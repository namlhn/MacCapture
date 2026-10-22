import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

public enum PermissionStatus: String, Equatable, Sendable {
    case granted
    case denied
    case notDetermined
}

@MainActor
public protocol PermissionManaging: AnyObject {
    func currentStatus() -> PermissionStatus
    func requestAccess() async -> Bool
    func openSystemSettings()
}

@MainActor
public final class PermissionManager: PermissionManaging {
    private var hasPromptedThisSession = false

    public init() {}

    public func currentStatus() -> PermissionStatus {
        if CGPreflightScreenCaptureAccess() {
            return .granted
        }
        return hasPromptedThisSession ? .denied : .notDetermined
    }

    public func requestAccess() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        hasPromptedThisSession = true
        let granted = CGRequestScreenCaptureAccess()
        if granted {
            return true
        }
        // Verify with ScreenCaptureKit shareable content enumeration in case permission was just toggled
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    public func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
