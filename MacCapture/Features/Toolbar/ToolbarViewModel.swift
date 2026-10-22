import Combine
import CoreGraphics
import Foundation

@MainActor
public final class ToolbarViewModel: ObservableObject {
    @Published public var isVisible: Bool = true
    @Published public var isCollapsedToEdge: Bool = false
    @Published public var availableDisplays: [CaptureDisplay] = []
    @Published public var countdownSeconds: Int?
    @Published public var isRecording: Bool = false

    public let preferences: PreferencesStore

    public var onCaptureRequested: ((CaptureMode, UInt32?) -> Void)?
    public var onRecordingRequested: ((RecordingMode, UInt32?) -> Void)?
    public var onOpenEditorRequested: (() -> Void)?
    public var onOpenPreferencesRequested: (() -> Void)?
    public var onHideRequested: (() -> Void)?
    public var onResetPositionRequested: (() -> Void)?
    public var onQuitRequested: (() -> Void)?

    public init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    public func triggerCapture(_ mode: CaptureMode, displayID: UInt32? = nil) {
        onCaptureRequested?(mode, displayID)
    }

    public func triggerRecording(_ mode: RecordingMode, displayID: UInt32? = nil) {
        onRecordingRequested?(mode, displayID)
    }

    public func selectDelay(_ delay: CaptureDelay) {
        preferences.captureDelay = delay
    }

    public func hideToolbar() {
        isVisible = false
        onHideRequested?()
    }

    public func showToolbar() {
        isVisible = true
        isCollapsedToEdge = false
    }

    public func resetPosition() {
        isCollapsedToEdge = false
        onResetPositionRequested?()
    }

    public func shortcutLabel(for action: HotkeyAction) -> String {
        preferences.hotkeys[action]?.displayString ?? ""
    }
}
