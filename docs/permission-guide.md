# MacCapture — Screen Recording Permission Guide

## Why Permission Is Required

macOS protects screen contents through the **Screen & System Audio Recording** privacy control. MacCapture uses Apple's native `ScreenCaptureKit` framework to capture:
- Selected screen regions (`CaptureMode.region`)
- Specific application windows (`CaptureMode.window`) without capturing overlapping windows
- Full displays (`CaptureMode.fullscreen`) at native Retina resolution

## How MacCapture Handles Permissions

1. **On-Demand Request Only:** MacCapture never prompts for Screen Recording permission on launch. It checks permission via `CGPreflightScreenCaptureAccess()` only when you initiate a capture.
2. **Graceful Denial Recovery:** If permission is not granted:
   - MacCapture transitions cleanly to `.permissionHelp` without crashing or leaving stuck overlays.
   - An informational dialog explains why permission is needed and provides one-click access to **System Settings → Privacy & Security → Screen & System Audio Recording** alongside a **Retry Capture** button.
3. **No Extra Permissions in MVP:**
   - **Accessibility** permission is **not** requested in v0.1.
   - **Microphone** permission is **not** requested in v0.1.
4. **100% Local Processing:** Captured pixels remain in local memory until you explicitly click **Copy** or **Save**.
