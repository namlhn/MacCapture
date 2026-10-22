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
    func resetAndRePromptAccess()
}

public extension PermissionManaging {
    func resetAndRePromptAccess() {}
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
        // Check with ScreenCaptureKit first in case permission was already granted or updated
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            // Fall through to prompt only once per session
        }
        guard !hasPromptedThisSession else {
            return false
        }
        hasPromptedThisSession = true
        if CGRequestScreenCaptureAccess() {
            return true
        }
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

    public func resetAndRePromptAccess() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.maccapture.app"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", bundleID]
        try? process.run()
        process.waitUntilExit()
        hasPromptedThisSession = false
        _ = CGRequestScreenCaptureAccess()
        openSystemSettings()
    }
}
