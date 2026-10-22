# MacCapture — UI/UX Specification

## 1. Floating Toolbar

- **Dimensions:**
  - Compact mode (default): `360 × 44 pt`
  - Comfortable mode: `388 × 46 pt`
  - Collapsed edge handle: `24 × 44 pt`
- **Visual Style:** Borderless `NSPanel` with SwiftUI `.ultraThinMaterial`, `11 pt` continuous corner radius, subtle border (`primary.opacity(0.18)`), and soft drop shadow.
- **Controls (Left to Right):**
  1. **Drag Handle (`circle.grid.2x3.fill`)**: Drag to reposition; double-click to reset to top-center of active screen.
  2. **Region (`viewfinder.rectangular`)**: Starts interactive region selection (`⌃⌘1`).
  3. **Window (`macwindow`)**: Starts interactive window highlight & selection (`⌃⌘2`).
  4. **Full (`rectangle.inset.filled`)**: Captures active display immediately (`⌃⌘3`), or opens a display picker menu when multiple monitors are connected.
  5. **Delay Menu (`timer`)**: Selects `0s`, `3s`, `5s`, or `10s` countdown before capture.
  6. **More Menu (`ellipsis.circle`)**: Accesses `Open Editor…`, `Reset Toolbar Position`, `Preferences…`, `Hide Toolbar`, and `Quit MacCapture` (plus disabled roadmap indicators for v0.2/v0.3).
  7. **Hide Button (`xmark`)**: Hides the floating toolbar panel while keeping MacCapture running in the menu bar.

## 2. Region & Window Overlays

- **Region Overlay (`RegionOverlayController`)**:
  - Covers each physical `NSScreen` with a `35%` dimmed backdrop and crosshair cursor.
  - Supports dragging in any direction, clamping to display bounds, and displaying a live `W × H px` badge in physical pixels.
  - Pressing `Esc` or right-clicking cancels immediately and restores cursor and toolbar.
- **Window Overlay (`WindowSelectionController`)**:
  - Highlights the topmost application window under the cursor with a system blue border, translucent fill, and a `<App Name> — <Window Title>` pill.

## 3. Annotation Editor

- **Top Toolbar:**
  - `Undo` (`⌘Z`), `Redo` (`⇧⌘Z`)
  - Tools: `Select`, `Arrow`, `Rect`, `Ellipse`, `Text`, `Crop` (and disabled `Blur*` roadmap indicator)
  - `Delete` button (`Delete` / `Backspace`) when an annotation is selected
  - Export actions: `Copy` (`⌘C`), `Save` (`⌘S`), `Save As…` (`⇧⌘S`)
- **Bottom Status Bar:**
  - 8 preset stroke color swatches
  - Stroke width picker (`2 pt`, `4 pt`, `6 pt`, `8 pt`)
  - Font size picker (`16 pt`, `24 pt`, `32 pt`, `44 pt`)
  - Zoom menu (`50%`, `100%`, `200%`) + trackpad pinch-to-zoom
  - Output pixel dimensions badge (`Size: W×H px`)
