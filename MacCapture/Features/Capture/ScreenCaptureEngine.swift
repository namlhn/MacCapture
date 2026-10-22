import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

public final class ScreenCaptureEngine: CaptureEngineProtocol, @unchecked Sendable {
    private let cacheLock = NSLock()
    private var cachedWindowFilter: (windowID: UInt32, filter: SCContentFilter, width: Int, height: Int, timestamp: TimeInterval)?

    public init() {}

    public func listDisplays() async throws -> [CaptureDisplay] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.permissionDenied
        }

        let nsScreensByID = await MainActor.run { () -> [UInt32: (name: String, frame: CGRect, visibleFrame: CGRect, scale: CGFloat)] in
            var map: [UInt32: (String, CGRect, CGRect, CGFloat)] = [:]
            for screen in NSScreen.screens {
                let id = FloatingToolbarPanel.displayID(for: screen)
                map[id] = (screen.localizedName, screen.frame, screen.visibleFrame, screen.backingScaleFactor)
            }
            return map
        }

        let mainID = CGMainDisplayID()
        let displays: [CaptureDisplay] = content.displays.map { scDisplay in
            let id = scDisplay.displayID
            if let nsInfo = nsScreensByID[id] {
                let pixelWidth = Int((nsInfo.frame.width * nsInfo.scale).rounded())
                let pixelHeight = Int((nsInfo.frame.height * nsInfo.scale).rounded())
                return CaptureDisplay(
                    id: id,
                    name: nsInfo.name,
                    frameInPoints: nsInfo.frame,
                    visibleFrameInPoints: nsInfo.visibleFrame,
                    pixelWidth: max(pixelWidth, scDisplay.width),
                    pixelHeight: max(pixelHeight, scDisplay.height),
                    scaleFactor: nsInfo.scale,
                    isPrimary: id == mainID
                )
            } else {
                let bounds = CGDisplayBounds(id)
                return CaptureDisplay(
                    id: id,
                    name: "Display \(id)",
                    frameInPoints: bounds,
                    visibleFrameInPoints: bounds,
                    pixelWidth: scDisplay.width,
                    pixelHeight: scDisplay.height,
                    scaleFactor: 1.0,
                    isPrimary: id == mainID
                )
            }
        }

        guard !displays.isEmpty else {
            throw CaptureError.noDisplaysAvailable
        }
        return displays
    }

    public func listWindows() async throws -> [CaptureWindow] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.permissionDenied
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let primaryHeight = await MainActor.run {
            NSScreen.screens.first(where: { FloatingToolbarPanel.displayID(for: $0) == CGMainDisplayID() })?.frame.height
                ?? NSScreen.main?.frame.height
                ?? 1080
        }

        return content.windows.compactMap { scWindow -> CaptureWindow? in
            guard scWindow.isOnScreen,
                  scWindow.windowLayer == 0,
                  scWindow.frame.width >= 32,
                  scWindow.frame.height >= 32 else {
                return nil
            }
            let ownerPID = scWindow.owningApplication?.processID ?? 0
            if ownerPID == currentPID {
                return nil
            }
            let ownerName = scWindow.owningApplication?.applicationName ?? "Application"
            let bundleID = scWindow.owningApplication?.bundleIdentifier
            let appKitFrame = CoordinateConverter.coreGraphicsGlobalRectToAppKitRect(
                scWindow.frame,
                primaryDisplayHeightInPoints: primaryHeight
            )
            return CaptureWindow(
                id: scWindow.windowID,
                title: scWindow.title ?? "",
                ownerName: ownerName,
                ownerPID: ownerPID,
                bundleIdentifier: bundleID,
                frameInPoints: appKitFrame,
                layer: scWindow.windowLayer,
                isOnScreen: scWindow.isOnScreen
            )
        }
    }

    public func captureDisplay(id: UInt32) async throws -> CGImage {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.permissionDenied
        }

        guard let scDisplay = content.displays.first(where: { $0.displayID == id }) else {
            throw CaptureError.displayNotFound(id)
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == currentPID }
        let filter = SCContentFilter(display: scDisplay, excludingWindows: ownWindows)

        let scale = await MainActor.run { () -> CGFloat in
            NSScreen.screens.first(where: { FloatingToolbarPanel.displayID(for: $0) == id })?.backingScaleFactor ?? 2.0
        }

        let config = SCStreamConfiguration()
        config.width = Int((CGFloat(scDisplay.width) * scale).rounded())
        config.height = Int((CGFloat(scDisplay.height) * scale).rounded())
        config.scalesToFit = false
        config.showsCursor = false
        config.capturesAudio = false

        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }
    }

    public func captureWindow(id: UInt32) async throws -> CGImage {
        let now = ProcessInfo.processInfo.systemUptime
        let cached: (filter: SCContentFilter, width: Int, height: Int)? = {
            cacheLock.lock()
            defer { cacheLock.unlock() }
            if let entry = cachedWindowFilter, entry.windowID == id, (now - entry.timestamp) < 15.0 {
                return (entry.filter, entry.width, entry.height)
            }
            return nil
        }()

        let filter: SCContentFilter
        let targetWidth: Int
        let targetHeight: Int

        if let cached {
            filter = cached.filter
            targetWidth = cached.width
            targetHeight = cached.height
        } else {
            let content: SCShareableContent
            do {
                content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            } catch {
                throw CaptureError.permissionDenied
            }

            guard let scWindow = content.windows.first(where: { $0.windowID == id }) else {
                throw CaptureError.windowNotFound(id)
            }

            let newFilter = SCContentFilter(desktopIndependentWindow: scWindow)
            let scale = await MainActor.run { () -> CGFloat in
                NSScreen.main?.backingScaleFactor ?? 2.0
            }
            let w = max(Int((scWindow.frame.width * scale).rounded()), 1)
            let h = max(Int((scWindow.frame.height * scale).rounded()), 1)

            cacheLock.lock()
            cachedWindowFilter = (id, newFilter, w, h, now)
            cacheLock.unlock()

            filter = newFilter
            targetWidth = w
            targetHeight = h
        }

        let config = SCStreamConfiguration()
        config.width = targetWidth
        config.height = targetHeight
        config.scalesToFit = false
        config.showsCursor = false
        config.capturesAudio = false

        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            cacheLock.lock()
            cachedWindowFilter = nil
            cacheLock.unlock()
            throw CaptureError.captureFailed(error.localizedDescription)
        }
    }

    public func captureRegion(displayID: UInt32, rectInPixels: CGRect) async throws -> CGImage {
        guard CoordinateConverter.isValidSelection(pixelRect: rectInPixels) else {
            throw CaptureError.selectionTooSmall
        }

        let displayImage = try await captureDisplay(id: displayID)
        let imageBounds = CGRect(x: 0, y: 0, width: displayImage.width, height: displayImage.height)
        let clampedCrop = CoordinateConverter.clampRect(rectInPixels.integral, to: imageBounds)

        guard CoordinateConverter.isValidSelection(pixelRect: clampedCrop),
              let cropped = displayImage.cropping(to: clampedCrop) else {
            throw CaptureError.captureFailed("Selected region lies outside display pixel bounds.")
        }
        return cropped
    }
}
