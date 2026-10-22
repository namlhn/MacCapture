# MacCapture — Ứng dụng Chụp Màn Hình & Chú Thích Chuyên Nghiệp cho macOS

**MacCapture** là ứng dụng chụp màn hình (Screen Capture), chụp cuộn trang (Scrolling Capture) và chỉnh sửa/chú thích vector (Vector Annotation) siêu nhẹ, thuần native dành cho **macOS 14.0+**, được xây dựng bằng **Swift**, **AppKit**, **SwiftUI** và **ScreenCaptureKit**.

Ứng dụng hoạt động hoàn toàn **100% Offline & Local** trên máy Mac của bạn — không cần tài khoản đám mây, không thu thập dữ liệu (zero telemetry) và khởi động tức thì với thanh công cụ nổi (**Floating Toolbar**) gọn đẹp cùng biểu tượng trên thanh **Menu Bar**.

---

## ✨ Tính năng nổi bật

### 1. Thanh công cụ nổi (Floating Toolbar) & Menu Bar
- **Giao diện kính mờ hiện đại (`ultraThinMaterial`)**:
  - Gắn **Icon Logo MacCapture** chuẩn squircle macOS ngay đầu thanh công cụ (vừa là điểm nhận diện thương hiệu, vừa là tay nắm kéo di chuyển hoặc nhấp đúp để đưa về vị trí mặc định).
  - Tự động lưu vị trí tương đối theo từng màn hình và tự động căn chỉnh lại khi cắm/rút màn hình rời.
  - Hỗ trợ thu gọn sát mép màn hình (**Auto-collapse to edge**) chỉ còn biểu tượng mini để tiết kiệm diện tích.
  - Có thể ẩn thanh công cụ nổi (`×`) bất kỳ lúc nào và điều khiển hoàn toàn từ biểu tượng trên **Menu Bar** hoặc bằng phím tắt toàn cục.

### 2. Bốn chế độ chụp màn hình chuyên dụng (`ScreenCaptureKit`)
| Chế độ | Phím tắt mặc định | Mô tả chi tiết |
| :--- | :---: | :--- |
| **Region** (Chụp vùng chọn) | `⌃⌘1` | Kéo chuột chọn vùng bất kỳ trên màn hình với tâm ngắm crosshair, hiển thị kích thước pixel thực (`W × H px`) theo thời gian thực, hỗ trợ kéo 4 hướng. |
| **Window** (Chụp cửa sổ) | `⌃⌘2` | Di chuột qua cửa sổ bất kỳ để làm nổi bật khung xanh và tên ứng dụng; chụp chính xác cửa sổ độc lập (`desktopIndependentWindow`) kể cả khi bị cửa sổ khác đè lên. |
| **Full** (Toàn màn hình) | `⌃⌘3` | Chụp ngay toàn bộ màn hình ở độ phân giải Retina gốc (hỗ trợ menu chọn màn hình nếu đang dùng nhiều màn hình). |
| **Scroll** (Chụp cuộn trang) | `⌃⌘4` | **Chọn trực tiếp Cửa sổ / Tab trình duyệt** (không cần vẽ khung thủ công), tự động focus vào cửa sổ và **tự động cuộn từ trên xuống cuối trang** (hoặc đến khi bấm **Dừng / Space**), tự lọc bỏ Sticky Header / Tab Bar và ghép thành một bức ảnh dài liền mạch tốc độ cao. |

- **Hẹn giờ chụp (Capture Delay)**: Hỗ trợ hẹn giờ `0s`, `3s`, `5s`, `10s` ngay trên thanh công cụ (tự động đổi sang badge màu cam khi đang bật hẹn giờ).

### 3. Trình chỉnh sửa & Chú thích ảnh (Non-Destructive Vector Annotation Editor)
Ngay sau khi chụp, ảnh được mở trong cửa sổ **Annotation Editor** với giao diện chuyên nghiệp, làm nổi bật màu công cụ đang chọn và hỗ trợ đầy đủ **Undo / Redo (`⌘Z` / `⇧⌘Z`)** lên tới 50 bước mà không làm tốn bộ nhớ:

- **Select (`V`)**: Chọn, di chuyển, thay đổi kích thước (8 điểm neo quanh vật thể) hoặc xóa (`Delete`) bất kỳ chú thích nào đã vẽ.
- **Arrow (`A`)**: Vẽ mũi tên chỉ dẫn sắc nét.
- **Line (`L`)**: Vẽ đoạn thẳng trực tiếp từ điểm đầu đến điểm cuối, hỗ trợ kéo chỉnh lại 2 đầu mút dễ dàng.
- **Rect (`R`)**: Vẽ khung chữ nhật viền nổi hoặc bật tùy chọn **Fill** để tô nền bán trong suốt.
- **Ellipse (`O`)**: Vẽ hình tròn / elip khoanh vùng nội dung quan trọng.
- **Text (`T`)**: Chèn chữ chú thích với nền pill bán trong suốt giúp dễ đọc trên mọi nền ảnh, tùy chỉnh cỡ chữ (`16pt`, `24pt`, `32pt`, `44pt`) và màu sắc.
- **Blur (`B`) — Làm mờ thông tin nhạy cảm**:
  - Kéo chọn vùng cần che (mật khẩu, số tài khoản, email, dữ liệu cá nhân...) để áp dụng hiệu ứng **Mosaic Pixelation (làm vỡ hạt ô vuông)** trực tiếp lên vùng ảnh.
  - Hỗ trợ chỉnh 4 mức độ nhòe (ô vuông lớn/nhỏ) ngay tại thanh **Blur** phía dưới; khi xuất ảnh PNG hoặc Copy, vùng làm mờ được nướng cứng (irreversible) đảm bảo an toàn tuyệt đối.
- **Crop (`C`) — Cắt ảnh 2 bước trực quan**:
  - Kéo chọn vùng muốn giữ lại (phần ngoài tự động tối đi kèm lưới bố cục 1/3 và 8 chốt kéo góc/cạnh).
  - Tinh chỉnh thoải mái rồi bấm nút xanh **`Hoàn thành Crop`** (hoặc nhấn `Enter`) ngay cạnh vùng cắt để cắt gọn khung ảnh, hoặc bấm **`Khôi phục ảnh gốc`** / `⌘Z` bất kỳ lúc nào.

### 4. Xuất ảnh chất lượng gốc (Copy & Save PNG)
- **Copy (`⌘C`)**: Kết xuất (flatten) ảnh gốc + toàn bộ lớp vector/blur/crop ở đúng độ phân giải pixel vật lý (Retina 2x/3x) và chép thẳng vào Clipboard (`NSPasteboard`).
- **Save PNG (`⌘S` / `⇧⌘S`)**: Lưu file PNG sắc nét, tự động loại bỏ siêu dữ liệu cá nhân (GPS/EXIF) với tên file mặc định theo thời gian (`MacCapture YYYY-MM-DD at HH.mm.ss.png`).

---

## ⌨️ Bảng phím tắt

### Phím tắt toàn cục (Global Shortcuts)
- `⌃⌘1`: Chụp vùng chọn (**Capture Region**)
- `⌃⌘2`: Chụp cửa sổ (**Capture Window**)
- `⌃⌘3`: Chụp toàn màn hình (**Capture Fullscreen**)
- `⌃⌘4`: Chụp cuộn cửa sổ / tab trình duyệt (**Capture Scrolling**)
- `⌃⌘T`: Ẩn / Hiện thanh công cụ nổi (**Show/Hide Floating Toolbar**)

### Phím tắt trong khi Chụp & Chỉnh sửa
- `Space` / `Return (Enter)`:
  - Trong chế độ **Scroll**: Dừng cuộn & mở ảnh đã ghép trong Editor.
  - Trong chế độ **Crop**: Xác nhận hoàn thành cắt ảnh.
- `Esc`: Hủy thao tác chụp hoặc hủy vùng đang chọn.
- `⌘Z` / `⇧⌘Z`: Hoàn tác (Undo) / Làm lại (Redo).
- `Delete` / `Backspace`: Xóa đối tượng chú thích đang chọn.
- `⌘C`: Copy ảnh đã chú thích vào Clipboard.
- `⌘S` / `⇧⌘S`: Lưu nhanh file PNG / Lưu thành (Save As…).

---

## 🏗️ Kiến trúc & Cấu trúc thư mục

```text
MacCapture/
├── README.md
├── LICENSE
├── plan.md
├── CONTRIBUTING.md
├── docs/
│   ├── architecture.md               # Kiến trúc phân tầng & quyết định kỹ thuật (ADR)
│   ├── ui-spec.md                    # Đặc tả giao diện Floating Toolbar & Editor
│   ├── permission-guide.md           # Hướng dẫn cấp quyền Screen Recording & Accessibility
│   └── test-matrix.md                # Ma trận kiểm thử tự động & thủ công
├── MacCapture.xcodeproj/             # Project Xcode thuần native (không phụ thuộc thư viện ngoài)
├── build/
│   └── MacCapture.app                # Bản đóng gói ứng dụng Release (.app) sẵn sàng chạy ngay
├── MacCapture/
│   ├── App/
│   │   ├── MacCaptureApp.swift       # Entry point của ứng dụng
│   │   ├── AppDelegate.swift         # Quản lý vòng đời ứng dụng macOS
│   │   ├── AppCoordinator.swift      # Điều phối trung tâm giữa Toolbar, Capture, MenuBar và Editor
│   │   └── MenuBarController.swift   # Biểu tượng & menu điều khiển trên thanh Menu Bar
│   ├── Core/
│   │   ├── CaptureTypes.swift        # Các kiểu dữ liệu cốt lõi (CaptureMode, CaptureDisplay, CaptureWindow...)
│   │   ├── PermissionManager.swift   # Kiểm tra & yêu cầu quyền Screen Recording
│   │   └── HotkeyManager.swift       # Đăng ký phím tắt toàn cục qua Carbon RegisterEventHotKey
│   ├── Features/
│   │   ├── Toolbar/
│   │   │   ├── FloatingToolbarPanel.swift    # NSPanel nổi không chiếm focus (nonactivatingPanel)
│   │   │   ├── ToolbarView.swift             # Giao diện Floating Toolbar kèm AppLogoBadgeView
│   │   │   ├── ToolbarViewModel.swift        # Trạng thái hiển thị & hành động trên Toolbar
│   │   │   └── ToolbarPositionStore.swift    # Lưu & phục hồi vị trí Toolbar trên đa màn hình
│   │   ├── Capture/
│   │   │   ├── CaptureCoordinator.swift          # Máy trạng thái (State Machine) điều phối quy trình chụp
│   │   │   ├── ScreenCaptureEngine.swift         # Chụp màn hình & cửa sổ qua ScreenCaptureKit (có cache filter)
│   │   │   ├── RegionOverlayController.swift     # Lớp phủ chọn vùng chụp (Crosshair & kích thước pixel)
│   │   │   ├── WindowSelectionController.swift   # Lớp phủ chọn Cửa sổ / Tab trình duyệt
│   │   │   ├── ScrollingCaptureController.swift  # Tự động cuộn cửa sổ & thuật toán ghép ảnh dọc tốc độ cao
│   │   │   └── CoordinateConverter.swift         # Chuyển đổi tọa độ AppKit <-> CoreGraphics <-> Pixel Retina
│   │   ├── Editor/
│   │   │   ├── AnnotationModels.swift        # Mô hình dữ liệu Vector Annotation (Arrow, Line, Rect, Ellipse, Text, Blur)
│   │   │   ├── AnnotationCommandStack.swift  # Ngăn xếp Undo/Redo dựa trên lệnh (Command Pattern)
│   │   │   ├── AnnotationCanvas.swift        # Canvas vẽ & tương tác trực tiếp + bộ lọc Pixelation Blur
│   │   │   ├── EditorView.swift              # Giao diện cửa sổ chỉnh sửa ảnh & thanh công cụ
│   │   │   └── EditorWindowController.swift  # Quản lý cửa sổ Editor & hộp thoại lưu file
│   │   ├── Export/
│   │   │   ├── ImageRenderer.swift           # Kết xuất ảnh gốc + chú thích vector + blur + crop ra CGImage
│   │   │   ├── PNGExporter.swift             # Mã hóa file PNG sạch metadata qua ImageIO
│   │   │   └── ClipboardService.swift        # Sao chép ảnh vào NSPasteboard
│   │   └── Settings/
│   │       ├── PreferencesStore.swift        # Lưu trữ cài đặt người dùng (UserDefaults & Launch at Login)
│   │       └── PreferencesView.swift         # Cửa sổ cài đặt (General, Shortcuts, Privacy)
│   └── Resources/
│       ├── Assets.xcassets/                  # Bộ AppIcon.appiconset đầy đủ 10 kích thước chuẩn macOS
│       ├── Info.plist                        # Cấu hình bundle & mô tả quyền riêng tư
│       └── MacCapture.entitlements           # Quyền thực thi ứng dụng
├── MacCaptureTests/                          # Bộ 21 Unit Tests kiểm thử toàn diện
└── MacCaptureUITests/                        # Bộ UI Smoke Tests
```

---

## 🚀 Hướng dẫn Chạy & Biên dịch

### Cách 1: Chạy trực tiếp bản `.app` đã đóng gói sẵn (Nhanh nhất)
Bản biên dịch tối ưu hóa (`Release`) đã được đóng gói sẵn tại `build/MacCapture.app`. Mở **Terminal** và chạy:

```bash
open /Users/win/Documents/antigravity/calm-einstein/build/MacCapture.app
```

Bạn cũng có thể kéo file `build/MacCapture.app` vào thư mục `/Applications` để sử dụng lâu dài như mọi ứng dụng macOS khác.

### Cách 2: Mở và chạy trong Xcode
```bash
open /Users/win/Documents/antigravity/calm-einstein/MacCapture.xcodeproj
```
Chọn scheme **`MacCapture`** → Nhấn **`⌘R` (Run)**.

### Cách 3: Biên dịch và chạy Unit Tests bằng dòng lệnh
```bash
# Biên dịch bản Release
xcodebuild -project MacCapture.xcodeproj -scheme MacCapture -configuration Release build

# Chạy toàn bộ 21 Unit Tests
xcodebuild test -project MacCapture.xcodeproj -scheme MacCapture -destination 'platform=macOS' -only-testing:MacCaptureTests
```

---

## 🔐 Quyền Hệ thống (macOS Permissions)

1. **Screen Recording (Ghi màn hình — Bắt buộc khi chụp)**:
   - Vào `System Settings → Privacy & Security → Screen & System Audio Recording` và bật công tắc cho **MacCapture**.
2. **Accessibility (Trợ năng — Dùng cho tính năng Tự động cuộn `Scroll`)**:
   - Để ứng dụng có thể tự động gửi sự kiện lăn chuột sang cửa sổ trình duyệt khi chụp cuộn (`Scroll`), vào `System Settings → Privacy & Security → Accessibility` và bật công tắc cho **MacCapture**.
   - *(Mẹo: Nếu biên dịch lại bản mới, hãy tắt rồi bật lại công tắc `MacCapture` trong mục Accessibility để macOS cập nhật chữ ký mới của ứng dụng).*

---

## 📄 Giấy phép (License)

Phát hành theo giấy phép [MIT License](LICENSE).
