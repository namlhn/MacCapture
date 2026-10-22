# MacCapture — Professional Screen Capture & Annotation App for macOS

**English** • [Tiếng Việt](README.vi.md)

---

**MacCapture** is an ultra-lightweight, high-performance, native screen capture, scrolling capture, and non-destructive vector annotation utility built exclusively for **macOS 14.0+ (Sonoma and Sequoia)** using **Swift**, **AppKit**, **SwiftUI**, and Apple's modern **ScreenCaptureKit** framework.

Designed with a strict **100% Local & Offline** privacy-first philosophy, MacCapture requires zero accounts, collects zero telemetry, and starts instantly with a sleek frosted glass **Floating Toolbar** and a discreet **Menu Bar** companion.

---

## ✨ Key Features

### 1. Modern Floating Toolbar & Menu Bar Companion
- **Frosted Glass Aesthetic (`ultraThinMaterial`)**:
  - Embedded macOS squircle **App Logo** acts as both brand identity and an intuitive drag handle (double-click to quickly restore to default center position).
  - **Multi-Monitor Intelligent Positioning**: Persists relative coordinates per physical display and automatically clamps bounds when connecting or disconnecting external monitors.
  - **Auto-Collapse to Edge**: Snaps and collapses neatly against display edges into a subtle mini handle to keep screen real estate clutter-free.
  - **Full Control Flexibility**: Hide the floating toolbar anytime (`×`) and trigger all actions directly via the **Menu Bar** icon or global keyboard shortcuts.

### 2. Four Dedicated Capture Modes (`ScreenCaptureKit`)
| Mode | Default Shortcut | Details |
| :--- | :---: | :--- |
| **Region** | `⌃⌘1` | Drag anywhere on screen with crosshair guides and live physical pixel dimensions (`W × H px`), supporting seamless dragging across all 4 directions. |
| **Window** | `⌃⌘2` | Interactive hover selection highlighting windows with blue borders and app titles; captures clean isolated windows (`desktopIndependentWindow`) even when partially obscured. |
| **Fullscreen** | `⌃⌘3` | Instant full-screen screenshot at native Retina resolution (includes multi-display selection picker when multiple monitors are connected). |
| **Scrolling** | `⌃⌘4` | **Target any window or browser tab directly** (no manual bounding box required). Automatically activates the target window, drives smooth vertical scrolling down to page bottom (or until manually stopped via **Space** / **Stop**), deduplicates sticky headers/toolbars, and stitches into a single high-resolution panoramic image. |

- **Capture Timer Delay**: Selectable countdowns of `0s`, `3s`, `5s`, or `10s` directly from the toolbar (accompanied by a visible amber badge when delay is active).

### 3. Screen Recording — Region & Fullscreen (`ScreenCaptureKit` + `AVAssetWriter`)
- **Two Recording Modes**:
  - **Record Region**: Drag to select any custom area on screen. While recording, an on-screen **red dashed border frame with L-brackets and a `● REC W×H` badge** clearly marks the active recording boundary without blocking mouse clicks or keyboard input (`ignoresMouseEvents = true`).
  - **Record Fullscreen**: Record the entire active display at native Retina resolution.
- **Floating Recording HUD**: Displays a live elapsed timer (`MM:SS`), resolution/mode label, and a one-click **Stop** button positioned right beside the recorded region (or at the top of the screen for fullscreen). Both the HUD and the region border are automatically excluded from the output video via `SCContentFilter`.
- **Clean `.mp4` Output**: Encodes 30 FPS H.264 `.mp4` videos into `~/Movies/MacCapture/Screen Recording YYYY-MM-DD at HH.mm.ss.mp4` and automatically reveals the file in Finder when stopped.

### 4. Non-Destructive Vector Annotation Editor
Captured screenshots open immediately in a full-featured, zero-latency **Annotation Editor** window with active tool highlighting and a 50-step memory-efficient **Undo / Redo (`⌘Z` / `⇧⌘Z`)** command stack:

- **Select (`V`)**: Pick, reposition, resize via 8 bounding box anchor points, or delete (`Delete`) any drawn annotation.
- **Arrow (`A`)**: Draw sharp directional vector callout arrows.
- **Line (`L`)**: Draw straight line segments with draggable end vertices.
- **Rect (`R`)**: Draw rectangle frames with customizable stroke thickness, color palette, or optional semi-transparent fill.
- **Ellipse (`O`)**: Draw circles and ovals to highlight key areas.
- **Text (`T`)**: Add typography notes with an adaptive pill background for effortless legibility across light or dark backgrounds, complete with customizable font presets (`16pt`, `24pt`, `32pt`, `44pt`).
- **Blur (`B`) — Privacy & Redaction**:
  - Drag over sensitive screen information (passwords, auth tokens, banking details, private emails) to apply **Mosaic Pixelation** directly onto the underlying pixels.
  - 4 customizable pixelation granularity levels via the bottom blur controls.
  - Hardened and irreversibly flattened upon copy or PNG export, guaranteeing absolute data privacy.
- **Crop (`C`) — Two-Step Interactive Crop**:
  - Drag to define the target crop rectangle (outside area darkens with rule-of-thirds grid lines and 8 draggable corner/edge grips).
  - Adjust precisely, then click **`Finish Crop`** (or press `Enter`) to trim the canvas, or press **`Reset Original`** / `⌘Z` anytime to revert.

### 5. Pixel-Perfect Native Export (Clipboard & PNG)
- **Copy to Clipboard (`⌘C`)**: Flattens original capture + all vector annotations + pixelation blur + crop bounds at full physical Retina resolution (2x / 3x) straight into `NSPasteboard`.
- **Save Clean PNG (`⌘S` / `⇧⌘S`)**: Exports uncompressed PNG images stripped of sensitive metadata (GPS, EXIF, device info), automatically named with localized timestamps (`MacCapture YYYY-MM-DD at HH.mm.ss.png`).

---

## ⌨️ Keyboard Shortcuts

### Global Hotkeys
- `⌃⌘1`: Capture Region
- `⌃⌘2`: Capture Window
- `⌃⌘3`: Capture Fullscreen
- `⌃⌘4`: Capture Scrolling Window / Webpage
- `⌃⌘T`: Toggle Floating Toolbar Visibility

### In-App & Editor Hotkeys
- `Space` / `Return (Enter)`:
  - In **Scrolling Capture**: Stop scrolling and open stitched image in Editor.
  - In **Crop Mode**: Confirm and apply the crop boundaries.
- `Esc`: Cancel active capture or dismiss selection overlay.
- `⌘Z` / `⇧⌘Z`: Undo / Redo annotation actions.
- `Delete` / `Backspace`: Remove selected annotation object.
- `⌘C`: Copy flattened image to system Clipboard.
- `⌘S` / `⇧⌘S`: Quick Save PNG / Save As… dialog.

---

## 🏗️ Architecture & Project Structure

```text
MacCapture/
├── README.md                         # English documentation
├── README.vi.md                      # Vietnamese documentation
├── LICENSE                           # MIT License
├── plan.md                           # Specification & implementation roadmap
├── CONTRIBUTING.md                   # Contribution guidelines
├── docs/
│   ├── architecture.md               # Layered architecture & Architecture Decision Records (ADRs)
│   ├── ui-spec.md                    # Detailed UI specifications for Toolbar & Editor
│   ├── permission-guide.md           # Step-by-step Screen Recording & Accessibility guide
│   └── test-matrix.md                # Automated test matrix & manual validation criteria
├── MacCapture.xcodeproj/             # Native Xcode project (zero third-party dependencies)
├── build/
│   └── MacCapture.app                # Standalone pre-compiled Release application bundle
├── MacCapture/
│   ├── App/
│   │   ├── MacCaptureApp.swift       # SwiftUI app entry point
│   │   ├── AppDelegate.swift         # macOS application lifecycle manager
│   │   ├── AppCoordinator.swift      # Central coordinator connecting Toolbar, Capture, Editor & MenuBar
│   │   └── MenuBarController.swift   # Menu Bar status item & contextual menus
│   ├── Core/
│   │   ├── CaptureTypes.swift        # Core data models (CaptureMode, CaptureDisplay, CaptureWindow...)
│   │   ├── PermissionManager.swift   # System permission checks & onboarding prompts
│   │   └── HotkeyManager.swift       # Carbon RegisterEventHotKey global shortcut dispatcher
│   ├── Features/
│   │   ├── Toolbar/
│   │   │   ├── FloatingToolbarPanel.swift    # Non-activating floating NSPanel
│   │   │   ├── ToolbarView.swift             # SwiftUI Floating Toolbar view with AppLogoBadgeView
│   │   │   ├── ToolbarViewModel.swift        # Presentation state machine & user interaction bindings
│   │   │   └── ToolbarPositionStore.swift    # Multi-display position storage & clamping
│   │   ├── Capture/
│   │   │   ├── CaptureCoordinator.swift          # Capture workflow state machine
│   │   │   ├── ScreenCaptureEngine.swift         # ScreenCaptureKit engine with SCShareableContent caching
│   │   │   ├── RegionOverlayController.swift     # Interactive crosshair & live dimension overlay
│   │   │   ├── WindowSelectionController.swift   # Window / browser tab highlight & picker overlay
│   │   │   ├── ScrollingCaptureController.swift  # Automated scroll driver & vertical stitcher
│   │   │   └── CoordinateConverter.swift         # AppKit <-> CoreGraphics <-> Retina pixel coordinate transformations
│   │   ├── Recording/
│   │   │   ├── RecordingController.swift         # Screen recording lifecycle & countdown manager
│   │   │   └── ScreenRecorder.swift              # ScreenCaptureKit video stream & AVAssetWriter pipeline
│   │   ├── Editor/
│   │   │   ├── AnnotationModels.swift        # Vector data models (Arrow, Line, Rect, Ellipse, Text, Blur)
│   │   │   ├── AnnotationCommandStack.swift  # Command Pattern undo/redo stack
│   │   │   ├── AnnotationCanvas.swift        # Interactive canvas drawing surface & pixelation blur shader
│   │   │   ├── EditorView.swift              # Full annotation editor SwiftUI window & tool palette
│   │   │   └── EditorWindowController.swift  # Editor window lifecycle & save dialog management
│   │   ├── Export/
│   │   │   ├── ImageRenderer.swift           # High-resolution image compositor (base + vector + blur + crop)
│   │   │   ├── PNGExporter.swift             # Metadata-stripped PNG encoder via ImageIO
│   │   │   └── ClipboardService.swift        # High-res image clipboard pasteboard service
│   │   └── Settings/
│   │       ├── PreferencesStore.swift        # User preferences persistence (UserDefaults & Launch at Login)
│   │       └── PreferencesView.swift         # Settings window (General, Shortcuts, Privacy)
│   └── Resources/
│       ├── Assets.xcassets/                  # AppIcon asset catalog with all macOS sizes
│       ├── Info.plist                        # Bundle metadata & privacy usage descriptions
│       └── MacCapture.entitlements           # App security entitlements
├── MacCaptureTests/                          # Comprehensive unit test suite (21 unit tests)
└── MacCaptureUITests/                        # UI smoke test suite
```

---

## 🚀 Getting Started & Building

### Method 1: Launch the Pre-built `.app` (Recommended)
An optimized `Release` build is pre-compiled and ready at `build/MacCapture.app`. Open **Terminal** and run:

```bash
open /Users/win/Documents/antigravity/calm-einstein/build/MacCapture.app
```

You can also drag `build/MacCapture.app` into your `/Applications` directory to use it like any standard macOS app.

### Method 2: Open and Run in Xcode
```bash
open /Users/win/Documents/antigravity/calm-einstein/MacCapture.xcodeproj
```
Select the **`MacCapture`** scheme → Press **`⌘R` (Run)**.

### Method 3: Command-Line Build & Run Unit Tests
```bash
# Build Release binary
xcodebuild -project MacCapture.xcodeproj -scheme MacCapture -configuration Release build

# Run all 21 Unit Tests
xcodebuild test -project MacCapture.xcodeproj -scheme MacCapture -destination 'platform=macOS' -only-testing:MacCaptureTests
```

---

## 🔐 Required macOS Permissions

1. **Screen Recording (Required for Capture & Recording)**:
   - Navigate to `System Settings → Privacy & Security → Screen & System Audio Recording` and ensure **MacCapture** is toggled **ON**.
2. **Accessibility (Required for Scrolling Capture)**:
   - To enable automated mouse wheel scrolling events during **Scrolling Capture** (`Scroll`), navigate to `System Settings → Privacy & Security → Accessibility` and toggle **MacCapture** **ON**.
   - *(Note: If you recompile a new binary, toggle the switch off and on again so macOS updates the code signature).*

---

## 🛡️ Privacy & Security

- **100% Offline**: Zero network calls, zero analytics, zero telemetry.
- **Local Processing**: All image processing, vector rendering, and stitching happen entirely in memory on your Mac.
- **Clean Output**: Exported PNG files are automatically stripped of sensitive EXIF, GPS, and device metadata.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
