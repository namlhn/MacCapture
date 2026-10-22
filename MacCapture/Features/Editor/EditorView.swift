import SwiftUI

public struct EditorView: View {
    @ObservedObject private var commandStack: AnnotationCommandStack
    @State private var activeTool: EditorTool = .arrow
    @State private var pendingCropRect: CGRect?
    @State private var currentStyle = AnnotationStyle()
    @State private var zoomScale: CGFloat = 1.0
    @State private var viewportSize: CGSize = CGSize(width: 860, height: 520)
    @State private var editingTextValue: String = ""
    @State private var statusBanner: StatusBanner?

    private let onCopyRequested: (CaptureDocument) -> Result<Void, CaptureError>
    private let onSaveRequested: (CaptureDocument, Bool) -> Result<URL?, CaptureError>

    public struct StatusBanner: Identifiable, Equatable {
        public let id = UUID()
        public let message: String
        public let isError: Bool
    }

    public init(
        commandStack: AnnotationCommandStack,
        onCopyRequested: @escaping (CaptureDocument) -> Result<Void, CaptureError>,
        onSaveRequested: @escaping (CaptureDocument, Bool) -> Result<URL?, CaptureError>
    ) {
        self.commandStack = commandStack
        self.onCopyRequested = onCopyRequested
        self.onSaveRequested = onSaveRequested
    }

    public var body: some View {
        VStack(spacing: 0) {
            topToolbar
            Divider()

            if let selectedTextAnnotation = selectedTextAnnotation {
                textEditorBar(for: selectedTextAnnotation)
                Divider()
            }

            if activeTool == .crop || commandStack.document.cropRect != nil {
                cropBar
                Divider()
            }

            ZStack(alignment: .top) {
                GeometryReader { geo in
                    ScrollView([.horizontal, .vertical]) {
                        ZStack {
                            AnnotationCanvas(
                                commandStack: commandStack,
                                pendingCropRect: $pendingCropRect,
                                activeTool: activeTool,
                                currentStyle: currentStyle,
                                zoomScale: zoomScale,
                                onRequestTextFocus: { id in
                                    commandStack.selectedAnnotationID = id
                                    if let ann = commandStack.document.annotations.first(where: { $0.id == id }) {
                                        editingTextValue = ann.text ?? ""
                                    }
                                },
                                onConfirmCrop: {
                                    confirmPendingCrop()
                                },
                                onCancelCrop: {
                                    cancelPendingCrop()
                                }
                            )
                            .overlay(
                                Rectangle()
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                            )
                            .padding(32)
                        }
                        .frame(
                            minWidth: max(geo.size.width, 200),
                            minHeight: max(geo.size.height, 200)
                        )
                    }
                    .background(canvasBackdrop)
                    .onAppear {
                        viewportSize = geo.size
                    }
                    .onChange(of: geo.size) { _, newSize in
                        viewportSize = newSize
                    }
                    .gesture(
                        MagnificationGesture()
                            .onEnded { factor in
                                let next = min(max(zoomScale * factor, 0.25), 3.0)
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    zoomScale = next
                                }
                            }
                    )
                }

                if let banner = statusBanner {
                    bannerToast(banner)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            Divider()
            bottomInspectorBar
        }
        .frame(minWidth: 920, minHeight: 560)
        .onChange(of: activeTool) { _, newTool in
            if newTool == .crop {
                commandStack.selectedAnnotationID = nil
                if pendingCropRect == nil {
                    pendingCropRect = commandStack.document.cropRect
                }
            } else {
                pendingCropRect = nil
            }
        }
        .onChange(of: commandStack.selectedAnnotationID) { _, newID in
            guard let newID,
                  let selected = commandStack.document.annotations.first(where: { $0.id == newID }) else {
                return
            }
            currentStyle = selected.style
            editingTextValue = selected.text ?? ""
        }
        .accessibilityIdentifier("EditorRootView")
    }

    private var canvasBackdrop: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            LinearGradient(
                colors: [
                    Color.black.opacity(0.10),
                    Color.clear,
                    Color.black.opacity(0.14),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var selectedTextAnnotation: Annotation? {
        guard let id = commandStack.selectedAnnotationID,
              let ann = commandStack.document.annotations.first(where: { $0.id == id }),
              ann.kind == .text else {
            return nil
        }
        return ann
    }

    // MARK: - Top Toolbar

    private var topToolbar: some View {
        HStack(spacing: 12) {
            // Brand Logo Badge at the very start of the Editor Toolbar
            HStack(spacing: 8) {
                AppLogoBadgeView(size: 28)
                Text("MacCapture")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .padding(.trailing, 2)

            Divider()
                .frame(height: 20)
                .opacity(0.5)

            // Undo / Redo Capsule Group
            HStack(spacing: 2) {
                EditorIconButton(
                    title: "Undo",
                    symbol: "arrow.uturn.backward",
                    isEnabled: commandStack.canUndo,
                    action: { commandStack.undo() }
                )
                .keyboardShortcut("z", modifiers: [.command])
                .help("Undo (⌘Z)")
                .accessibilityIdentifier("EditorButton_Undo")

                Divider()
                    .frame(height: 18)
                    .opacity(0.5)

                EditorIconButton(
                    title: "Redo",
                    symbol: "arrow.uturn.forward",
                    isEnabled: commandStack.canRedo,
                    action: { commandStack.redo() }
                )
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help("Redo (⇧⌘Z)")
                .accessibilityIdentifier("EditorButton_Redo")
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )

            // Segmented Drawing Tools Dock
            HStack(spacing: 4) {
                ForEach(EditorTool.allCases, id: \.self) { tool in
                    EditorToolPillButton(
                        tool: tool,
                        isSelected: activeTool == tool,
                        action: {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                activeTool = tool
                            }
                        }
                    )
                    .accessibilityIdentifier("EditorTool_\(tool.rawValue)")
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )

            if let selectedID = commandStack.selectedAnnotationID {
                Button(role: .destructive) {
                    commandStack.removeAnnotation(id: selectedID)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Delete")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.red.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.delete, modifiers: [])
                .help("Delete Selected Annotation (Delete)")
                .accessibilityIdentifier("EditorButton_Delete")
            }

            Spacer(minLength: 8)

            // Copy & Save Actions
            HStack(spacing: 8) {
                EditorActionPillButton(
                    title: "Copy",
                    symbol: "doc.on.doc.fill",
                    isPrimary: false,
                    action: { performCopy() }
                )
                .keyboardShortcut("c", modifiers: [.command])
                .help("Copy Annotated Image to Clipboard (⌘C)")
                .accessibilityIdentifier("EditorButton_Copy")

                HStack(spacing: 1) {
                    EditorActionPillButton(
                        title: "Save PNG",
                        symbol: "square.and.arrow.down.fill",
                        isPrimary: true,
                        action: { performSave(saveAs: false) }
                    )
                    .keyboardShortcut("s", modifiers: [.command])
                    .help("Save PNG (⌘S)")
                    .accessibilityIdentifier("EditorButton_Save")

                    Button {
                        performSave(saveAs: true)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.88))
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .help("Save As… (⇧⌘S)")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Contextual Sub-bars

    private func textEditorBar(for annotation: Annotation) -> some View {
        HStack(spacing: 10) {
            Label("Edit Text", systemImage: "textformat")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            TextField("Type annotation text…", text: $editingTextValue)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    commandStack.updateText(id: annotation.id, newText: editingTextValue)
                }
                .accessibilityIdentifier("EditorTextField_AnnotationText")

            Button {
                commandStack.updateText(id: annotation.id, newText: editingTextValue)
            } label: {
                Text("Apply")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("EditorButton_ApplyText")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.07))
    }

    private var cropBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "crop")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(activeTool == .crop ? Color.accentColor : Color.orange)

            if activeTool == .crop {
                if let pending = pendingCropRect {
                    Text("Vùng cắt: \(Int(pending.width)) × \(Int(pending.height)) px")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    Text("• Kéo 4 góc hoặc kéo bên trong khung để tinh chỉnh")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Kéo chuột trên ảnh để chọn vùng muốn cắt (Crop)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if commandStack.document.cropRect != nil {
                    Button {
                        commandStack.updateCrop(nil)
                        pendingCropRect = nil
                    } label: {
                        Label("Khôi phục ảnh gốc", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("EditorButton_ResetCrop")
                }

                Button {
                    cancelPendingCrop()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Hủy")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Cancel Crop (Esc)")

                Button {
                    confirmPendingCrop()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Hoàn thành Crop")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(pendingCropRect != nil ? Color.green : Color.secondary.opacity(0.35))
                    )
                }
                .buttonStyle(.plain)
                .disabled(pendingCropRect == nil)
                .keyboardShortcut(.defaultAction)
                .help("Apply Crop (Return / Enter)")
                .accessibilityIdentifier("EditorButton_ConfirmCrop")
            } else if let appliedCrop = commandStack.document.cropRect {
                Text("Đã cắt ảnh: \(Int(appliedCrop.width)) × \(Int(appliedCrop.height)) px")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())

                Spacer()

                Button {
                    pendingCropRect = appliedCrop
                    activeTool = .crop
                } label: {
                    Label("Chỉnh lại vùng cắt", systemImage: "crop")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    commandStack.updateCrop(nil)
                } label: {
                    Label("Khôi phục ảnh gốc", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.orange.opacity(0.18))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("EditorButton_ResetCrop")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(activeTool == .crop ? Color.accentColor.opacity(0.09) : Color.orange.opacity(0.09))
    }

    private func bannerToast(_ banner: StatusBanner) -> some View {
        HStack(spacing: 8) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(banner.isError ? .red : .green)
            Text(banner.message)
                .font(.system(size: 12, weight: .medium))
            Button {
                withAnimation {
                    statusBanner = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    (banner.isError ? Color.red : Color.green).opacity(0.45),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }

    // MARK: - Bottom Inspector & Status Bar

    private var bottomInspectorBar: some View {
        let outputSize = commandStack.document.effectiveOutputPixelSize
        return HStack(spacing: 14) {
            // Active Tool Indicator Pill
            HStack(spacing: 5) {
                Image(systemName: activeTool.symbolName)
                    .font(.system(size: 11, weight: .bold))
                Text(activeTool.title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.14))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
            )

            Divider()
                .frame(height: 18)

            // Color Palette Swatches
            HStack(spacing: 7) {
                ForEach(RGBAColor.palette, id: \.self) { color in
                    let isSelected = currentStyle.strokeColor == color
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                            applyStrokeColor(color)
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 18, height: 18)
                                .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)

                            if isSelected {
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 2)
                                    .frame(width: 18, height: 18)
                                Circle()
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                                    .frame(width: 24, height: 24)
                            } else {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                                    .frame(width: 18, height: 18)
                            }
                        }
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Select stroke color")
                }
            }

            Divider()
                .frame(height: 18)

            // Visual Stroke Width / Blur Intensity Pills
            HStack(spacing: 4) {
                Text(activeTool == .blur ? "Blur" : "Stroke")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                ForEach([CGFloat(2), CGFloat(4), CGFloat(6), CGFloat(8)], id: \.self) { width in
                    let isSelected = currentStyle.strokeWidth == width
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            applyStrokeWidth(width)
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Capsule()
                                .fill(isSelected ? Color.white : Color.primary.opacity(0.75))
                                .frame(width: 16, height: max(width * 0.85, 2))
                            Text("\(Int(width))")
                                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        }
                        .frame(width: 28, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color.primary.opacity(0.10),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Stroke width: \(Int(width)) pt")
                }
            }

            // Fill toggle for Rectangle / Ellipse
            if activeTool == .rectangle || activeTool == .ellipse {
                Button {
                    currentStyle.isFilled.toggle()
                    syncSelectedStyle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: currentStyle.isFilled ? "square.fill" : "square.dotted")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Fill")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(currentStyle.isFilled ? .white : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(currentStyle.isFilled ? Color.accentColor : Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .help("Toggle translucent shape fill")
            }

            Divider()
                .frame(height: 18)

            // Font Size Menu
            Menu {
                ForEach([CGFloat(16), CGFloat(24), CGFloat(32), CGFloat(44)], id: \.self) { size in
                    Button {
                        applyFontSize(size)
                    } label: {
                        HStack {
                            Text("\(Int(size)) pt")
                            if currentStyle.fontSize == size {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 11, weight: .medium))
                    Text("\(Int(currentStyle.fontSize)) pt")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Text Font Size")

            Spacer()

            // Zoom Controls & Image Size Badge
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            zoomScale = max(zoomScale - 0.25, 0.25)
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Zoom Out")

                    Menu {
                        Button("Fit to Window") { fitToWindow() }
                        Divider()
                        Button("50%") { zoomScale = 0.5 }
                        Button("100% (Actual Pixels)") { zoomScale = 1.0 }
                        Button("200%") { zoomScale = 2.0 }
                    } label: {
                        Text("\(Int((zoomScale * 100).rounded()))%")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .frame(width: 48)
                    }
                    .menuStyle(.borderlessButton)

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            zoomScale = min(zoomScale + 0.25, 3.0)
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Zoom In")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )

                Text("\(Int(outputSize.width)) × \(Int(outputSize.height)) px")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .accessibilityIdentifier("EditorLabel_PixelSize")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private func confirmPendingCrop() {
        guard let crop = pendingCropRect, crop.width >= 8, crop.height >= 8 else { return }
        let bounds = CGRect(origin: .zero, size: commandStack.document.imagePixelSize)
        let clamped = CoordinateConverter.clampRect(crop.integral, to: bounds)
        guard clamped.width >= 8, clamped.height >= 8 else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            commandStack.updateCrop(clamped)
            pendingCropRect = nil
            activeTool = .select
        }
        showBanner(
            message: "Đã cắt ảnh thành \(Int(clamped.width)) × \(Int(clamped.height)) px (Nhấn ⌘Z để hoàn tác).",
            isError: false
        )
    }

    private func cancelPendingCrop() {
        withAnimation(.easeInOut(duration: 0.15)) {
            pendingCropRect = nil
            activeTool = .select
        }
    }

    private func fitToWindow() {
        let imgSize = commandStack.document.effectiveOutputPixelSize
        guard imgSize.width > 0, imgSize.height > 0 else { return }
        let availableW = max(viewportSize.width - 72, 200)
        let availableH = max(viewportSize.height - 72, 200)
        let scale = min(availableW / imgSize.width, availableH / imgSize.height, 1.0)
        withAnimation(.easeInOut(duration: 0.18)) {
            zoomScale = max(scale, 0.25)
        }
    }

    private func applyStrokeColor(_ color: RGBAColor) {
        currentStyle.strokeColor = color
        syncSelectedStyle()
    }

    private func applyStrokeWidth(_ width: CGFloat) {
        currentStyle.strokeWidth = width
        syncSelectedStyle()
    }

    private func applyFontSize(_ size: CGFloat) {
        currentStyle.fontSize = size
        syncSelectedStyle()
    }

    private func syncSelectedStyle() {
        if let selectedID = commandStack.selectedAnnotationID {
            commandStack.updateStyle(id: selectedID, newStyle: currentStyle)
        }
    }

    private func performCopy() {
        switch onCopyRequested(commandStack.document) {
        case .success:
            showBanner(message: "Copied flattened PNG image to clipboard.", isError: false)
        case .failure(let error):
            showBanner(message: error.localizedDescription, isError: true)
        }
    }

    private func performSave(saveAs: Bool) {
        switch onSaveRequested(commandStack.document, saveAs) {
        case .success(let url):
            if let url {
                showBanner(message: "Saved PNG to \(url.lastPathComponent).", isError: false)
            }
        case .failure(let error):
            showBanner(message: error.localizedDescription, isError: true)
        }
    }

    private func showBanner(message: String, isError: Bool) {
        let banner = StatusBanner(message: message, isError: isError)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            statusBanner = banner
        }
        if !isError {
            let bannerID = banner.id
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                if statusBanner?.id == bannerID {
                    withAnimation(.easeOut(duration: 0.2)) {
                        statusBanner = nil
                    }
                }
            }
        }
    }
}

// MARK: - Custom Professional Button Components

private struct EditorToolPillButton: View {
    let tool: EditorTool
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tool.symbolName)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                Text(tool.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Color.white : (isHovering ? Color.primary : Color.primary.opacity(0.82)))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor,
                                        Color.accentColor.opacity(0.85),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: Color.accentColor.opacity(0.38), radius: 5, x: 0, y: 2)
                    } else if isHovering {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.09))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.white.opacity(0.28) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help("\(tool.title) Tool (\(tool.shortcutHint))")
    }
}

private struct EditorIconButton: View {
    let title: String
    let symbol: String
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.45))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovering && isEnabled ? Color.primary.opacity(0.09) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct EditorActionPillButton: View {
    let title: String
    let symbol: String
    let isPrimary: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isPrimary ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isPrimary
                            ? (isHovering ? Color.accentColor.opacity(0.9) : Color.accentColor)
                            : (isHovering ? Color.primary.opacity(0.12) : Color.primary.opacity(0.07))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isPrimary ? Color.white.opacity(0.22) : Color.primary.opacity(0.14),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isPrimary ? Color.accentColor.opacity(0.28) : .clear,
                radius: 4,
                x: 0,
                y: 2
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
