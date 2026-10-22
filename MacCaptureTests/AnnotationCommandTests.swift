import CoreGraphics
import Foundation
import XCTest
#if canImport(MacCapture)
@testable import MacCapture
#endif

@MainActor
final class AnnotationCommandTests: XCTestCase {
    private func makeStack() -> AnnotationCommandStack {
        let baseImage = ImageRenderer.makeSyntheticImage(width: 1920, height: 1080)!
        let doc = CaptureDocument(baseImage: baseImage)
        return AnnotationCommandStack(document: doc)
    }

    func testAddRemoveUndoRedo() {
        let stack = makeStack()
        let arrow = Annotation(
            kind: .arrow,
            frame: CGRect(x: 10, y: 20, width: 100, height: 80),
            startPoint: CGPoint(x: 10, y: 20),
            endPoint: CGPoint(x: 110, y: 100)
        )

        stack.addAnnotation(arrow)
        XCTAssertEqual(stack.document.annotations.count, 1)
        XCTAssertTrue(stack.canUndo)

        stack.undo()
        XCTAssertTrue(stack.document.annotations.isEmpty)
        XCTAssertTrue(stack.canRedo)

        stack.redo()
        XCTAssertEqual(stack.document.annotations.count, 1)

        stack.removeAnnotation(id: arrow.id)
        XCTAssertTrue(stack.document.annotations.isEmpty)

        stack.undo()
        XCTAssertEqual(stack.document.annotations.count, 1)
    }

    func testMoveAndResizeUndoRedo() {
        let stack = makeStack()
        let rect = Annotation(
            kind: .rectangle,
            frame: CGRect(x: 50, y: 60, width: 200, height: 120)
        )
        stack.addAnnotation(rect)

        stack.moveAnnotation(id: rect.id, dx: 30, dy: -20)
        XCTAssertEqual(stack.document.annotations[0].frame, CGRect(x: 80, y: 40, width: 200, height: 120))

        stack.undo()
        XCTAssertEqual(stack.document.annotations[0].frame, CGRect(x: 50, y: 60, width: 200, height: 120))

        stack.redo()
        XCTAssertEqual(stack.document.annotations[0].frame, CGRect(x: 80, y: 40, width: 200, height: 120))

        let resizedFrame = CGRect(x: 80, y: 40, width: 320, height: 240)
        stack.resizeAnnotation(id: rect.id, newFrame: resizedFrame)
        XCTAssertEqual(stack.document.annotations[0].frame, resizedFrame)

        stack.undo()
        XCTAssertEqual(stack.document.annotations[0].frame, CGRect(x: 80, y: 40, width: 200, height: 120))

        stack.redo()
        XCTAssertEqual(stack.document.annotations[0].frame, resizedFrame)
    }

    func testUpdateStyleTextAndCropUndoRedo() {
        let stack = makeStack()
        let textAnnotation = Annotation(
            kind: .text,
            frame: CGRect(x: 100, y: 100, width: 240, height: 50),
            style: AnnotationStyle(strokeColor: .red, strokeWidth: 4, fontSize: 24),
            text: "Initial"
        )
        stack.addAnnotation(textAnnotation)

        let newStyle = AnnotationStyle(strokeColor: .green, strokeWidth: 6, fontSize: 32)
        stack.updateStyle(id: textAnnotation.id, newStyle: newStyle)
        XCTAssertEqual(stack.document.annotations[0].style, newStyle)

        stack.undo()
        XCTAssertEqual(stack.document.annotations[0].style.strokeColor, .red)

        stack.redo()
        XCTAssertEqual(stack.document.annotations[0].style, newStyle)

        stack.updateText(id: textAnnotation.id, newText: "Updated Caption")
        XCTAssertEqual(stack.document.annotations[0].text, "Updated Caption")

        stack.undo()
        XCTAssertEqual(stack.document.annotations[0].text, "Initial")

        stack.redo()
        XCTAssertEqual(stack.document.annotations[0].text, "Updated Caption")

        let crop = CGRect(x: 200, y: 150, width: 800, height: 600)
        stack.updateCrop(crop)
        XCTAssertEqual(stack.document.cropRect, crop)
        XCTAssertEqual(stack.document.effectiveOutputPixelSize, CGSize(width: 800, height: 600))

        stack.undo()
        XCTAssertNil(stack.document.cropRect)
        XCTAssertEqual(stack.document.effectiveOutputPixelSize, CGSize(width: 1920, height: 1080))

        stack.redo()
        XCTAssertEqual(stack.document.cropRect, crop)
    }

    func testZIndexSortingAndHitTesting() {
        let stack = makeStack()
        let first = Annotation(kind: .rectangle, frame: CGRect(x: 10, y: 10, width: 100, height: 100))
        let second = Annotation(
            kind: .arrow,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 100, y: 100)
        )
        stack.addAnnotation(first)
        stack.addAnnotation(second)

        let sorted = stack.document.sortedAnnotations
        XCTAssertEqual(sorted.map(\.id), [first.id, second.id])
        XCTAssertLessThan(sorted[0].zIndex, sorted[1].zIndex)

        XCTAssertTrue(second.hitTest(CGPoint(x: 50, y: 50), tolerance: 6))
        XCTAssertFalse(second.hitTest(CGPoint(x: 90, y: 10), tolerance: 6))
    }
}
