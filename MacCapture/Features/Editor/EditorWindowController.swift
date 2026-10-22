import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private let commandStack: AnnotationCommandStack
    private let exporter: ImageExporting
    private var lastSavedURL: URL?
    public var onWindowClosed: (() -> Void)?

    public init(
        document: CaptureDocument,
        exporter: ImageExporting = PNGExporter()
    ) {
        self.commandStack = AnnotationCommandStack(document: document)
        self.exporter = exporter

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 920, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacCapture Editor"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        let rootView = EditorView(
            commandStack: commandStack,
            onCopyRequested: { [weak self] doc in
                guard let self else { return .failure(.exportFailed("Editor deallocated.")) }
                return self.copyDocument(doc)
            },
            onSaveRequested: { [weak self] doc, forcePrompt in
                guard let self else { return .failure(.exportFailed("Editor deallocated.")) }
                return self.saveDocument(doc, forceSavePanel: forcePrompt)
            }
        )
        window.contentView = NSHostingView(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func present(document: CaptureDocument) {
        lastSavedURL = nil
        commandStack.replaceDocument(document)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func openImageFilePicker() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Open Image in MacCapture Editor"
        openPanel.allowedContentTypes = [.png, .jpeg, .tiff]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false

        guard openPanel.runModal() == .OK,
              let url = openPanel.url,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return
        }

        let document = CaptureDocument(baseImage: cgImage)
        present(document: document)
    }

    public func copyDocument(_ document: CaptureDocument) -> Result<Void, CaptureError> {
        do {
            let flattened = try ImageRenderer.render(document: document)
            try exporter.copyImage(image: flattened)
            return .success(())
        } catch let error as CaptureError {
            return .failure(error)
        } catch {
            return .failure(.exportFailed(error.localizedDescription))
        }
    }

    public func saveDocument(
        _ document: CaptureDocument,
        forceSavePanel: Bool
    ) -> Result<URL?, CaptureError> {
        let destinationURL: URL
        if !forceSavePanel, let existingURL = lastSavedURL {
            destinationURL = existingURL
        } else {
            let savePanel = NSSavePanel()
            savePanel.title = "Save Annotated Screenshot"
            savePanel.allowedContentTypes = [.png]
            savePanel.canCreateDirectories = true
            savePanel.nameFieldStringValue = PNGExporter.defaultFilename(for: document.capturedAt)

            guard savePanel.runModal() == .OK, let chosenURL = savePanel.url else {
                return .success(nil)
            }
            destinationURL = chosenURL
        }

        do {
            let flattened = try ImageRenderer.render(document: document)
            try exporter.savePNG(image: flattened, to: destinationURL)
            lastSavedURL = destinationURL
            return .success(destinationURL)
        } catch let error as CaptureError {
            return .failure(error)
        } catch {
            return .failure(.exportFailed(error.localizedDescription))
        }
    }

    public func windowWillClose(_ notification: Notification) {
        onWindowClosed?()
    }
}
