import CoreGraphics
import Foundation

public enum CaptureMode: String, Codable, CaseIterable, Sendable {
    case region
    case window
    case fullscreen
    case scrolling

    public var displayName: String {
        switch self {
        case .region: return "Region"
        case .window: return "Window"
        case .fullscreen: return "Full"
        case .scrolling: return "Scroll"
        }
    }

    public var symbolName: String {
        switch self {
        case .region: return "viewfinder.rectangular"
        case .window: return "macwindow"
        case .fullscreen: return "rectangle.inset.filled"
        case .scrolling: return "arrow.up.and.down.text.horizontal"
        }
    }
}

public enum CaptureDelay: Int, Codable, CaseIterable, Sendable {
    case none = 0
    case threeSeconds = 3
    case fiveSeconds = 5
    case tenSeconds = 10

    public var label: String {
        switch self {
        case .none: return "0s"
        case .threeSeconds: return "3s"
        case .fiveSeconds: return "5s"
        case .tenSeconds: return "10s"
        }
    }
}

public struct CaptureDisplay: Identifiable, Equatable, Sendable {
    public let id: UInt32
    public let name: String
    public let frameInPoints: CGRect
    public let visibleFrameInPoints: CGRect
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let scaleFactor: CGFloat
    public let isPrimary: Bool

    public init(
        id: UInt32,
        name: String,
        frameInPoints: CGRect,
        visibleFrameInPoints: CGRect,
        pixelWidth: Int,
        pixelHeight: Int,
        scaleFactor: CGFloat,
        isPrimary: Bool
    ) {
        self.id = id
        self.name = name
        self.frameInPoints = frameInPoints
        self.visibleFrameInPoints = visibleFrameInPoints
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scaleFactor = scaleFactor
        self.isPrimary = isPrimary
    }

    public var pixelSize: CGSize {
        CGSize(width: pixelWidth, height: pixelHeight)
    }
}

public struct CaptureWindow: Identifiable, Equatable, Sendable {
    public let id: UInt32
    public let title: String
    public let ownerName: String
    public let ownerPID: Int32
    public let bundleIdentifier: String?
    public let frameInPoints: CGRect
    public let layer: Int
    public let isOnScreen: Bool

    public init(
        id: UInt32,
        title: String,
        ownerName: String,
        ownerPID: Int32,
        bundleIdentifier: String?,
        frameInPoints: CGRect,
        layer: Int = 0,
        isOnScreen: Bool = true
    ) {
        self.id = id
        self.title = title
        self.ownerName = ownerName
        self.ownerPID = ownerPID
        self.bundleIdentifier = bundleIdentifier
        self.frameInPoints = frameInPoints
        self.layer = layer
        self.isOnScreen = isOnScreen
    }

    public var displayTitle: String {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ownerName
        }
        return "\(ownerName) — \(title)"
    }
}

public enum CaptureError: Error, Equatable, LocalizedError, Sendable {
    case permissionDenied
    case noDisplaysAvailable
    case displayNotFound(UInt32)
    case windowNotFound(UInt32)
    case selectionTooSmall
    case cancelled
    case captureFailed(String)
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required to capture the screen."
        case .noDisplaysAvailable:
            return "No active displays were found."
        case .displayNotFound(let id):
            return "Target display (\(id)) is no longer available."
        case .windowNotFound(let id):
            return "Selected window (\(id)) is no longer available or is protected."
        case .selectionTooSmall:
            return "Selected region is smaller than the minimum 4×4 pixel threshold."
        case .cancelled:
            return "Capture was cancelled."
        case .captureFailed(let reason):
            return "Screen capture failed: \(reason)"
        case .exportFailed(let reason):
            return "Failed to export image: \(reason)"
        }
    }
}

public enum CaptureState: Equatable, Sendable {
    case idle
    case checkingPermission(CaptureMode)
    case permissionHelp(CaptureMode)
    case countdown(CaptureMode, remainingSeconds: Int)
    case selectingRegion
    case selectingWindow
    case capturingFullscreen
    case capturing(CaptureMode)
    case editing(UUID)
    case error(CaptureError)

    public var isBusy: Bool {
        switch self {
        case .idle, .editing, .permissionHelp, .error:
            return false
        case .checkingPermission, .countdown, .selectingRegion, .selectingWindow, .capturingFullscreen, .capturing:
            return true
        }
    }
}

public protocol CaptureEngineProtocol: Sendable {
    func listDisplays() async throws -> [CaptureDisplay]
    func listWindows() async throws -> [CaptureWindow]
    func captureDisplay(id: UInt32) async throws -> CGImage
    func captureWindow(id: UInt32) async throws -> CGImage
    func captureRegion(displayID: UInt32, rectInPixels: CGRect) async throws -> CGImage
}

public protocol ImageExporting: Sendable {
    func pngData(image: CGImage) throws -> Data
    func savePNG(image: CGImage, to url: URL) throws
    func copyImage(image: CGImage) throws
}
