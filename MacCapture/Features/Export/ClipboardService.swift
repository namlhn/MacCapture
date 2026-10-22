import AppKit
import CoreGraphics
import Foundation

public final class ClipboardService: @unchecked Sendable {
    private let pasteboardName: NSPasteboard.Name?

    public init(pasteboardName: NSPasteboard.Name? = nil) {
        self.pasteboardName = pasteboardName
    }

    public func copyPNGData(_ pngData: Data, width: Int, height: Int) throws {
        guard !pngData.isEmpty else {
            throw CaptureError.exportFailed("Cannot copy empty PNG data to clipboard.")
        }

        let pasteboard: NSPasteboard = if let pasteboardName {
            NSPasteboard(name: pasteboardName)
        } else {
            NSPasteboard.general
        }

        pasteboard.clearContents()
        let wrotePNG = pasteboard.setData(pngData, forType: .png)
        if let nsImage = NSImage(data: pngData) {
            nsImage.size = NSSize(width: width, height: height)
            _ = pasteboard.writeObjects([nsImage])
        }

        guard wrotePNG else {
            throw CaptureError.exportFailed("Failed to write PNG data to system pasteboard.")
        }
    }
}
