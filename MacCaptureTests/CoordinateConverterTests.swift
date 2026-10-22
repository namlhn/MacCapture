import CoreGraphics
import Foundation
import XCTest
#if canImport(MacCapture)
@testable import MacCapture
#endif

final class CoordinateConverterTests: XCTestCase {
    func testNormalizedDragRectInAllFourDirections() {
        let p1 = CGPoint(x: 100, y: 200)
        let p2 = CGPoint(x: 350, y: 450)

        let topLeftToBottomRight = CoordinateConverter.normalizedDragRect(from: p1, to: p2)
        let bottomRightToTopLeft = CoordinateConverter.normalizedDragRect(from: p2, to: p1)
        let bottomLeftToTopRight = CoordinateConverter.normalizedDragRect(
            from: CGPoint(x: 100, y: 450),
            to: CGPoint(x: 350, y: 200)
        )
        let topRightToBottomLeft = CoordinateConverter.normalizedDragRect(
            from: CGPoint(x: 350, y: 200),
            to: CGPoint(x: 100, y: 450)
        )

        let expected = CGRect(x: 100, y: 200, width: 250, height: 250)
        XCTAssertEqual(topLeftToBottomRight, expected)
        XCTAssertEqual(bottomRightToTopLeft, expected)
        XCTAssertEqual(bottomLeftToTopRight, expected)
        XCTAssertEqual(topRightToBottomLeft, expected)
    }

    func testClampRectWithNegativeOriginDisplay() {
        let externalBounds = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let selection = CGRect(x: -2050, y: -100, width: 500, height: 400)

        let clamped = CoordinateConverter.clampRect(selection, to: externalBounds)
        XCTAssertEqual(clamped, CGRect(x: -1920, y: -100, width: 370, height: 400))
    }

    func testRetina2xPixelConversionFromAppKitBottomLeftToDisplayTopLeft() {
        let retinaDisplay = CaptureDisplay(
            id: 1,
            name: "Built-in Retina Display",
            frameInPoints: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrameInPoints: CGRect(x: 0, y: 50, width: 1440, height: 825),
            pixelWidth: 2880,
            pixelHeight: 1800,
            scaleFactor: 2.0,
            isPrimary: true
        )

        // Select a 200x100 pt region near the top-left of the AppKit screen (y from 750..850 means 50pt below top)
        let appKitRect = CGRect(x: 40, y: 750, width: 200, height: 100)
        let pixelRect = CoordinateConverter.appKitGlobalRectToDisplayPixelRect(appKitRect, display: retinaDisplay)

        // Top-left local points: x = 40, y = 900 - (750 + 100) = 50, w = 200, h = 100
        // At 2x scale: x = 80, y = 100, w = 400, h = 200
        XCTAssertEqual(pixelRect, CGRect(x: 80, y: 100, width: 400, height: 200))
    }

    func testExternalMonitor1xWithNegativeOriginPixelConversion() {
        let externalDisplay = CaptureDisplay(
            id: 2,
            name: "External 1080p",
            frameInPoints: CGRect(x: -1920, y: -180, width: 1920, height: 1080),
            visibleFrameInPoints: CGRect(x: -1920, y: -180, width: 1920, height: 1055),
            pixelWidth: 1920,
            pixelHeight: 1080,
            scaleFactor: 1.0,
            isPrimary: false
        )

        // Selection at (-1820, 700, 300, 150) inside (-1920..-0, -180..900)
        // localX = -1820 - (-1920) = 100
        // localYFromBottom = 700 - (-180) = 880 -> topLeftY = 1080 - (880 + 150) = 50
        let appKitRect = CGRect(x: -1820, y: 700, width: 300, height: 150)
        let pixelRect = CoordinateConverter.appKitGlobalRectToDisplayPixelRect(appKitRect, display: externalDisplay)

        XCTAssertEqual(pixelRect, CGRect(x: 100, y: 50, width: 300, height: 150))
    }

    func testCoreGraphicsAndAppKitGlobalCoordinateRoundTrip() {
        let primaryHeight: CGFloat = 1080
        let cgWindowFrame = CGRect(x: 120, y: 80, width: 800, height: 600)

        let appKitFrame = CoordinateConverter.coreGraphicsGlobalRectToAppKitRect(
            cgWindowFrame,
            primaryDisplayHeightInPoints: primaryHeight
        )
        XCTAssertEqual(appKitFrame, CGRect(x: 120, y: 400, width: 800, height: 600))

        let roundTrip = CoordinateConverter.appKitGlobalRectToCoreGraphicsRect(
            appKitFrame,
            primaryDisplayHeightInPoints: primaryHeight
        )
        XCTAssertEqual(roundTrip, cgWindowFrame)
    }

    func testMinimumSelectionThreshold() {
        XCTAssertFalse(CoordinateConverter.isValidSelection(pixelRect: CGRect(x: 0, y: 0, width: 3, height: 10)))
        XCTAssertFalse(CoordinateConverter.isValidSelection(pixelRect: CGRect(x: 0, y: 0, width: 10, height: 3)))
        XCTAssertTrue(CoordinateConverter.isValidSelection(pixelRect: CGRect(x: 0, y: 0, width: 4, height: 4)))
    }

    func testToolbarPositionPersistenceAndDisconnectedDisplayFallback() {
        let store = ToolbarPositionStore(defaults: nil)
        let panelSize = CGSize(width: 360, height: 44)

        let primary = CaptureDisplay(
            id: 1,
            name: "Primary",
            frameInPoints: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrameInPoints: CGRect(x: 0, y: 40, width: 1440, height: 835),
            pixelWidth: 2880,
            pixelHeight: 1800,
            scaleFactor: 2.0,
            isPrimary: true
        )
        let secondary = CaptureDisplay(
            id: 2,
            name: "External",
            frameInPoints: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
            visibleFrameInPoints: CGRect(x: 1440, y: 0, width: 1920, height: 1055),
            pixelWidth: 1920,
            pixelHeight: 1080,
            scaleFactor: 1.0,
            isPrimary: false
        )

        // Save toolbar on secondary display
        let savedFrame = CGRect(x: 1800, y: 500, width: 360, height: 44)
        store.save(panelFrame: savedFrame, visibleFrame: secondary.visibleFrameInPoints, displayID: secondary.id)

        let restoredWithSecondary = store.resolvedFrame(
            panelSize: panelSize,
            availableDisplays: [primary, secondary]
        )
        XCTAssertEqual(restoredWithSecondary.origin.x, 1800, accuracy: 1.0)
        XCTAssertEqual(restoredWithSecondary.origin.y, 500, accuracy: 1.0)

        // Unplug secondary display -> must fall back and clamp inside primary visibleFrame
        let restoredFallback = store.resolvedFrame(
            panelSize: panelSize,
            availableDisplays: [primary]
        )
        XCTAssertTrue(primary.visibleFrameInPoints.contains(restoredFallback))
    }
}
