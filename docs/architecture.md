# MacCapture — Architecture & ADRs

## 1. Module Boundaries

MacCapture is organized into strict, single-responsibility layers:

| Module | Directory | Responsibility | Prohibited Dependencies |
|---|---|---|---|
| **AppShell** | `MacCapture/App` | App lifecycle, `NSStatusItem` menu bar, window coordination | Raw pixel manipulation, direct `ScreenCaptureKit` calls |
| **Toolbar** | `MacCapture/Features/Toolbar` | Floating `NSPanel`, SwiftUI compact bar, display-relative position persistence | Direct `ScreenCaptureKit` or file export calls |
| **Capture** | `MacCapture/Features/Capture` | `CaptureCoordinator` state machine, `ScreenCaptureEngine`, Region & Window overlays, `CoordinateConverter` | Vector annotation rendering |
| **Editor** | `MacCapture/Features/Editor` | `CaptureDocument`, vector `Annotation` layers, `AnnotationCommandStack` Undo/Redo, interactive canvas | Requesting OS screen capture permissions |
| **Export** | `MacCapture/Features/Export` | Full-resolution CoreGraphics flattening (`ImageRenderer`), `ImageIO` PNG encoding, `NSPasteboard` export | Creating UI windows or panels |
| **Settings** | `MacCapture/Features/Settings` | `PreferencesStore` (`UserDefaults` + `SMAppService`), `PreferencesView` | Retaining `CGImage` screenshots |
| **Core** | `MacCapture/Core` | Shared domain models, `PermissionManager`, Carbon `HotkeyManager` | `NSPanel` or Editor views |

## 2. State Machine (`CaptureCoordinator`)

```text
idle
  ├── startCapture(mode) → checkingPermission(mode)
  │     ├── denied → permissionHelp(mode) → idle
  │     └── granted → [countdown] → selectingRegion | selectingWindow | capturingFullscreen
  │                                       ├── cancelled → cleanup overlays + restore toolbar → idle
  │                                       └── selected → capturing(mode)
  │                                                         ├── failure → cleanup + restore toolbar → error(CaptureError)
  │                                                         └── success → editing(document.id)
  └── openDocumentInEditor → editing(document.id)
```

## 3. Architectural Decision Records (ADRs)

### ADR-001: Native SwiftUI + AppKit over Electron
- **Decision:** Build with native Swift, AppKit (`NSPanel`, `NSStatusItem`, `NSWindow`), and SwiftUI.
- **Rationale:** Instant startup, low memory footprint, direct access to `ScreenCaptureKit` and `NSScreen` backing scale factors, and native visual materials.

### ADR-002: Floating Toolbar via Non-Activating `NSPanel` + Menu Bar Fallback
- **Decision:** Host `ToolbarView` inside a borderless, `.nonactivatingPanel` `FloatingToolbarPanel` paired with an always-present `NSStatusItem` menu.
- **Rationale:** Allows one-click capture without stealing focus from the active application, while guaranteeing full recoverability from the menu bar if hidden.

### ADR-003: `ScreenCaptureKit` Behind `CaptureEngineProtocol`
- **Decision:** Encapsulate `SCShareableContent`, `SCContentFilter`, and `SCScreenshotManager` inside `ScreenCaptureEngine: CaptureEngineProtocol`.
- **Rationale:** Enables deterministic unit testing of `CaptureCoordinator` using mock engines and cleanly excludes MacCapture's own windows from captures.

### ADR-004: Vector Annotation Layers with On-Demand High-Resolution Flattening
- **Decision:** Store annotations (`arrow`, `rectangle`, `ellipse`, `text`) and `cropRect` as lightweight value types in `CaptureDocument`, with command-based Undo/Redo in `AnnotationCommandStack`. Flatten to a bitmap via `ImageRenderer` only when copying or saving.
- **Rationale:** Prevents duplicating full-resolution 4K/Retina bitmaps on every edit or Undo step.

### ADR-005: Strictly Offline MVP (Zero Telemetry / Zero Network)
- **Decision:** No network requests, analytics SDKs, or cloud uploads in the capture or editor pipelines.
- **Rationale:** Screen captures frequently contain sensitive user data; offline-only operation maximizes user trust and satisfies `P-07`.

### ADR-006: Defer Scrolling Capture (v0.2) and Screen Recording (v0.3)
- **Decision:** Keep scrolling stitch pipelines and `AVFoundation` video recording out of the v0.1 MVP coordinator.
- **Rationale:** Prevents scope creep and ensures core static capture and annotation reach production quality first.
