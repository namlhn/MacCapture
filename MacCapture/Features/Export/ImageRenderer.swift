import AppKit
import CoreGraphics
import CoreText
import Foundation

public enum ImageRenderer {
    /// Flattens a `CaptureDocument` (baseImage + sorted vector annotations + optional cropRect)
    /// into a full-resolution `CGImage`.
    public static func render(document: CaptureDocument) throws -> CGImage {
        let width = document.baseImage.width
        let height = document.baseImage.height
        guard width > 0, height > 0 else {
            throw CaptureError.exportFailed("Invalid base image dimensions.")
        }

        let colorSpace = document.baseImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw CaptureError.exportFailed("Unable to allocate CoreGraphics bitmap context.")
        }

        let fullCanvasRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.interpolationQuality = .high
        context.draw(document.baseImage, in: fullCanvasRect)

        // Flip coordinate system so (0, 0) is top-left and Y increases downward, matching Annotation coordinates.
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        for annotation in document.sortedAnnotations {
            draw(annotation: annotation, baseImage: document.baseImage, in: context)
        }
        context.restoreGState()

        guard let fullRenderedImage = context.makeImage() else {
            throw CaptureError.exportFailed("Failed to rasterize annotated image.")
        }

        if let cropRect = document.cropRect {
            let clamped = CoordinateConverter.clampRect(cropRect.integral, to: fullCanvasRect)
            if clamped.width >= 1, clamped.height >= 1 {
                guard let cropped = fullRenderedImage.cropping(to: clamped) else {
                    throw CaptureError.exportFailed("Failed to apply crop rectangle.")
                }
                return cropped
            }
        }

        return fullRenderedImage
    }

    public static func draw(annotation: Annotation, baseImage: CGImage? = nil, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        let strokeColor = annotation.style.strokeColor.cgColor
        let lineWidth = max(annotation.style.strokeWidth, 1.0)
        context.setStrokeColor(strokeColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.kind {
        case .rectangle:
            let rect = annotation.frame.standardized
            if annotation.style.isFilled {
                let fill = annotation.style.strokeColor
                context.setFillColor(
                    RGBAColor(red: fill.red, green: fill.green, blue: fill.blue, alpha: 0.2).cgColor
                )
                context.fill(rect)
            }
            context.stroke(rect)

        case .ellipse:
            let rect = annotation.frame.standardized
            if annotation.style.isFilled {
                let fill = annotation.style.strokeColor
                context.setFillColor(
                    RGBAColor(red: fill.red, green: fill.green, blue: fill.blue, alpha: 0.2).cgColor
                )
                context.fillEllipse(in: rect)
            }
            context.strokeEllipse(in: rect)

        case .line:
            guard hypot(annotation.endPoint.x - annotation.startPoint.x, annotation.endPoint.y - annotation.startPoint.y) >= 1.0 else {
                return
            }
            context.beginPath()
            context.move(to: annotation.startPoint)
            context.addLine(to: annotation.endPoint)
            context.strokePath()

        case .arrow:
            drawArrow(
                from: annotation.startPoint,
                to: annotation.endPoint,
                lineWidth: lineWidth,
                color: strokeColor,
                in: context
            )

        case .text:
            drawText(annotation: annotation, in: context)

        case .blur:
            drawBlur(annotation: annotation, baseImage: baseImage, in: context)
        }
    }

    public static func makeBlurredRegionImage(
        from baseImage: CGImage,
        regionInPixels: CGRect,
        strength: CGFloat
    ) -> CGImage? {
        let imageBounds = CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)
        let clamped = CoordinateConverter.clampRect(regionInPixels.integral, to: imageBounds)
        guard clamped.width >= 2, clamped.height >= 2,
              let cropped = baseImage.cropping(to: clamped) else {
            return nil
        }

        let blockSize = max(Int(strength * 4.5), 10)
        let smallW = max(Int(clamped.width) / blockSize, 1)
        let smallH = max(Int(clamped.height) / blockSize, 1)

        let colorSpace = baseImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let smallContext = CGContext(
            data: nil,
            width: smallW,
            height: smallH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        smallContext.interpolationQuality = .medium
        smallContext.draw(cropped, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
        guard let smallImage = smallContext.makeImage() else {
            return nil
        }

        let outW = Int(clamped.width)
        let outH = Int(clamped.height)
        guard let outContext = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        // Upsample with nearest-neighbor (.none) for irreversible mosaic pixelation
        outContext.interpolationQuality = .none
        outContext.draw(smallImage, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        return outContext.makeImage()
    }

    private static func drawBlur(
        annotation: Annotation,
        baseImage: CGImage?,
        in context: CGContext
    ) {
        let rect = annotation.frame.standardized
        guard rect.width >= 2, rect.height >= 2 else { return }

        if let baseImage,
           let blurredPatch = makeBlurredRegionImage(
               from: baseImage,
               regionInPixels: rect,
               strength: annotation.style.strokeWidth
           ) {
            let imageBounds = CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)
            let clamped = CoordinateConverter.clampRect(rect.integral, to: imageBounds)
            context.saveGState()
            context.translateBy(x: clamped.minX, y: clamped.minY + clamped.height)
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .none
            context.draw(blurredPatch, in: CGRect(origin: .zero, size: clamped.size))
            context.restoreGState()
        } else {
            context.setFillColor(RGBAColor.black.cgColor)
            context.fill(rect)
        }
    }

    private static func drawArrow(
        from start: CGPoint,
        to end: CGPoint,
        lineWidth: CGFloat,
        color: CGColor,
        in context: CGContext
    ) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length >= 1.0 else { return }

        let angle = atan2(dy, dx)
        let headLength = max(lineWidth * 3.8, 12.0)
        let headAngle: CGFloat = .pi / 6.0

        let shaftEnd = CGPoint(
            x: end.x - cos(angle) * (headLength * 0.65),
            y: end.y - sin(angle) * (headLength * 0.65)
        )

        context.beginPath()
        context.move(to: start)
        context.addLine(to: shaftEnd)
        context.strokePath()

        let wing1 = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let wing2 = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        context.setFillColor(color)
        context.beginPath()
        context.move(to: end)
        context.addLine(to: wing1)
        context.addLine(to: wing2)
        context.closePath()
        context.fillPath()
    }

    private static func drawText(annotation: Annotation, in context: CGContext) {
        let textString = (annotation.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textString.isEmpty else { return }

        let rect = annotation.frame.standardized
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, annotation.style.fontSize, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: annotation.style.strokeColor.cgColor,
        ]
        guard let attrString = CFAttributedStringCreate(
            kCFAllocatorDefault,
            textString as CFString,
            attributes as CFDictionary
        ) else { return }

        let framesetter = CTFramesetterCreateWithAttributedString(attrString)
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRangeMake(0, CFAttributedStringGetLength(attrString)),
            nil,
            CGSize(width: max(rect.width, 400), height: max(rect.height, 200)),
            nil
        )

        let drawWidth = max(rect.width, ceil(suggestedSize.width) + 8)
        let drawHeight = max(rect.height, ceil(suggestedSize.height) + 6)

        // CoreText draws with Y-up inside its path, so flip locally at rect.minY + drawHeight
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY + drawHeight)
        context.scaleBy(x: 1, y: -1)

        let path = CGPath(rect: CGRect(x: 0, y: 0, width: drawWidth, height: drawHeight), transform: nil)
        let ctFrame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        CTFrameDraw(ctFrame, context)
        context.restoreGState()
    }

    /// Creates a synthetic test `CGImage` with a deterministic gradient/pattern for unit tests and Editor preview.
    public static func makeSyntheticImage(width: Int, height: Int, fill: RGBAColor = .blue) -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        context.setFillColor(fill.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
