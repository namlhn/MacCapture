import Combine
import CoreGraphics
import Foundation

@MainActor
public final class CaptureCoordinator: ObservableObject {
    @Published public private(set) var state: CaptureState = .idle
    @Published public private(set) var latestDocument: CaptureDocument?
    @Published public private(set) var lastError: CaptureError?

    private let permissionManager: PermissionManaging
    private let captureEngine: CaptureEngineProtocol
    private let regionSelector: RegionSelecting
    private let windowSelector: WindowSelecting
    private let scrollingCapturer: ScrollingCapturing

    public var onHideAppChromeForCapture: (() -> Void)?
    public var onRestoreAppChromeAfterCapture: (() -> Void)?
    public var onDocumentCaptured: ((CaptureDocument) -> Void)?
    public var onPermissionDenied: ((CaptureMode) -> Void)?

    public init(
        permissionManager: PermissionManaging,
        captureEngine: CaptureEngineProtocol,
        regionSelector: RegionSelecting,
        windowSelector: WindowSelecting,
        scrollingCapturer: ScrollingCapturing? = nil
    ) {
        self.permissionManager = permissionManager
        self.captureEngine = captureEngine
        self.regionSelector = regionSelector
        self.windowSelector = windowSelector
        self.scrollingCapturer = scrollingCapturer ?? ScrollingCaptureController()
    }

    public func startCapture(
        mode: CaptureMode,
        delay: CaptureDelay = .none,
        preferredDisplayID: UInt32? = nil
    ) async {
        guard !state.isBusy else { return }
        lastError = nil
        state = .checkingPermission(mode)

        let hasPermission: Bool
        switch permissionManager.currentStatus() {
        case .granted:
            hasPermission = true
        case .notDetermined, .denied:
            hasPermission = await permissionManager.requestAccess()
        }

        guard hasPermission else {
            state = .permissionHelp(mode)
            lastError = .permissionDenied
            onPermissionDenied?(mode)
            return
        }

        if delay.rawValue > 0 {
            for remaining in stride(from: delay.rawValue, through: 1, by: -1) {
                state = .countdown(mode, remainingSeconds: remaining)
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    cleanupAndResetToIdle()
                    return
                }
            }
        }

        onHideAppChromeForCapture?()
        // Allow window server a brief tick to hide floating toolbar before overlay/capture
        try? await Task.sleep(nanoseconds: 35_000_000)

        do {
            let capturedImage: CGImage
            switch mode {
            case .fullscreen:
                state = .capturingFullscreen
                let displays = try await captureEngine.listDisplays()
                let targetID: UInt32
                if let preferredDisplayID, displays.contains(where: { $0.id == preferredDisplayID }) {
                    targetID = preferredDisplayID
                } else if let primary = displays.first(where: { $0.isPrimary }) {
                    targetID = primary.id
                } else if let first = displays.first {
                    targetID = first.id
                } else {
                    throw CaptureError.noDisplaysAvailable
                }
                state = .capturing(.fullscreen)
                capturedImage = try await captureEngine.captureDisplay(id: targetID)

            case .region:
                state = .selectingRegion
                let displays = try await captureEngine.listDisplays()
                let selection = try await regionSelector.selectRegion(displays: displays)
                state = .capturing(.region)
                capturedImage = try await captureEngine.captureRegion(
                    displayID: selection.displayID,
                    rectInPixels: selection.rectInPixels
                )

            case .window:
                state = .selectingWindow
                let displays = try await captureEngine.listDisplays()
                let windows = try await captureEngine.listWindows()
                let selectedWindowID = try await windowSelector.selectWindow(windows: windows, displays: displays)
                state = .capturing(.window)
                capturedImage = try await captureEngine.captureWindow(id: selectedWindowID)

            case .scrolling:
                state = .selectingWindow
                let displays = try await captureEngine.listDisplays()
                let windows = try await captureEngine.listWindows()
                let selectedWindowID = try await windowSelector.selectWindow(windows: windows, displays: displays)
                guard let targetWindow = windows.first(where: { $0.id == selectedWindowID }) else {
                    throw CaptureError.windowNotFound(selectedWindowID)
                }
                let clickPoint = (windowSelector as? WindowSelectionController)?.lastSelectedClickPointInAppKit
                let targetDisplay = displays.first(where: {
                    $0.frameInPoints.intersects(targetWindow.frameInPoints)
                }) ?? displays.first(where: { $0.isPrimary }) ?? displays.first
                guard let resolvedDisplay = targetDisplay else {
                    throw CaptureError.noDisplaysAvailable
                }
                state = .capturing(.scrolling)
                capturedImage = try await scrollingCapturer.captureScrollingWindow(
                    window: targetWindow,
                    clickPointInAppKit: clickPoint,
                    display: resolvedDisplay,
                    captureEngine: captureEngine
                )
            }

            let document = CaptureDocument(baseImage: capturedImage)
            latestDocument = document
            state = .editing(document.id)
            onRestoreAppChromeAfterCapture?()
            onDocumentCaptured?(document)
        } catch let captureError as CaptureError {
            regionSelector.cleanup()
            windowSelector.cleanup()
            scrollingCapturer.cleanup()
            onRestoreAppChromeAfterCapture?()
            if captureError == .cancelled {
                state = .idle
            } else {
                lastError = captureError
                state = .error(captureError)
            }
        } catch {
            regionSelector.cleanup()
            windowSelector.cleanup()
            scrollingCapturer.cleanup()
            onRestoreAppChromeAfterCapture?()
            let wrapped = CaptureError.captureFailed(error.localizedDescription)
            lastError = wrapped
            state = .error(wrapped)
        }
    }

    public func cancelActiveOperation() {
        regionSelector.cleanup()
        windowSelector.cleanup()
        scrollingCapturer.cleanup()
        onRestoreAppChromeAfterCapture?()
        state = .idle
    }

    public func openDocumentInEditor(_ document: CaptureDocument) {
        latestDocument = document
        state = .editing(document.id)
        onDocumentCaptured?(document)
    }

    public func finishEditing() {
        state = .idle
    }

    public func dismissError() {
        lastError = nil
        state = .idle
    }

    private func cleanupAndResetToIdle() {
        regionSelector.cleanup()
        windowSelector.cleanup()
        scrollingCapturer.cleanup()
        onRestoreAppChromeAfterCapture?()
        state = .idle
    }
}
