import CoreGraphics
import Foundation

public enum CoordinateConverter {
    public static let minimumSelectionPixels: CGFloat = 4.0

    /// Normalizes a rectangle dragged between two arbitrary points (supporting all 4 drag directions).
    public static func normalizedDragRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    /// Clamps a selection rectangle to remain within the given bounds (supports negative display origins).
    public static func clampRect(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let standardized = rect.standardized
        let intersection = standardized.intersection(bounds)
        if intersection.isNull {
            return CGRect(origin: bounds.origin, size: .zero)
        }
        return intersection
    }

    /// Converts a global AppKit rectangle (origin bottom-left of primary screen, Y up)
    /// into display-local top-left coordinates in points (origin top-left of target display, Y down).
    public static func appKitGlobalRectToDisplayTopLeftPoints(
        _ appKitGlobalRect: CGRect,
        displayFrameInAppKitPoints: CGRect
    ) -> CGRect {
        let clamped = clampRect(appKitGlobalRect, to: displayFrameInAppKitPoints)
        guard clamped.width > 0, clamped.height > 0 else {
            return .zero
        }

        let localX = clamped.minX - displayFrameInAppKitPoints.minX
        let localYFromBottom = clamped.minY - displayFrameInAppKitPoints.minY
        let topLeftY = displayFrameInAppKitPoints.height - (localYFromBottom + clamped.height)

        return CGRect(
            x: localX,
            y: topLeftY,
            width: clamped.width,
            height: clamped.height
        )
    }

    /// Converts a global AppKit rectangle into an integral backing-pixel rectangle relative to the display's top-left corner.
    public static func appKitGlobalRectToDisplayPixelRect(
        _ appKitGlobalRect: CGRect,
        display: CaptureDisplay
    ) -> CGRect {
        let topLeftPoints = appKitGlobalRectToDisplayTopLeftPoints(
            appKitGlobalRect,
            displayFrameInAppKitPoints: display.frameInPoints
        )
        guard topLeftPoints.width > 0, topLeftPoints.height > 0 else {
            return .zero
        }

        let scale = max(display.scaleFactor, 1.0)
        let rawMinX = (topLeftPoints.minX * scale).rounded(.down)
        let rawMinY = (topLeftPoints.minY * scale).rounded(.down)
        let rawMaxX = (topLeftPoints.maxX * scale).rounded(.up)
        let rawMaxY = (topLeftPoints.maxY * scale).rounded(.up)

        let maxPixelWidth = CGFloat(display.pixelWidth)
        let maxPixelHeight = CGFloat(display.pixelHeight)

        let clampedMinX = min(max(rawMinX, 0), maxPixelWidth)
        let clampedMinY = min(max(rawMinY, 0), maxPixelHeight)
        let clampedMaxX = min(max(rawMaxX, clampedMinX), maxPixelWidth)
        let clampedMaxY = min(max(rawMaxY, clampedMinY), maxPixelHeight)

        return CGRect(
            x: clampedMinX,
            y: clampedMinY,
            width: clampedMaxX - clampedMinX,
            height: clampedMaxY - clampedMinY
        )
    }

    /// Converts a CoreGraphics global rect (origin top-left of primary display, Y down)
    /// to an AppKit global rect (origin bottom-left of primary display, Y up).
    public static func coreGraphicsGlobalRectToAppKitRect(
        _ cgRect: CGRect,
        primaryDisplayHeightInPoints: CGFloat
    ) -> CGRect {
        let appKitY = primaryDisplayHeightInPoints - (cgRect.origin.y + cgRect.height)
        return CGRect(
            x: cgRect.origin.x,
            y: appKitY,
            width: cgRect.width,
            height: cgRect.height
        )
    }

    /// Converts an AppKit global rect to a CoreGraphics global rect.
    public static func appKitGlobalRectToCoreGraphicsRect(
        _ appKitRect: CGRect,
        primaryDisplayHeightInPoints: CGFloat
    ) -> CGRect {
        let cgY = primaryDisplayHeightInPoints - (appKitRect.origin.y + appKitRect.height)
        return CGRect(
            x: appKitRect.origin.x,
            y: cgY,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }

    /// Validates whether a pixel selection meets the minimum 4×4 pixel threshold.
    public static func isValidSelection(
        pixelRect: CGRect,
        minimumDimension: CGFloat = minimumSelectionPixels
    ) -> Bool {
        pixelRect.width >= minimumDimension && pixelRect.height >= minimumDimension
    }
}
