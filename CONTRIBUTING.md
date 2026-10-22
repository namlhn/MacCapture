# Contributing to MacCapture

Thank you for your interest in contributing to **MacCapture**!

## Development Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16+ (Swift 6 toolchain)
- No third-party runtime dependencies for MVP (pure Apple frameworks: AppKit, SwiftUI, ScreenCaptureKit, CoreGraphics, ImageIO, Carbon, ServiceManagement)

## Principles

1. **Privacy First**: Never add telemetry, analytics, or network requests in the capture/editor pipeline.
2. **Modular Boundaries**:
   - `Core`: Shared types, permission checks, hotkey registration. No `NSPanel` dependencies.
   - `Features/Toolbar`: Floating `NSPanel`, SwiftUI toolbar view, position persistence. Must not call `ScreenCaptureKit` directly.
   - `Features/Capture`: `CaptureCoordinator` state machine, `ScreenCaptureEngine`, overlays, and coordinate conversion.
   - `Features/Editor`: Non-destructive vector annotations (`CaptureDocument`), command-based Undo/Redo, and canvas interactions.
   - `Features/Export`: High-resolution bitmap rendering, PNG encoding via `ImageIO`, and `NSPasteboard` clipboard export.
3. **Retina & Multi-Display Correctness**: Always use `CoordinateConverter` when converting between AppKit screen points, ScreenCaptureKit display-local points, and backing pixels.
4. **Testing**: Every feature or bug fix must include unit tests in `MacCaptureTests` using synthetic test images (never user screenshots).

## Running Tests

```bash
xcodebuild test \
  -project MacCapture.xcodeproj \
  -scheme MacCapture \
  -destination 'platform=macOS'
```
