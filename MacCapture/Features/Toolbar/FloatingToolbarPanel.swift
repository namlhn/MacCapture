import AppKit
import Combine
import SwiftUI

@MainActor
public final class FloatingToolbarPanel: NSPanel {
    private let viewModel: ToolbarViewModel
    private let positionStore: ToolbarPositionStore
    private var cancellables: Set<AnyCancellable> = []

    public init(
        viewModel: ToolbarViewModel,
        positionStore: ToolbarPositionStore = ToolbarPositionStore()
    ) {
        self.viewModel = viewModel
        self.positionStore = positionStore

        let initialSize = viewModel.preferences.toolbarScale.panelSize
        let initialRect = CGRect(origin: .zero, size: initialSize)

        super.init(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.animationBehavior = .utilityWindow

        let rootView = ToolbarView(
            viewModel: viewModel,
            onDragDelta: { [weak self] delta in
                self?.moveBy(delta: delta)
            },
            onDragEnded: { [weak self] in
                self?.persistCurrentPosition()
            }
        )
        self.contentView = NSHostingView(rootView: rootView)

        applyPreferences()
        restoreOrResetPosition(resetToDefault: false)
        observeChanges()
    }

    override public var canBecomeKey: Bool {
        true
    }

    override public var canBecomeMain: Bool {
        false
    }

    public func showToolbar() {
        viewModel.showToolbar()
        restoreOrResetPosition(resetToDefault: false)
        orderFrontRegardless()
    }

    public func hideToolbar() {
        viewModel.isVisible = false
        orderOut(nil)
    }

    public func resetPosition() {
        positionStore.clear()
        restoreOrResetPosition(resetToDefault: true)
    }

    public func clampToAvailableScreens() {
        let displays = Self.currentNSScreenDisplays()
        viewModel.availableDisplays = displays
        let targetSize = viewModel.isCollapsedToEdge
            ? CGSize(width: 38, height: 46)
            : viewModel.preferences.toolbarScale.panelSize
        let resolved = positionStore.resolvedFrame(
            panelSize: targetSize,
            availableDisplays: displays
        )
        setFrame(resolved, display: true)
    }

    private func applyPreferences() {
        let prefs = viewModel.preferences
        self.level = prefs.alwaysOnTop ? .floating : .normal

        var behavior: NSWindow.CollectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        if prefs.showOnAllSpaces {
            behavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        }
        self.collectionBehavior = behavior
        self.appearance = prefs.theme.appearance

        let targetSize = viewModel.isCollapsedToEdge
            ? CGSize(width: 38, height: 46)
            : prefs.toolbarScale.panelSize
        var updatedFrame = self.frame
        updatedFrame.size = targetSize
        if let screen = self.screen ?? NSScreen.main {
            updatedFrame = ToolbarPositionStore.clamp(frame: updatedFrame, to: screen.visibleFrame)
        }
        setFrame(updatedFrame, display: true)
    }

    private func moveBy(delta: CGSize) {
        var nextOrigin = self.frame.origin
        nextOrigin.x += delta.width
        nextOrigin.y -= delta.height
        var candidate = CGRect(origin: nextOrigin, size: self.frame.size)
        if let screen = self.screen ?? NSScreen.main {
            candidate = ToolbarPositionStore.clamp(frame: candidate, to: screen.visibleFrame)
        }
        setFrameOrigin(candidate.origin)
    }

    private func persistCurrentPosition() {
        guard let screen = self.screen ?? NSScreen.main else { return }
        let displayID = Self.displayID(for: screen)
        let clamped = ToolbarPositionStore.clamp(frame: self.frame, to: screen.visibleFrame)
        setFrame(clamped, display: false)
        positionStore.save(
            panelFrame: clamped,
            visibleFrame: screen.visibleFrame,
            displayID: displayID
        )

        if viewModel.preferences.autoHideToEdge {
            let nearRightEdge = abs(clamped.maxX - screen.visibleFrame.maxX) <= 6
            let nearLeftEdge = abs(clamped.minX - screen.visibleFrame.minX) <= 6
            if nearRightEdge || nearLeftEdge {
                viewModel.isCollapsedToEdge = true
                applyPreferences()
            }
        }
    }

    private func restoreOrResetPosition(resetToDefault: Bool) {
        let displays = Self.currentNSScreenDisplays()
        viewModel.availableDisplays = displays
        let size = viewModel.preferences.toolbarScale.panelSize

        if resetToDefault {
            if let screen = self.screen ?? NSScreen.main {
                let defaultFrame = ToolbarPositionStore.defaultFrame(
                    panelSize: size,
                    in: screen.visibleFrame
                )
                setFrame(defaultFrame, display: true)
                positionStore.save(
                    panelFrame: defaultFrame,
                    visibleFrame: screen.visibleFrame,
                    displayID: Self.displayID(for: screen)
                )
            }
            return
        }

        let resolved = positionStore.resolvedFrame(
            panelSize: size,
            availableDisplays: displays
        )
        setFrame(resolved, display: true)
    }

    private func observeChanges() {
        viewModel.preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.applyPreferences()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.clampToAvailableScreens()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: self)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.persistCurrentPosition()
            }
            .store(in: &cancellables)
    }

    public static func displayID(for screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    public static func currentNSScreenDisplays() -> [CaptureDisplay] {
        let mainID = CGMainDisplayID()
        return NSScreen.screens.map { screen in
            let id = displayID(for: screen)
            let scale = screen.backingScaleFactor
            let pixelWidth = Int((screen.frame.width * scale).rounded())
            let pixelHeight = Int((screen.frame.height * scale).rounded())
            return CaptureDisplay(
                id: id,
                name: screen.localizedName,
                frameInPoints: screen.frame,
                visibleFrameInPoints: screen.visibleFrame,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                scaleFactor: scale,
                isPrimary: id == mainID
            )
        }
    }
}
