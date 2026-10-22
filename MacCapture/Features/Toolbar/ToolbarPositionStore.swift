import CoreGraphics
import Foundation

public struct SavedToolbarPosition: Codable, Equatable, Sendable {
    public let displayID: UInt32
    public let normalizedX: CGFloat
    public let normalizedY: CGFloat

    public init(displayID: UInt32, normalizedX: CGFloat, normalizedY: CGFloat) {
        self.displayID = displayID
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
    }
}

public final class ToolbarPositionStore {
    private let defaults: UserDefaults?
    private let storageKey = "maccapture.toolbar.savedPosition"
    private var inMemoryPosition: SavedToolbarPosition?

    public init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
    }

    public func load() -> SavedToolbarPosition? {
        if let inMemoryPosition {
            return inMemoryPosition
        }
        guard let data = defaults?.data(forKey: storageKey) else { return nil }
        let decoded = try? JSONDecoder().decode(SavedToolbarPosition.self, from: data)
        inMemoryPosition = decoded
        return decoded
    }

    public func save(panelFrame: CGRect, visibleFrame: CGRect, displayID: UInt32) {
        let clamped = Self.clamp(frame: panelFrame, to: visibleFrame)
        let availableWidth = max(visibleFrame.width - clamped.width, 1)
        let availableHeight = max(visibleFrame.height - clamped.height, 1)

        let normX = min(max((clamped.minX - visibleFrame.minX) / availableWidth, 0), 1)
        let normY = min(max((clamped.minY - visibleFrame.minY) / availableHeight, 0), 1)

        let saved = SavedToolbarPosition(
            displayID: displayID,
            normalizedX: normX,
            normalizedY: normY
        )
        inMemoryPosition = saved
        if let defaults, let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: storageKey)
        }
    }

    public func clear() {
        inMemoryPosition = nil
        defaults?.removeObject(forKey: storageKey)
    }

    public func resolvedFrame(
        panelSize: CGSize,
        availableDisplays: [CaptureDisplay]
    ) -> CGRect {
        guard !availableDisplays.isEmpty else {
            return CGRect(origin: CGPoint(x: 100, y: 100), size: panelSize)
        }

        let saved = load()
        let targetDisplay: CaptureDisplay
        if let saved, let matched = availableDisplays.first(where: { $0.id == saved.displayID }) {
            targetDisplay = matched
        } else if let primary = availableDisplays.first(where: { $0.isPrimary }) {
            targetDisplay = primary
        } else {
            targetDisplay = availableDisplays[0]
        }

        let visible = targetDisplay.visibleFrameInPoints
        guard let saved else {
            return Self.defaultFrame(panelSize: panelSize, in: visible)
        }

        let availableWidth = max(visible.width - panelSize.width, 0)
        let availableHeight = max(visible.height - panelSize.height, 0)
        let x = visible.minX + saved.normalizedX * availableWidth
        let y = visible.minY + saved.normalizedY * availableHeight
        let rawFrame = CGRect(origin: CGPoint(x: x, y: y), size: panelSize)
        return Self.clamp(frame: rawFrame, to: visible)
    }

    public static func defaultFrame(panelSize: CGSize, in visibleFrame: CGRect) -> CGRect {
        let topMargin: CGFloat = 24
        let x = visibleFrame.midX - panelSize.width / 2
        let y = visibleFrame.maxY - panelSize.height - topMargin
        let candidate = CGRect(origin: CGPoint(x: x, y: y), size: panelSize)
        return clamp(frame: candidate, to: visibleFrame)
    }

    public static func clamp(frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)

        let minX = visibleFrame.minX
        let maxX = max(visibleFrame.maxX - width, minX)
        let minY = visibleFrame.minY
        let maxY = max(visibleFrame.maxY - height, minY)

        let clampedX = min(max(frame.origin.x, minX), maxX)
        let clampedY = min(max(frame.origin.y, minY), maxY)

        return CGRect(x: clampedX, y: clampedY, width: width, height: height)
    }
}
