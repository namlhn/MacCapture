import AppKit
import CoreGraphics
import Foundation
import ImageIO
import XCTest
#if canImport(MacCapture)
@testable import MacCapture
#endif

final class ExportTests: XCTestCase {
    func testFlattenDocumentWithAllAnnotationKindsPreservesPixelResolution() throws {
        let baseImage = try XCTUnwrap(ImageRenderer.makeSyntheticImage(width: 1200, height: 800, fill: .blue))
        let annotations: [Annotation] = [
            Annotation(
                kind: .rectangle,
                frame: CGRect(x: 80, y: 80, width: 300, height: 200),
                style: AnnotationStyle(strokeColor: .red, strokeWidth: 4, isFilled: true),
                zIndex: 0
            ),
            Annotation(
                kind: .ellipse,
                frame: CGRect(x: 450, y: 120, width: 240, height: 180),
                style: AnnotationStyle(strokeColor: .green, strokeWidth: 6),
                zIndex: 1
            ),
            Annotation(
                kind: .line,
                frame: CGRect(x: 50, y: 300, width: 250, height: 100),
                startPoint: CGPoint(x: 50, y: 300),
                endPoint: CGPoint(x: 300, y: 400),
                style: AnnotationStyle(strokeColor: .orange, strokeWidth: 4),
                zIndex: 2
            ),
            Annotation(
                kind: .arrow,
                frame: CGRect(x: 100, y: 400, width: 300, height: 150),
                startPoint: CGPoint(x: 100, y: 400),
                endPoint: CGPoint(x: 400, y: 550),
                style: AnnotationStyle(strokeColor: .yellow, strokeWidth: 5),
                zIndex: 3
            ),
            Annotation(
                kind: .text,
                frame: CGRect(x: 200, y: 600, width: 400, height: 60),
                style: AnnotationStyle(strokeColor: .white, strokeWidth: 4, fontSize: 28),
                text: "MacCapture Smoke Test",
                zIndex: 4
            ),
            Annotation(
                kind: .blur,
                frame: CGRect(x: 500, y: 400, width: 220, height: 120),
                style: AnnotationStyle(strokeColor: .red, strokeWidth: 6),
                zIndex: 5
            ),
        ]

        let document = CaptureDocument(baseImage: baseImage, annotations: annotations)
        let rendered = try ImageRenderer.render(document: document)

        XCTAssertEqual(rendered.width, 1200)
        XCTAssertEqual(rendered.height, 800)
    }

    func testFlattenDocumentWithCropProducesCroppedPixelDimensions() throws {
        let baseImage = try XCTUnwrap(ImageRenderer.makeSyntheticImage(width: 1920, height: 1080, fill: .purple))
        let cropRect = CGRect(x: 200, y: 100, width: 640, height: 360)
        let document = CaptureDocument(baseImage: baseImage, annotations: [], cropRect: cropRect)

        let rendered = try ImageRenderer.render(document: document)
        XCTAssertEqual(rendered.width, 640)
        XCTAssertEqual(rendered.height, 360)
    }

    func testPNGExportAndSaveRoundTrip() throws {
        let pasteboardName = NSPasteboard.Name("maccapture.test.pb.\(UUID().uuidString)")
        let clipboard = ClipboardService(pasteboardName: pasteboardName)
        let exporter = PNGExporter(clipboardService: clipboard)

        let image = try XCTUnwrap(ImageRenderer.makeSyntheticImage(width: 800, height: 600, fill: .orange))
        let pngData = try exporter.pngData(image: image)
        XCTAssertFalse(pngData.isEmpty)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("maccapture-smoke-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try exporter.savePNG(image: image, to: tempURL)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(tempURL as CFURL, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

        XCTAssertEqual(decoded.width, 800)
        XCTAssertEqual(decoded.height, 600)

        try exporter.copyImage(image: image)
        let pb = NSPasteboard(name: pasteboardName)
        let copiedData = pb.data(forType: .png)
        XCTAssertNotNil(copiedData)
        XCTAssertEqual(copiedData?.count, pngData.count)
    }

    func testSavePNGToInvalidDestinationThrowsExportError() throws {
        let exporter = PNGExporter()
        let image = try XCTUnwrap(ImageRenderer.makeSyntheticImage(width: 100, height: 100))
        let invalidURL = URL(fileURLWithPath: "/nonexistent-root-dir-\(UUID().uuidString)/out.png")

        XCTAssertThrowsError(try exporter.savePNG(image: image, to: invalidURL)) { error in
            guard case CaptureError.exportFailed = error else {
                return XCTFail("Expected CaptureError.exportFailed, got \(error)")
            }
        }
    }
}
