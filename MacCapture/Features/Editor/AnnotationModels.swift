import CoreGraphics
import Foundation
import SwiftUI

public enum AnnotationKind: String, Codable, CaseIterable, Sendable {
    case arrow
    case line
    case rectangle
    case ellipse
    case text
    case blur

    public var title: String {
        switch self {
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rectangle: return "Rect"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        case .blur: return "Blur"
        }
    }

    public var symbolName: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .text: return "textformat"
        case .blur: return "drop.halffull"
        }
    }
}

public enum EditorTool: String, CaseIterable, Sendable {
    case select
    case arrow
    case line
    case rectangle
    case ellipse
    case text
    case blur
    case crop

    public var title: String {
        switch self {
        case .select: return "Select"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rectangle: return "Rect"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        case .blur: return "Blur"
        case .crop: return "Crop"
        }
    }

    public var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .text: return "textformat"
        case .blur: return "drop.halffull"
        case .crop: return "crop"
        }
    }

    public var shortcutHint: String {
        switch self {
        case .select: return "V"
        case .arrow: return "A"
        case .line: return "L"
        case .rectangle: return "R"
        case .ellipse: return "O"
        case .text: return "T"
        case .blur: return "B"
        case .crop: return "C"
        }
    }
}

public struct RGBAColor: Codable, Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    public static let red = RGBAColor(red: 0.95, green: 0.22, blue: 0.22)
    public static let orange = RGBAColor(red: 0.98, green: 0.55, blue: 0.12)
    public static let yellow = RGBAColor(red: 0.96, green: 0.80, blue: 0.12)
    public static let green = RGBAColor(red: 0.18, green: 0.78, blue: 0.36)
    public static let blue = RGBAColor(red: 0.14, green: 0.52, blue: 0.96)
    public static let purple = RGBAColor(red: 0.62, green: 0.32, blue: 0.92)
    public static let white = RGBAColor(red: 1.0, green: 1.0, blue: 1.0)
    public static let black = RGBAColor(red: 0.10, green: 0.10, blue: 0.10)

    public static let palette: [RGBAColor] = [
        .red, .orange, .yellow, .green, .blue, .purple, .white, .black
    ]

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

public struct AnnotationStyle: Codable, Equatable, Sendable {
    public var strokeColor: RGBAColor
    public var strokeWidth: CGFloat
    public var fontSize: CGFloat
    public var isFilled: Bool

    public init(
        strokeColor: RGBAColor = .red,
        strokeWidth: CGFloat = 4.0,
        fontSize: CGFloat = 24.0,
        isFilled: Bool = false
    ) {
        self.strokeColor = strokeColor
        self.strokeWidth = max(strokeWidth, 1.0)
        self.fontSize = max(fontSize, 8.0)
        self.isFilled = isFilled
    }
}

public struct Annotation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: AnnotationKind
    public var frame: CGRect
    public var startPoint: CGPoint
    public var endPoint: CGPoint
    public var style: AnnotationStyle
    public var text: String?
    public var zIndex: Int

    public init(
        id: UUID = UUID(),
        kind: AnnotationKind,
        frame: CGRect,
        startPoint: CGPoint? = nil,
        endPoint: CGPoint? = nil,
        style: AnnotationStyle = AnnotationStyle(),
        text: String? = nil,
        zIndex: Int = 0
    ) {
        self.id = id
        self.kind = kind
        let standardized = frame.standardized
        self.frame = standardized
        self.startPoint = startPoint ?? CGPoint(x: standardized.minX, y: standardized.minY)
        self.endPoint = endPoint ?? CGPoint(x: standardized.maxX, y: standardized.maxY)
        self.style = style
        self.text = text
        self.zIndex = zIndex
    }

    public mutating func applyOffset(dx: CGFloat, dy: CGFloat) {
        frame = frame.offsetBy(dx: dx, dy: dy)
        startPoint = CGPoint(x: startPoint.x + dx, y: startPoint.y + dy)
        endPoint = CGPoint(x: endPoint.x + dx, y: endPoint.y + dy)
    }

    public mutating func applyResize(newFrame: CGRect, newStart: CGPoint? = nil, newEnd: CGPoint? = nil) {
        let standardized = newFrame.standardized
        frame = standardized
        if let newStart {
            startPoint = newStart
        } else {
            startPoint = CGPoint(x: standardized.minX, y: standardized.minY)
        }
        if let newEnd {
            endPoint = newEnd
        } else {
            endPoint = CGPoint(x: standardized.maxX, y: standardized.maxY)
        }
    }

    public func hitTest(_ point: CGPoint, tolerance: CGFloat = 8.0) -> Bool {
        switch kind {
        case .arrow, .line:
            return Self.distanceFromPoint(point, toSegmentFrom: startPoint, to: endPoint) <= max(tolerance, style.strokeWidth)
        case .rectangle, .ellipse, .text, .blur:
            return frame.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    private static func distanceFromPoint(_ p: CGPoint, toSegmentFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.0001 else {
            return hypot(p.x - a.x, p.y - a.y)
        }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1)
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        return hypot(p.x - projX, p.y - projY)
    }
}

public struct CaptureDocument: Identifiable, Sendable {
    public let id: UUID
    public let capturedAt: Date
    public let imagePixelSize: CGSize
    public let baseImage: CGImage
    public var annotations: [Annotation]
    public var cropRect: CGRect?

    public init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        baseImage: CGImage,
        annotations: [Annotation] = [],
        cropRect: CGRect? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.imagePixelSize = CGSize(width: baseImage.width, height: baseImage.height)
        self.baseImage = baseImage
        self.annotations = annotations
        self.cropRect = cropRect
    }

    public var sortedAnnotations: [Annotation] {
        annotations.sorted { lhs, rhs in
            if lhs.zIndex == rhs.zIndex {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.zIndex < rhs.zIndex
        }
    }

    public var effectiveOutputPixelSize: CGSize {
        if let cropRect {
            let bounds = CGRect(origin: .zero, size: imagePixelSize)
            let clamped = CoordinateConverter.clampRect(cropRect.integral, to: bounds)
            if clamped.width >= 1, clamped.height >= 1 {
                return clamped.size
            }
        }
        return imagePixelSize
    }
}
