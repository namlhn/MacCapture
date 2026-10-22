import Combine
import CoreGraphics
import Foundation

public struct AnnotationGeometrySnapshot: Equatable, Sendable {
    public let frame: CGRect
    public let startPoint: CGPoint
    public let endPoint: CGPoint

    public init(frame: CGRect, startPoint: CGPoint, endPoint: CGPoint) {
        self.frame = frame
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    public init(annotation: Annotation) {
        self.frame = annotation.frame
        self.startPoint = annotation.startPoint
        self.endPoint = annotation.endPoint
    }
}

public enum AnnotationCommand: Equatable, Sendable {
    case add(Annotation)
    case remove(Annotation)
    case move(id: UUID, from: AnnotationGeometrySnapshot, to: AnnotationGeometrySnapshot)
    case resize(id: UUID, from: AnnotationGeometrySnapshot, to: AnnotationGeometrySnapshot)
    case updateStyle(id: UUID, oldStyle: AnnotationStyle, newStyle: AnnotationStyle)
    case updateText(id: UUID, oldText: String?, newText: String?)
    case updateCrop(oldCrop: CGRect?, newCrop: CGRect?)
}

@MainActor
public final class AnnotationCommandStack: ObservableObject {
    @Published public private(set) var document: CaptureDocument
    @Published public private(set) var undoStack: [AnnotationCommand] = []
    @Published public private(set) var redoStack: [AnnotationCommand] = []
    @Published public var selectedAnnotationID: UUID?

    public init(document: CaptureDocument) {
        self.document = document
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public var nextZIndex: Int {
        (document.annotations.map(\.zIndex).max() ?? -1) + 1
    }

    public func execute(_ command: AnnotationCommand) {
        apply(command, to: &document)
        undoStack.append(command)
        redoStack.removeAll()
    }

    public func undo() {
        guard let command = undoStack.popLast() else { return }
        apply(inverse(of: command), to: &document)
        redoStack.append(command)
    }

    public func redo() {
        guard let command = redoStack.popLast() else { return }
        apply(command, to: &document)
        undoStack.append(command)
    }

    public func replaceDocument(_ newDocument: CaptureDocument) {
        document = newDocument
        undoStack.removeAll()
        redoStack.removeAll()
        selectedAnnotationID = nil
    }

    public func addAnnotation(_ annotation: Annotation) {
        var item = annotation
        item.zIndex = nextZIndex
        execute(.add(item))
        selectedAnnotationID = item.id
    }

    public func removeAnnotation(id: UUID) {
        guard let existing = document.annotations.first(where: { $0.id == id }) else { return }
        execute(.remove(existing))
        if selectedAnnotationID == id {
            selectedAnnotationID = nil
        }
    }

    public func moveAnnotation(id: UUID, dx: CGFloat, dy: CGFloat) {
        guard abs(dx) > 0.001 || abs(dy) > 0.001,
              let existing = document.annotations.first(where: { $0.id == id }) else { return }
        let fromSnapshot = AnnotationGeometrySnapshot(annotation: existing)
        var moved = existing
        moved.applyOffset(dx: dx, dy: dy)
        let toSnapshot = AnnotationGeometrySnapshot(annotation: moved)
        execute(.move(id: id, from: fromSnapshot, to: toSnapshot))
    }

    public func resizeAnnotation(
        id: UUID,
        newFrame: CGRect,
        newStartPoint: CGPoint? = nil,
        newEndPoint: CGPoint? = nil
    ) {
        guard let existing = document.annotations.first(where: { $0.id == id }) else { return }
        let fromSnapshot = AnnotationGeometrySnapshot(annotation: existing)
        var resized = existing
        resized.applyResize(newFrame: newFrame, newStart: newStartPoint, newEnd: newEndPoint)
        let toSnapshot = AnnotationGeometrySnapshot(annotation: resized)
        guard fromSnapshot != toSnapshot else { return }
        execute(.resize(id: id, from: fromSnapshot, to: toSnapshot))
    }

    public func updateStyle(id: UUID, newStyle: AnnotationStyle) {
        guard let existing = document.annotations.first(where: { $0.id == id }),
              existing.style != newStyle else { return }
        execute(.updateStyle(id: id, oldStyle: existing.style, newStyle: newStyle))
    }

    public func updateText(id: UUID, newText: String?) {
        guard let existing = document.annotations.first(where: { $0.id == id }),
              existing.text != newText else { return }
        execute(.updateText(id: id, oldText: existing.text, newText: newText))
    }

    public func updateCrop(_ newCrop: CGRect?) {
        guard document.cropRect != newCrop else { return }
        execute(.updateCrop(oldCrop: document.cropRect, newCrop: newCrop))
    }

    private func inverse(of command: AnnotationCommand) -> AnnotationCommand {
        switch command {
        case .add(let annotation):
            return .remove(annotation)
        case .remove(let annotation):
            return .add(annotation)
        case .move(let id, let from, let to):
            return .move(id: id, from: to, to: from)
        case .resize(let id, let from, let to):
            return .resize(id: id, from: to, to: from)
        case .updateStyle(let id, let oldStyle, let newStyle):
            return .updateStyle(id: id, oldStyle: newStyle, newStyle: oldStyle)
        case .updateText(let id, let oldText, let newText):
            return .updateText(id: id, oldText: newText, newText: oldText)
        case .updateCrop(let oldCrop, let newCrop):
            return .updateCrop(oldCrop: newCrop, newCrop: oldCrop)
        }
    }

    private func apply(_ command: AnnotationCommand, to doc: inout CaptureDocument) {
        switch command {
        case .add(let annotation):
            if !doc.annotations.contains(where: { $0.id == annotation.id }) {
                doc.annotations.append(annotation)
            }
        case .remove(let annotation):
            doc.annotations.removeAll { $0.id == annotation.id }
        case .move(let id, _, let to), .resize(let id, _, let to):
            guard let idx = doc.annotations.firstIndex(where: { $0.id == id }) else { return }
            doc.annotations[idx].frame = to.frame
            doc.annotations[idx].startPoint = to.startPoint
            doc.annotations[idx].endPoint = to.endPoint
        case .updateStyle(let id, _, let newStyle):
            guard let idx = doc.annotations.firstIndex(where: { $0.id == id }) else { return }
            doc.annotations[idx].style = newStyle
        case .updateText(let id, _, let newText):
            guard let idx = doc.annotations.firstIndex(where: { $0.id == id }) else { return }
            doc.annotations[idx].text = newText
        case .updateCrop(_, let newCrop):
            doc.cropRect = newCrop
        }
    }
}
