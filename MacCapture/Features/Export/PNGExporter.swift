import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public final class PNGExporter: ImageExporting, Sendable {
    private let clipboardService: ClipboardService

    public init(clipboardService: ClipboardService = ClipboardService()) {
        self.clipboardService = clipboardService
    }

    public func pngData(image: CGImage) throws -> Data {
        guard image.width > 0, image.height > 0 else {
            throw CaptureError.exportFailed("Image has invalid dimensions.")
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureError.exportFailed("Failed to create PNG image destination.")
        }

        // Strip extraneous metadata to protect privacy
        let cleanProperties: [CFString: Any] = [:]
        CGImageDestinationAddImage(destination, image, cleanProperties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.exportFailed("Failed to finalize PNG encoding.")
        }

        return mutableData as Data
    }

    public func savePNG(image: CGImage, to url: URL) throws {
        let data = try pngData(image: image)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw CaptureError.exportFailed(error.localizedDescription)
        }
    }

    public func copyImage(image: CGImage) throws {
        let data = try pngData(image: image)
        try clipboardService.copyPNGData(data, width: image.width, height: image.height)
    }

    public static func defaultFilename(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "MacCapture \(formatter.string(from: date)).png"
    }
}
