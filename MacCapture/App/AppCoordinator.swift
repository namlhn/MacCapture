import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
public final class AppCoordinator {
    public let preferences: PreferencesStore
    public let permissionManager: PermissionManaging
    public let hotkeyManager: HotkeyManager
    public let toolbarViewModel: ToolbarViewModel
    public let toolbarPanel: FloatingToolbarPanel
    public let captureCoordinator: CaptureCoordinator
    public let menuBarController: MenuBarController
    public let recordingController: RecordingController

    private var editorWindowController: EditorWindowController?
    private var preferencesWindow: NSWindow?
    private var wasToolbarVisibleBeforeCapture = true
    private var cancellables: Set<AnyCancellable> = []

    public init(
        preferences: PreferencesStore? = nil,
        permissionManager: PermissionManaging? = nil,
        captureEngine: CaptureEngineProtocol? = nil,
        regionSelector: RegionSelecting? = nil,
        windowSelector: WindowSelecting? = nil
    ) {
        let resolvedPreferences = preferences ?? PreferencesStore()
        let resolvedPermissionManager = permissionManager ?? PermissionManager()
        let resolvedCaptureEngine = captureEngine ?? ScreenCaptureEngine()
        let resolvedRegionSelector = regionSelector ?? RegionOverlayController()
        let resolvedWindowSelector = windowSelector ?? WindowSelectionController()

        self.preferences = resolvedPreferences
        self.permissionManager = resolvedPermissionManager
        self.hotkeyManager = HotkeyManager()
        self.toolbarViewModel = ToolbarViewModel(preferences: resolvedPreferences)
        self.toolbarPanel = FloatingToolbarPanel(viewModel: toolbarViewModel)
        self.captureCoordinator = CaptureCoordinator(
            permissionManager: resolvedPermissionManager,
            captureEngine: resolvedCaptureEngine,
            regionSelector: resolvedRegionSelector,
            windowSelector: resolvedWindowSelector
        )
        self.menuBarController = MenuBarController()
        self.recordingController = RecordingController(
            permissionManager: resolvedPermissionManager,
            captureEngine: resolvedCaptureEngine,
            regionSelector: RegionOverlayController()
        )

        wireCallbacks()
    }

    public func start() {
        hotkeyManager.updateBindings(preferences.hotkeys)

        if preferences.showToolbarOnStartup {
            toolbarPanel.showToolbar()
        } else {
            toolbarPanel.hideToolbar()
        }
        menuBarController.refreshMenuLabels()

        if ProcessInfo.processInfo.arguments.contains("--ui-testing-open-editor") {
            openEditorWithSyntheticOrBlankDocument()
        }
    }

    public func toggleToolbar() {
        if toolbarViewModel.isVisible {
            toolbarPanel.hideToolbar()
        } else {
            toolbarPanel.showToolbar()
        }
        menuBarController.refreshMenuLabels()
    }

    public func openEditorWithSyntheticOrBlankDocument() {
        if let latest = captureCoordinator.latestDocument {
            presentEditor(with: latest)
            return
        }
        if let placeholder = ImageRenderer.makeSyntheticImage(
            width: 1280,
            height: 720,
            fill: RGBAColor(red: 0.14, green: 0.18, blue: 0.24)
        ) {
            let doc = CaptureDocument(baseImage: placeholder)
            presentEditor(with: doc)
        }
    }

    public func showPreferencesWindow() {
        if let window = preferencesWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = PreferencesView(
            preferences: preferences,
            onResetToolbarPosition: { [weak self] in
                self?.toolbarPanel.resetPosition()
            },
            onOpenScreenPermissions: { [weak self] in
                self?.permissionManager.openSystemSettings()
            }
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 480, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacCapture Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        self.preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func showAboutDialog() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "MacCapture",
            .applicationVersion: "0.3.0",
            .credits: NSAttributedString(
                string: "Lightweight native macOS screen capture, scrolling capture, screen recording, and vector annotation toolbar."
            ),
        ])
    }

    private func wireCallbacks() {
        toolbarViewModel.onCaptureRequested = { [weak self] mode, displayID in
            guard let self else { return }
            Task { @MainActor in
                await self.captureCoordinator.startCapture(
                    mode: mode,
                    delay: self.preferences.captureDelay,
                    preferredDisplayID: displayID
                )
            }
        }

        toolbarViewModel.onRecordingRequested = { [weak self] mode, displayID in
            guard let self else { return }
            let audioOptions = RecordingAudioOptions(
                recordSystemAudio: self.preferences.recordSystemAudio,
                recordMicrophone: self.preferences.recordMicrophone
            )
            Task { @MainActor in
                await self.recordingController.toggle(
                    mode: mode,
                    delay: self.preferences.captureDelay,
                    audioOptions: audioOptions,
                    preferredDisplayID: displayID
                )
            }
        }

        menuBarController.isRecordingProvider = { [weak self] in
            self?.recordingController.isActive ?? false
        }

        menuBarController.isSystemAudioEnabledProvider = { [weak self] in
            self?.preferences.recordSystemAudio ?? true
        }

        menuBarController.isMicrophoneEnabledProvider = { [weak self] in
            self?.preferences.recordMicrophone ?? true
        }

        menuBarController.onToggleSystemAudio = { [weak self] in
            guard let self else { return }
            self.preferences.recordSystemAudio.toggle()
        }

        menuBarController.onToggleMicrophone = { [weak self] in
            guard let self else { return }
            self.preferences.recordMicrophone.toggle()
        }

        menuBarController.onRecordingModeSelected = { [weak self] mode in
            guard let self else { return }
            let audioOptions = RecordingAudioOptions(
                recordSystemAudio: self.preferences.recordSystemAudio,
                recordMicrophone: self.preferences.recordMicrophone
            )
            Task { @MainActor in
                await self.recordingController.toggle(
                    mode: mode,
                    delay: self.preferences.captureDelay,
                    audioOptions: audioOptions
                )
            }
        }

        recordingController.onStateChanged = { [weak self] state in
            self?.toolbarViewModel.isRecording = (state == .recording)
            self?.menuBarController.refreshMenuLabels()
        }

        recordingController.onHideAppChrome = { [weak self] in
            guard let self else { return }
            self.wasToolbarVisibleBeforeCapture = self.toolbarViewModel.isVisible
            self.toolbarPanel.orderOut(nil)
        }

        recordingController.onRestoreAppChrome = { [weak self] in
            guard let self, self.wasToolbarVisibleBeforeCapture else { return }
            self.toolbarPanel.showToolbar()
        }

        recordingController.onPermissionDenied = { [weak self] mode in
            self?.presentRecordingPermissionHelpAlert(for: mode)
        }

        recordingController.onRecordingSaved = { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }

        recordingController.onError = { error in
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Screen Recording Failed"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }

        toolbarViewModel.onOpenEditorRequested = { [weak self] in
            self?.openEditorWithSyntheticOrBlankDocument()
        }

        toolbarViewModel.onOpenPreferencesRequested = { [weak self] in
            self?.showPreferencesWindow()
        }

        toolbarViewModel.onHideRequested = { [weak self] in
            self?.toolbarPanel.hideToolbar()
            self?.menuBarController.refreshMenuLabels()
        }

        toolbarViewModel.onResetPositionRequested = { [weak self] in
            self?.toolbarPanel.resetPosition()
        }

        toolbarViewModel.onQuitRequested = {
            NSApplication.shared.terminate(nil)
        }

        menuBarController.isToolbarVisibleProvider = { [weak self] in
            self?.toolbarViewModel.isVisible ?? false
        }

        menuBarController.onCaptureModeSelected = { [weak self] mode in
            guard let self else { return }
            Task { @MainActor in
                await self.captureCoordinator.startCapture(
                    mode: mode,
                    delay: self.preferences.captureDelay
                )
            }
        }

        menuBarController.onOpenEditorSelected = { [weak self] in
            guard let self else { return }
            if self.editorWindowController == nil {
                self.openEditorWithSyntheticOrBlankDocument()
            }
            self.editorWindowController?.openImageFilePicker()
        }

        menuBarController.onToggleToolbarSelected = { [weak self] in
            self?.toggleToolbar()
        }

        menuBarController.onOpenPreferencesSelected = { [weak self] in
            self?.showPreferencesWindow()
        }

        menuBarController.onShowAboutSelected = { [weak self] in
            self?.showAboutDialog()
        }

        menuBarController.onQuitSelected = {
            NSApplication.shared.terminate(nil)
        }

        hotkeyManager.onActionTriggered = { [weak self] action in
            guard let self else { return }
            switch action {
            case .captureRegion:
                Task { @MainActor in
                    await self.captureCoordinator.startCapture(mode: .region, delay: self.preferences.captureDelay)
                }
            case .captureWindow:
                Task { @MainActor in
                    await self.captureCoordinator.startCapture(mode: .window, delay: self.preferences.captureDelay)
                }
            case .captureFullscreen:
                Task { @MainActor in
                    await self.captureCoordinator.startCapture(mode: .fullscreen, delay: self.preferences.captureDelay)
                }
            case .captureScrolling:
                Task { @MainActor in
                    await self.captureCoordinator.startCapture(mode: .scrolling, delay: self.preferences.captureDelay)
                }
            case .toggleToolbar:
                self.toggleToolbar()
            }
        }

        preferences.$hotkeys
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] updated in
                self?.hotkeyManager.updateBindings(updated)
            }
            .store(in: &cancellables)

        captureCoordinator.onHideAppChromeForCapture = { [weak self] in
            guard let self else { return }
            self.wasToolbarVisibleBeforeCapture = self.toolbarViewModel.isVisible
            self.toolbarPanel.orderOut(nil)
        }

        captureCoordinator.onRestoreAppChromeAfterCapture = { [weak self] in
            guard let self else { return }
            if self.wasToolbarVisibleBeforeCapture {
                self.toolbarPanel.showToolbar()
            }
        }

        captureCoordinator.onDocumentCaptured = { [weak self] document in
            self?.presentEditor(with: document)
        }

        captureCoordinator.onPermissionDenied = { [weak self] mode in
            self?.presentPermissionHelpAlert(for: mode)
        }
    }

    private func presentEditor(with document: CaptureDocument) {
        if let existing = editorWindowController {
            existing.present(document: document)
        } else {
            let controller = EditorWindowController(document: document)
            controller.onWindowClosed = { [weak self] in
                self?.captureCoordinator.finishEditing()
            }
            self.editorWindowController = controller
            controller.present(document: document)
        }
    }

    private func presentPermissionHelpAlert(for mode: CaptureMode) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = """
        MacCapture needs Screen Recording permission to capture \(mode.displayName.lowercased()) screenshots. \
        Your screenshots stay 100% local on your Mac and are never uploaded.

        Please enable MacCapture in System Settings → Privacy & Security → Screen & System Audio Recording, then click Retry.
        """
        alert.addButton(withTitle: "Reset & Re-register Permission")
        alert.addButton(withTitle: "Relaunch App")
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            captureCoordinator.dismissError()
            permissionManager.resetAndRePromptAccess()
        case .alertSecondButtonReturn:
            captureCoordinator.dismissError()
            relaunchApp()
        case .alertThirdButtonReturn:
            permissionManager.openSystemSettings()
            captureCoordinator.dismissError()
        default:
            captureCoordinator.dismissError()
        }
    }

    private func presentRecordingPermissionHelpAlert(for mode: RecordingMode) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = """
        MacCapture needs Screen Recording permission to record the screen (\(mode.displayName)).

        If you already turned on MacCapture in System Settings but still see this message, click "Reset & Re-register Permission" below to clear the old cached signature, then turn the toggle back ON and click "Relaunch App".
        """
        alert.addButton(withTitle: "Reset & Re-register Permission")
        alert.addButton(withTitle: "Relaunch App")
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            permissionManager.resetAndRePromptAccess()
        case .alertSecondButtonReturn:
            relaunchApp()
        case .alertThirdButtonReturn:
            permissionManager.openSystemSettings()
        default:
            break
        }
    }

    private func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
