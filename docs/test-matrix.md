# MacCapture — Test Matrix & Acceptance Criteria

## 1. Internal Acceptance Criteria (v0.1 Targets)

| ID | Metric | Target | Verification Method |
|---|---|---|---|
| **P-01** | Hotkey press to overlay ready | p95 < 400 ms (warm) | Manual / instrumented timing |
| **P-02** | Capture completion to Editor visible | p95 < 1.5 s (1920×1080) | Manual / instrumented timing |
| **P-03** | Compact toolbar dimensions | 40–46 pt height, 320–390 pt width | Enforced in `ToolbarScale` (`360×44` & `388×46`) |
| **P-04** | Copy / Save PNG compatibility | 100% valid PNG output | Automated in `ExportTests` + Preview verification |
| **P-05** | Multi-display & Retina coordinate accuracy | 0 px offset across 1x/2x & negative origins | Automated in `CoordinateConverterTests` |
| **P-06** | Undo/Redo fidelity | 100% state recovery across all commands | Automated in `AnnotationCommandTests` |
| **P-07** | Zero network traffic | 0 network requests in capture/editor | Code audit (no `URLSession`/network APIs linked) |

## 2. Automated Unit Test Coverage (`MacCaptureTests`)

- `CoordinateConverterTests`:
  - 4-direction drag normalization (`normalizedDragRect`)
  - Clamping across negative display origins (`clampRect`)
  - AppKit global bottom-left points → display-local top-left backing pixels at 1x and 2x Retina
  - CoreGraphics ↔ AppKit global window rect round-trip
  - Minimum 4×4 pixel selection validation
  - `ToolbarPositionStore` persistence and disconnected monitor fallback
- `CaptureCoordinatorTests`:
  - Permission denied → `.permissionHelp` flow without crash
  - Fullscreen capture lifecycle including hiding and restoring app chrome
  - Region selection cancellation (`Escape`) cleanup and restoration
  - Window capture error cleanup and `.error` state transition
  - `HotkeyManager` duplicate and macOS system shortcut conflict detection
- `AnnotationCommandTests`:
  - Add, remove, move, resize, style update, text edit, and crop Undo/Redo command stack verification
  - `zIndex` ordering and geometry hit-testing
- `ExportTests`:
  - High-resolution flattening of all annotation kinds (`arrow`, `rectangle`, `ellipse`, `text`)
  - Crop rectangle application and pixel dimension verification
  - `PNGExporter` file write/decode round-trip and `ClipboardService` pasteboard verification
  - Invalid destination write error handling

## 3. Manual QA Matrix

| Scenario | Environment | Expected Outcome |
|---|---|---|
| Permission denied | Fresh install / toggled off | Shows guidance dialog + System Settings button, no crash |
| Retina + external 1x monitor | Dual display mixed scaling | Region capture matches exact visual bounds and pixel dimensions |
| External monitor unplugged | Toolbar positioned on external display | Toolbar automatically clamps into primary display's `visibleFrame` |
| Overlapping windows | Window mode (`⌃⌘2`) | Captures only the selected target window via `SCContentFilter` |
| Press `Esc` during selection | Region or Window mode | Overlay closes immediately, cursor and toolbar restore cleanly |
| Paste into Preview / Notes / Chat | After pressing `⌘C` in Editor | Flattened PNG pastes at full resolution |
| Unwritable destination | Read-only folder in Save panel | Displays non-blocking error banner; document remains open in Editor |
