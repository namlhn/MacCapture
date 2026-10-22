import Carbon
import CoreGraphics
import Foundation
import XCTest
#if canImport(MacCapture)
@testable import MacCapture
#endif

@MainActor
final class CaptureCoordinatorTests: XCTestCase {
    private final class MockPermissionManager: PermissionManaging {
        var status: PermissionStatus = .granted
        var requestResult: Bool = true
        var openedSettingsCount = 0

        func currentStatus() -> PermissionStatus { status }
        func requestAccess() async -> Bool { requestResult }
        func openSystemSettings() { openedSettingsCount += 1 }
    }

    private final class MockCaptureEngine: CaptureEngineProtocol, @unchecked Sendable {
        var displays: [CaptureDisplay] = [
            CaptureDisplay(
                id: 1,
                name: "Test Display",
                frameInPoints: CGRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrameInPoints: CGRect(x: 0, y: 40, width: 1440, height: 835),
                pixelWidth: 2880,
                pixelHeight: 1800,
                scaleFactor: 2.0,
                isPrimary: true
            )
        ]
        var windows: [CaptureWindow] = [
            CaptureWindow(
                id: 42,
                title: "Document.md",
                ownerName: "TextEdit",
                ownerPID: 999,
                bundleIdentifier: "com.apple.TextEdit",
                frameInPoints: CGRect(x: 100, y: 100, width: 800, height: 600)
            )
        ]
        var errorToThrow: CaptureError?

        func listDisplays() async throws -> [CaptureDisplay] {
            if let errorToThrow { throw errorToThrow }
            return displays
        }

        func listWindows() async throws -> [CaptureWindow] {
            if let errorToThrow { throw errorToThrow }
            return windows
        }

        func captureDisplay(id: UInt32) async throws -> CGImage {
            if let errorToThrow { throw errorToThrow }
            return ImageRenderer.makeSyntheticImage(width: 2880, height: 1800)!
        }

        func captureWindow(id: UInt32) async throws -> CGImage {
            if let errorToThrow { throw errorToThrow }
            return ImageRenderer.makeSyntheticImage(width: 1600, height: 1200)!
        }

        func captureRegion(displayID: UInt32, rectInPixels: CGRect) async throws -> CGImage {
            if let errorToThrow { throw errorToThrow }
            return ImageRenderer.makeSyntheticImage(
                width: Int(rectInPixels.width),
                height: Int(rectInPixels.height)
            )!
        }
    }

    private final class MockRegionSelector: RegionSelecting {
        var result: Result<RegionSelectionResult, Error> = .success(
            RegionSelectionResult(displayID: 1, rectInPixels: CGRect(x: 100, y: 100, width: 640, height: 480))
        )
        var cleanupCount = 0

        func selectRegion(displays: [CaptureDisplay]) async throws -> RegionSelectionResult {
            try result.get()
        }

        func cleanup() {
            cleanupCount += 1
        }
    }

    private final class MockWindowSelector: WindowSelecting {
        var result: Result<UInt32, Error> = .success(42)
        var cleanupCount = 0

        func selectWindow(windows: [CaptureWindow], displays: [CaptureDisplay]) async throws -> UInt32 {
            try result.get()
        }

        func cleanup() {
            cleanupCount += 1
        }
    }

    func testPermissionDeniedTransitionsToPermissionHelpWithoutCrash() async {
        let permissions = MockPermissionManager()
        permissions.status = .denied
        permissions.requestResult = false
        let engine = MockCaptureEngine()
        let regionSelector = MockRegionSelector()
        let windowSelector = MockWindowSelector()

        let coordinator = CaptureCoordinator(
            permissionManager: permissions,
            captureEngine: engine,
            regionSelector: regionSelector,
            windowSelector: windowSelector
        )

        var deniedMode: CaptureMode?
        coordinator.onPermissionDenied = { mode in
            deniedMode = mode
        }

        await coordinator.startCapture(mode: .region)

        XCTAssertEqual(coordinator.state, .permissionHelp(.region))
        XCTAssertEqual(coordinator.lastError, .permissionDenied)
        XCTAssertEqual(deniedMode, .region)
    }

    func testFullscreenCaptureHidesAndRestoresChromeAndCreatesDocument() async {
        let permissions = MockPermissionManager()
        let engine = MockCaptureEngine()
        let regionSelector = MockRegionSelector()
        let windowSelector = MockWindowSelector()

        let coordinator = CaptureCoordinator(
            permissionManager: permissions,
            captureEngine: engine,
            regionSelector: regionSelector,
            windowSelector: windowSelector
        )

        var events: [String] = []
        coordinator.onHideAppChromeForCapture = { events.append("hide") }
        coordinator.onRestoreAppChromeAfterCapture = { events.append("restore") }
        coordinator.onDocumentCaptured = { _ in events.append("captured") }

        await coordinator.startCapture(mode: .fullscreen)

        XCTAssertEqual(events, ["hide", "restore", "captured"])
        guard let doc = coordinator.latestDocument else {
            return XCTFail("Expected captured document")
        }
        XCTAssertEqual(coordinator.state, .editing(doc.id))
        XCTAssertEqual(doc.imagePixelSize, CGSize(width: 2880, height: 1800))
    }

    func testRegionSelectionCancelledCleansUpAndReturnsToIdle() async {
        let permissions = MockPermissionManager()
        let engine = MockCaptureEngine()
        let regionSelector = MockRegionSelector()
        regionSelector.result = .failure(CaptureError.cancelled)
        let windowSelector = MockWindowSelector()

        let coordinator = CaptureCoordinator(
            permissionManager: permissions,
            captureEngine: engine,
            regionSelector: regionSelector,
            windowSelector: windowSelector
        )

        var restoredChrome = false
        coordinator.onRestoreAppChromeAfterCapture = { restoredChrome = true }

        await coordinator.startCapture(mode: .region)

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.lastError)
        XCTAssertTrue(restoredChrome)
        XCTAssertGreaterThanOrEqual(regionSelector.cleanupCount, 1)
    }

    func testWindowCaptureFailureCleansUpAndTransitionsToErrorState() async {
        let permissions = MockPermissionManager()
        let engine = MockCaptureEngine()
        engine.errorToThrow = .windowNotFound(42)
        let regionSelector = MockRegionSelector()
        let windowSelector = MockWindowSelector()

        let coordinator = CaptureCoordinator(
            permissionManager: permissions,
            captureEngine: engine,
            regionSelector: regionSelector,
            windowSelector: windowSelector
        )

        await coordinator.startCapture(mode: .window)

        XCTAssertEqual(coordinator.state, .error(.windowNotFound(42)))
        XCTAssertEqual(coordinator.lastError, .windowNotFound(42))
        XCTAssertGreaterThanOrEqual(windowSelector.cleanupCount, 1)
    }

    func testHotkeyConflictDetectionForDuplicatesAndSystemShortcuts() {
        let systemConflictShortcut = HotkeyShortcut(
            keyCode: UInt32(kVK_ANSI_4),
            carbonModifiers: UInt32(cmdKey | shiftKey),
            keyEquivalent: "4"
        )
        let bindings: [HotkeyAction: HotkeyShortcut] = [
            .captureRegion: .defaultRegion,
            .captureWindow: .defaultRegion, // duplicate
            .captureFullscreen: systemConflictShortcut, // system ⇧⌘4 conflict
            .toggleToolbar: .defaultToggleToolbar,
        ]

        let conflicts = HotkeyManager.validateConflicts(in: bindings)
        XCTAssertEqual(conflicts.count, 2)
        XCTAssertTrue(conflicts.contains { $0.action == .captureWindow })
        XCTAssertTrue(conflicts.contains { $0.action == .captureFullscreen })
    }

    func testScrollingStitcherDetectsOverlapAndStitchesVertically() {
        let width = 120
        let height = 100
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        func makePageSlice(scrollOffsetY: Int) -> CGImage {
            var bytes = [UInt8](repeating: 255, count: width * height * 4)
            for y in 0..<height {
                let pageY = y + scrollOffsetY
                let r = UInt8((pageY * 13) % 251)
                let g = UInt8((pageY * 29 + 50) % 241)
                let b = UInt8((pageY * 43 + 90) % 239)
                for x in 0..<width {
                    let idx = (y * width + x) * 4
                    bytes[idx] = r
                    bytes[idx + 1] = g
                    bytes[idx + 2] = b
                    bytes[idx + 3] = 255
                }
            }
            let data = Data(bytes) as CFData
            let provider = CGDataProvider(data: data)!
            return CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )!
        }

        let frame1 = makePageSlice(scrollOffsetY: 0)
        let frame2 = makePageSlice(scrollOffsetY: 30)
        guard let stitcher = ScrollingStitcher(firstFrame: frame1) else {
            return XCTFail("Expected ScrollingStitcher to initialize")
        }

        let outcome = stitcher.appendFrame(frame2)
        XCTAssertEqual(outcome, .stitched(addedHeight: 30, totalHeight: 130))
        XCTAssertEqual(stitcher.accumulatedImage.width, 120)
        XCTAssertEqual(stitcher.accumulatedImage.height, 130)
        XCTAssertEqual(stitcher.frameCount, 2)
    }
}
