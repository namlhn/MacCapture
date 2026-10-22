import CoreGraphics
import SwiftUI

public struct AnnotationCanvas: View {
    @ObservedObject private var commandStack: AnnotationCommandStack
    @Binding private var pendingCropRect: CGRect?
    private let activeTool: EditorTool
    private let currentStyle: AnnotationStyle
    private let zoomScale: CGFloat
    private let onRequestTextFocus: (UUID) -> Void
    private let onConfirmCrop: () -> Void
    private let onCancelCrop: () -> Void

    private enum DragOperation {
        case none
        case creating(start: CGPoint, current: CGPoint)
        case moving(id: UUID, original: Annotation, translation: CGSize)
        case resizingCorner(id: UUID, original: Annotation, corner: CornerHandle, current: CGPoint)
        case resizingArrowEnd(id: UUID, original: Annotation, isStart: Bool, current: CGPoint)
        case croppingNew(start: CGPoint, current: CGPoint)
        case movingCrop(original: CGRect, translation: CGSize)
        case resizingCropCorner(original: CGRect, corner: CornerHandle, current: CGPoint)
    }

    private enum CornerHandle: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    @State private var dragOperation: DragOperation = .none

    public init(
        commandStack: AnnotationCommandStack,
        pendingCropRect: Binding<CGRect?> = .constant(nil),
        activeTool: EditorTool,
        currentStyle: AnnotationStyle,
        zoomScale: CGFloat,
        onRequestTextFocus: @escaping (UUID) -> Void = { _ in },
        onConfirmCrop: @escaping () -> Void = {},
        onCancelCrop: @escaping () -> Void = {}
    ) {
        self.commandStack = commandStack
        self._pendingCropRect = pendingCropRect
        self.activeTool = activeTool
        self.currentStyle = currentStyle
        self.zoomScale = max(zoomScale, 0.1)
        self.onRequestTextFocus = onRequestTextFocus
        self.onConfirmCrop = onConfirmCrop
        self.onCancelCrop = onCancelCrop
    }

    /// When in `.crop` mode, show the full base image so the user can freely select or adjust the crop box.
    /// When not in `.crop` mode, if `document.cropRect` has been applied, show only the cropped region!
    private var visibleImagePixelRect: CGRect {
        let fullBounds = CGRect(origin: .zero, size: commandStack.document.imagePixelSize)
        if activeTool == .crop {
            return fullBounds
        }
        if let appliedCrop = commandStack.document.cropRect {
            let clamped = CoordinateConverter.clampRect(appliedCrop.integral, to: fullBounds)
            if clamped.width >= 1, clamped.height >= 1 {
                return clamped
            }
        }
        return fullBounds
    }

    private var fullDisplaySize: CGSize {
        let px = commandStack.document.imagePixelSize
        return CGSize(width: px.width * zoomScale, height: px.height * zoomScale)
    }

    private var visibleDisplaySize: CGSize {
        let visiblePx = visibleImagePixelRect
        return CGSize(width: visiblePx.width * zoomScale, height: visiblePx.height * zoomScale)
    }

    public var body: some View {
        let fullSize = fullDisplaySize
        let visibleSize = visibleDisplaySize
        let visiblePx = visibleImagePixelRect

        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Image(decorative: commandStack.document.baseImage, scale: 1.0, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: fullSize.width, height: fullSize.height)

                Canvas { context, _ in
                    for annotation in commandStack.document.sortedAnnotations {
                        let rendered = previewAdjustedAnnotation(annotation)
                        drawAnnotation(rendered, in: &context)
                    }

                    if case .creating(let start, let current) = dragOperation {
                        let preview = makePreviewAnnotation(from: start, to: current)
                        drawAnnotation(preview, in: &context)
                    }

                    if activeTool == .crop, let crop = liveCropRectInPixels {
                        drawInteractiveCropOverlay(cropInPixels: crop, in: &context, canvasSize: fullSize)
                    }

                    if activeTool != .crop,
                       let selectedID = commandStack.selectedAnnotationID,
                       let selected = commandStack.document.annotations.first(where: { $0.id == selectedID }) {
                        let adjusted = previewAdjustedAnnotation(selected)
                        drawSelectionHandles(for: adjusted, in: &context)
                    }
                }
                .frame(width: fullSize.width, height: fullSize.height)
            }
            .offset(
                x: -visiblePx.minX * zoomScale,
                y: -visiblePx.minY * zoomScale
            )
            .frame(width: visibleSize.width, height: visibleSize.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(canvasDragGesture)

            // Floating Confirm / Cancel pill right next to the crop selection box
            if activeTool == .crop,
               case .none = dragOperation,
               let crop = pendingCropRect,
               crop.width >= 8,
               crop.height >= 8 {
                floatingCropActionOverlay(for: crop, in: visibleSize)
            }
        }
        .frame(width: visibleSize.width, height: visibleSize.height)
        .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 3)
        .accessibilityIdentifier("AnnotationCanvasView")
    }

    @ViewBuilder
    private func floatingCropActionOverlay(for cropInPixels: CGRect, in canvasSize: CGSize) -> some View {
        let scaled = CGRect(
            x: cropInPixels.minX * zoomScale,
            y: cropInPixels.minY * zoomScale,
            width: cropInPixels.width * zoomScale,
            height: cropInPixels.height * zoomScale
        )
        let barWidth: CGFloat = 290
        let barHeight: CGFloat = 36
        let clampedX = min(max(scaled.midX - barWidth / 2, 8), max(canvasSize.width - barWidth - 8, 8))
        let prefersBelow = scaled.maxY + barHeight + 14 <= canvasSize.height
        let targetY = prefersBelow
            ? scaled.maxY + 10
            : max(scaled.minY - barHeight - 10, 8)

        HStack(spacing: 8) {
            Text("\(Int(cropInPixels.width)) × \(Int(cropInPixels.height)) px")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
                .padding(.leading, 4)

            Divider()
                .frame(height: 16)
                .overlay(Color.white.opacity(0.25))

            Button {
                onCancelCrop()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Hủy")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                )
            }
            .buttonStyle(.plain)
            .help("Cancel Crop (Esc)")

            Button {
                onConfirmCrop()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Hoàn thành")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.green)
                )
            }
            .buttonStyle(.plain)
            .help("Apply Crop (Return)")
            .accessibilityIdentifier("EditorButton_FloatingConfirmCrop")
        }
        .padding(.horizontal, 8)
        .frame(height: barHeight)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.84))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
        .offset(x: clampedX, y: targetY)
    }

    private var liveCropRectInPixels: CGRect? {
        let fullBounds = CGRect(origin: .zero, size: commandStack.document.imagePixelSize)
        switch dragOperation {
        case .croppingNew(let start, let current):
            let raw = CoordinateConverter.normalizedDragRect(from: start, to: current)
            return CoordinateConverter.clampRect(raw.integral, to: fullBounds)
        case .movingCrop(let original, let translation):
            let moved = original.offsetBy(
                dx: min(max(translation.width, -original.minX), fullBounds.maxX - original.maxX),
                dy: min(max(translation.height, -original.minY), fullBounds.maxY - original.maxY)
            )
            return CoordinateConverter.clampRect(moved.integral, to: fullBounds)
        case .resizingCropCorner(let original, let corner, let current):
            let resized = resizedFrame(original: original, corner: corner, to: current)
            return CoordinateConverter.clampRect(resized.integral, to: fullBounds)
        default:
            return pendingCropRect
        }
    }

    private var canvasDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startPx = toImagePixelPoint(value.startLocation)
                let currentPx = toImagePixelPoint(value.location)

                if case .none = dragOperation {
                    beginDrag(startPx: startPx, currentPx: currentPx)
                } else {
                    updateDrag(startPx: startPx, currentPx: currentPx)
                }
            }
            .onEnded { value in
                let startPx = toImagePixelPoint(value.startLocation)
                let endPx = toImagePixelPoint(value.location)
                finishDrag(startPx: startPx, endPx: endPx)
                dragOperation = .none
            }
    }

    private func beginDrag(startPx: CGPoint, currentPx: CGPoint) {
        switch activeTool {
        case .select:
            if let selectedID = commandStack.selectedAnnotationID,
               let selected = commandStack.document.annotations.first(where: { $0.id == selectedID }) {
                if selected.kind == .arrow || selected.kind == .line {
                    let handleTolerance = 12.0 / zoomScale
                    if hypot(startPx.x - selected.startPoint.x, startPx.y - selected.startPoint.y) <= handleTolerance {
                        dragOperation = .resizingArrowEnd(id: selected.id, original: selected, isStart: true, current: currentPx)
                        return
                    }
                    if hypot(startPx.x - selected.endPoint.x, startPx.y - selected.endPoint.y) <= handleTolerance {
                        dragOperation = .resizingArrowEnd(id: selected.id, original: selected, isStart: false, current: currentPx)
                        return
                    }
                } else if let corner = hitCornerHandle(in: selected.frame, at: startPx) {
                    dragOperation = .resizingCorner(id: selected.id, original: selected, corner: corner, current: currentPx)
                    return
                }
            }

            if let hit = commandStack.document.sortedAnnotations.reversed().first(where: {
                $0.hitTest(startPx, tolerance: 10.0 / zoomScale)
            }) {
                commandStack.selectedAnnotationID = hit.id
                let delta = CGSize(width: currentPx.x - startPx.x, height: currentPx.y - startPx.y)
                dragOperation = .moving(id: hit.id, original: hit, translation: delta)
            } else {
                commandStack.selectedAnnotationID = nil
            }

        case .arrow, .line, .rectangle, .ellipse, .text, .blur:
            dragOperation = .creating(start: startPx, current: currentPx)

        case .crop:
            if let existingCrop = pendingCropRect {
                if let corner = hitCornerHandle(in: existingCrop, at: startPx) {
                    dragOperation = .resizingCropCorner(original: existingCrop, corner: corner, current: currentPx)
                    return
                }
                if existingCrop.contains(startPx) {
                    let delta = CGSize(width: currentPx.x - startPx.x, height: currentPx.y - startPx.y)
                    dragOperation = .movingCrop(original: existingCrop, translation: delta)
                    return
                }
            }
            dragOperation = .croppingNew(start: startPx, current: currentPx)
        }
    }

    private func updateDrag(startPx: CGPoint, currentPx: CGPoint) {
        switch dragOperation {
        case .none:
            break
        case .creating(let start, _):
            dragOperation = .creating(start: start, current: currentPx)
        case .moving(let id, let original, _):
            let delta = CGSize(width: currentPx.x - startPx.x, height: currentPx.y - startPx.y)
            dragOperation = .moving(id: id, original: original, translation: delta)
        case .resizingCorner(let id, let original, let corner, _):
            dragOperation = .resizingCorner(id: id, original: original, corner: corner, current: currentPx)
        case .resizingArrowEnd(let id, let original, let isStart, _):
            dragOperation = .resizingArrowEnd(id: id, original: original, isStart: isStart, current: currentPx)
        case .croppingNew(let start, _):
            dragOperation = .croppingNew(start: start, current: currentPx)
        case .movingCrop(let original, _):
            let delta = CGSize(width: currentPx.x - startPx.x, height: currentPx.y - startPx.y)
            dragOperation = .movingCrop(original: original, translation: delta)
        case .resizingCropCorner(let original, let corner, _):
            dragOperation = .resizingCropCorner(original: original, corner: corner, current: currentPx)
        }
    }

    private func finishDrag(startPx: CGPoint, endPx: CGPoint) {
        switch dragOperation {
        case .none:
            break
        case .creating(let start, _):
            let created = makePreviewAnnotation(from: start, to: endPx)
            if created.kind == .text || created.frame.width >= 4 || created.frame.height >= 4 || hypot(endPx.x - start.x, endPx.y - start.y) >= 4 {
                commandStack.addAnnotation(created)
                if created.kind == .text {
                    onRequestTextFocus(created.id)
                }
            }

        case .moving(let id, _, let translation):
            commandStack.moveAnnotation(id: id, dx: translation.width, dy: translation.height)

        case .resizingCorner(let id, let original, let corner, _):
            let newFrame = resizedFrame(original: original.frame, corner: corner, to: endPx)
            commandStack.resizeAnnotation(id: id, newFrame: newFrame)

        case .resizingArrowEnd(let id, let original, let isStart, _):
            let newStart = isStart ? endPx : original.startPoint
            let newEnd = isStart ? original.endPoint : endPx
            let newFrame = CoordinateConverter.normalizedDragRect(from: newStart, to: newEnd)
            commandStack.resizeAnnotation(id: id, newFrame: newFrame, newStartPoint: newStart, newEndPoint: newEnd)

        case .croppingNew, .movingCrop, .resizingCropCorner:
            if let finalCrop = liveCropRectInPixels, finalCrop.width >= 8, finalCrop.height >= 8 {
                pendingCropRect = finalCrop
            }
        }
    }

    private func previewAdjustedAnnotation(_ annotation: Annotation) -> Annotation {
        var copy = annotation
        switch dragOperation {
        case .moving(let id, let original, let translation) where id == annotation.id:
            copy = original
            copy.applyOffset(dx: translation.width, dy: translation.height)
        case .resizingCorner(let id, let original, let corner, let current) where id == annotation.id:
            copy = original
            copy.applyResize(newFrame: resizedFrame(original: original.frame, corner: corner, to: current))
        case .resizingArrowEnd(let id, let original, let isStart, let current) where id == annotation.id:
            copy = original
            let newStart = isStart ? current : original.startPoint
            let newEnd = isStart ? original.endPoint : current
            copy.applyResize(
                newFrame: CoordinateConverter.normalizedDragRect(from: newStart, to: newEnd),
                newStart: newStart,
                newEnd: newEnd
            )
        default:
            break
        }
        return copy
    }

    private func makePreviewAnnotation(from start: CGPoint, to end: CGPoint) -> Annotation {
        let kind: AnnotationKind
        switch activeTool {
        case .arrow: kind = .arrow
        case .line: kind = .line
        case .rectangle: kind = .rectangle
        case .ellipse: kind = .ellipse
        case .text: kind = .text
        case .blur: kind = .blur
        case .select, .crop: kind = .rectangle
        }

        let rect = CoordinateConverter.normalizedDragRect(from: start, to: end)
        let frame = kind == .text && rect.width < 40
            ? CGRect(x: start.x, y: start.y, width: 200, height: max(currentStyle.fontSize * 1.6, 36))
            : rect

        return Annotation(
            kind: kind,
            frame: frame,
            startPoint: start,
            endPoint: end,
            style: currentStyle,
            text: kind == .text ? "Annotation" : nil,
            zIndex: commandStack.nextZIndex
        )
    }

    private func drawAnnotation(_ annotation: Annotation, in context: inout GraphicsContext) {
        let color = annotation.style.strokeColor.swiftUIColor
        let lineWidth = max(annotation.style.strokeWidth * zoomScale, 1.0)
        let scaledFrame = CGRect(
            x: annotation.frame.minX * zoomScale,
            y: annotation.frame.minY * zoomScale,
            width: annotation.frame.width * zoomScale,
            height: annotation.frame.height * zoomScale
        )

        switch annotation.kind {
        case .rectangle:
            let path = Path(scaledFrame)
            if annotation.style.isFilled {
                context.fill(path, with: .color(color.opacity(0.2)))
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)

        case .ellipse:
            let path = Path(ellipseIn: scaledFrame)
            if annotation.style.isFilled {
                context.fill(path, with: .color(color.opacity(0.2)))
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)

        case .line:
            let start = CGPoint(x: annotation.startPoint.x * zoomScale, y: annotation.startPoint.y * zoomScale)
            let end = CGPoint(x: annotation.endPoint.x * zoomScale, y: annotation.endPoint.y * zoomScale)
            guard hypot(end.x - start.x, end.y - start.y) >= 1 else { return }
            var linePath = Path()
            linePath.move(to: start)
            linePath.addLine(to: end)
            context.stroke(linePath, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

        case .arrow:
            let start = CGPoint(x: annotation.startPoint.x * zoomScale, y: annotation.startPoint.y * zoomScale)
            let end = CGPoint(x: annotation.endPoint.x * zoomScale, y: annotation.endPoint.y * zoomScale)
            let dx = end.x - start.x
            let dy = end.y - start.y
            let len = hypot(dx, dy)
            guard len >= 1 else { return }

            let angle = atan2(dy, dx)
            let headLength = max(lineWidth * 3.8, 12.0 * zoomScale)
            let headAngle: CGFloat = .pi / 6.0

            let shaftEnd = CGPoint(
                x: end.x - cos(angle) * (headLength * 0.65),
                y: end.y - sin(angle) * (headLength * 0.65)
            )
            var shaft = Path()
            shaft.move(to: start)
            shaft.addLine(to: shaftEnd)
            context.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            var head = Path()
            head.move(to: end)
            head.addLine(to: CGPoint(x: end.x - headLength * cos(angle - headAngle), y: end.y - headLength * sin(angle - headAngle)))
            head.addLine(to: CGPoint(x: end.x - headLength * cos(angle + headAngle), y: end.y - headLength * sin(angle + headAngle)))
            head.closeSubpath()
            context.fill(head, with: .color(color))

        case .text:
            let textValue = annotation.text ?? ""
            guard !textValue.isEmpty else { return }
            let resolved = context.resolve(
                Text(textValue)
                    .font(.system(size: annotation.style.fontSize * zoomScale, weight: .bold))
                    .foregroundColor(color)
            )
            context.draw(resolved, in: scaledFrame)

        case .blur:
            guard annotation.frame.width >= 2, annotation.frame.height >= 2 else { return }
            if let blurredCG = ImageRenderer.makeBlurredRegionImage(
                from: commandStack.document.baseImage,
                regionInPixels: annotation.frame,
                strength: annotation.style.strokeWidth
            ) {
                let imageBounds = CGRect(origin: .zero, size: commandStack.document.imagePixelSize)
                let clampedPx = CoordinateConverter.clampRect(annotation.frame.integral, to: imageBounds)
                let scaledClamped = CGRect(
                    x: clampedPx.minX * zoomScale,
                    y: clampedPx.minY * zoomScale,
                    width: clampedPx.width * zoomScale,
                    height: clampedPx.height * zoomScale
                )
                context.draw(
                    Image(decorative: blurredCG, scale: 1.0, orientation: .up).interpolation(.none),
                    in: scaledClamped
                )
                context.stroke(
                    Path(scaledClamped),
                    with: .color(.white.opacity(0.35)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
            }
        }
    }

    private func drawSelectionHandles(for annotation: Annotation, in context: inout GraphicsContext) {
        let handlePoints: [CGPoint]
        if annotation.kind == .arrow || annotation.kind == .line {
            handlePoints = [
                CGPoint(x: annotation.startPoint.x * zoomScale, y: annotation.startPoint.y * zoomScale),
                CGPoint(x: annotation.endPoint.x * zoomScale, y: annotation.endPoint.y * zoomScale),
            ]
        } else {
            let scaled = CGRect(
                x: annotation.frame.minX * zoomScale,
                y: annotation.frame.minY * zoomScale,
                width: annotation.frame.width * zoomScale,
                height: annotation.frame.height * zoomScale
            )
            context.stroke(
                Path(scaled.insetBy(dx: -2, dy: -2)),
                with: .color(.accentColor),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
            handlePoints = [
                CGPoint(x: scaled.minX, y: scaled.minY),
                CGPoint(x: scaled.maxX, y: scaled.minY),
                CGPoint(x: scaled.minX, y: scaled.maxY),
                CGPoint(x: scaled.maxX, y: scaled.maxY),
            ]
        }

        for point in handlePoints {
            let rect = CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)
            let circle = Path(ellipseIn: rect)
            context.fill(circle, with: .color(.white))
            context.stroke(circle, with: .color(.accentColor), lineWidth: 2)
        }
    }

    private func drawInteractiveCropOverlay(cropInPixels: CGRect, in context: inout GraphicsContext, canvasSize: CGSize) {
        let scaledCrop = CGRect(
            x: cropInPixels.minX * zoomScale,
            y: cropInPixels.minY * zoomScale,
            width: cropInPixels.width * zoomScale,
            height: cropInPixels.height * zoomScale
        )
        var dimPath = Path(CGRect(origin: .zero, size: canvasSize))
        dimPath.addRect(scaledCrop)
        context.fill(dimPath, with: .color(.black.opacity(0.52)), style: FillStyle(eoFill: true))

        // Rule of thirds grid inside crop rect
        if scaledCrop.width >= 30, scaledCrop.height >= 30 {
            var gridPath = Path()
            for step in 1...2 {
                let x = scaledCrop.minX + scaledCrop.width * CGFloat(step) / 3.0
                gridPath.move(to: CGPoint(x: x, y: scaledCrop.minY))
                gridPath.addLine(to: CGPoint(x: x, y: scaledCrop.maxY))

                let y = scaledCrop.minY + scaledCrop.height * CGFloat(step) / 3.0
                gridPath.move(to: CGPoint(x: scaledCrop.minX, y: y))
                gridPath.addLine(to: CGPoint(x: scaledCrop.maxX, y: y))
            }
            context.stroke(gridPath, with: .color(.white.opacity(0.35)), lineWidth: 1)
        }

        // Crisp border
        context.stroke(
            Path(scaledCrop),
            with: .color(.white),
            lineWidth: 2
        )

        // 4 Corner handles
        let corners = [
            CGPoint(x: scaledCrop.minX, y: scaledCrop.minY),
            CGPoint(x: scaledCrop.maxX, y: scaledCrop.minY),
            CGPoint(x: scaledCrop.minX, y: scaledCrop.maxY),
            CGPoint(x: scaledCrop.maxX, y: scaledCrop.maxY),
        ]
        for corner in corners {
            let handleRect = CGRect(x: corner.x - 5.5, y: corner.y - 5.5, width: 11, height: 11)
            let handlePath = Path(roundedRect: handleRect, cornerRadius: 2.5)
            context.fill(handlePath, with: .color(.white))
            context.stroke(handlePath, with: .color(.accentColor), lineWidth: 2)
        }
    }

    private func hitCornerHandle(in rect: CGRect, at pixelPoint: CGPoint) -> CornerHandle? {
        let tolerance = 14.0 / zoomScale
        let candidates: [(CornerHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
        ]
        return candidates.first { hypot(pixelPoint.x - $0.1.x, pixelPoint.y - $0.1.y) <= tolerance }?.0
    }

    private func resizedFrame(original: CGRect, corner: CornerHandle, to point: CGPoint) -> CGRect {
        let anchor: CGPoint
        switch corner {
        case .topLeft: anchor = CGPoint(x: original.maxX, y: original.maxY)
        case .topRight: anchor = CGPoint(x: original.minX, y: original.maxY)
        case .bottomLeft: anchor = CGPoint(x: original.maxX, y: original.minY)
        case .bottomRight: anchor = CGPoint(x: original.minX, y: original.minY)
        }
        return CoordinateConverter.normalizedDragRect(from: anchor, to: point)
    }

    private func toImagePixelPoint(_ viewPoint: CGPoint) -> CGPoint {
        let fullSize = commandStack.document.imagePixelSize
        let visiblePx = visibleImagePixelRect
        let x = min(max(visiblePx.minX + viewPoint.x / zoomScale, 0), fullSize.width)
        let y = min(max(visiblePx.minY + viewPoint.y / zoomScale, 0), fullSize.height)
        return CGPoint(x: x, y: y)
    }
}
