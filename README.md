# MultiAI — macOS Multi-Account Desktop App Manager

**MultiAI** là ứng dụng native macOS (SwiftUI) giúp bạn tạo, quản lý và chạy **nhiều tài khoản độc lập song song** cho các ứng dụng AI trên máy (Claude, Antigravity, Gemini/ChatGPT qua Chrome/Edge App Mode, Cursor, v.v.).

Mỗi tài khoản được tạo sẽ trở thành **một app `.app` độc lập** nằm trong `~/Applications/MultiAI Apps/` với icon có badge màu phân biệt và thư mục dữ liệu riêng (`~/Library/Application Support/MultiAI/Profiles/<UUID>`), có thể mở từ Spotlight, Dock, Dashboard hoặc Menu Bar.

---

## Tính năng chính

- **Tự động phát hiện ứng dụng trên máy** (`/Applications` & `~/Applications`) và chọn cơ chế tách biệt phù hợp:
  - **IDE Isolated** (`Antigravity.app`, `Cursor.app`, `VS Code`): truyền `--user-data-dir` riêng (và tuỳ chọn `--extensions-dir`).
  - **Electron Isolated** (`Claude.app`, Electron apps): truyền `--user-data-dir` riêng để tách hoàn toàn phiên đăng nhập, cookies, cache.
  - **Browser App Mode** (`Google Chrome.app`, `Microsoft Edge.app`, `Brave.app`, `Arc.app`): mở các Web AI (`gemini.google.com`, `chatgpt.com`, `claude.ai`, ...) dưới dạng cửa sổ app độc lập với profile riêng.
  - **Native macOS** (`ChatGPT.app` hoặc app native khác): mở nhiều instance qua `open -n` kèm biến môi trường `XDG_*` (có tuỳ chọn tách `HOME`). *Lưu ý: các app native dùng macOS Keychain như `ChatGPT.app` vẫn có thể dùng chung token Keychain; MultiAI hỗ trợ chuyển nhanh 1-click sang `Browser App Mode` cho `https://chatgpt.com` để tách tài khoản hoàn toàn.*
- **Tạo `.app` độc lập có icon Badge màu sắc**: render `.icns` nhiều độ phân giải ngay trong Swift (không phụ thuộc công cụ ngoài), hỗ trợ ghim lên Dock hoặc mở qua Spotlight.
- **Theo dõi trạng thái live & Menu Bar launcher**: xem tài khoản nào đang chạy (PID), Launch / Focus / Stop nhanh từ Menu Bar.
- **Chia cửa sổ song song (Window Tiling)**: sắp xếp các app đang chạy theo bố cục **Side by Side**, **Grid**, hoặc **Stacked** bằng macOS Accessibility API.

---

## Build & Cài đặt

### Chạy test
```bash
swift test
```

### Build và cài vào `~/Applications/MultiAI.app`
```bash
./scripts/build-app.sh --install
```

Sau khi cài xong, bạn có thể mở app bằng lệnh:
```bash
open ~/Applications/MultiAI.app
```
hoặc tìm **MultiAI** trong Spotlight (`Cmd + Space`).

---

## Quyền Accessibility (cho tính năng Chia cửa sổ)

Lần đầu sử dụng tính năng **Chia cửa sổ (Side by Side / Grid / Stacked)**, macOS sẽ hỏi cấp quyền **Accessibility**:
1. Mở **System Settings → Privacy & Security → Accessibility**.
2. Bật quyền cho **MultiAI** (hoặc bấm nút *"Mở Cài đặt Accessibility"* ngay trên banner thông báo trong app).

---

## Cấu trúc thư mục

- `Sources/MultiAICore/`: Models và Services (Discovery, IconBadgeRenderer, AppBundleGenerator, ProcessTracker, WindowTiler, InstanceStore).
- `Sources/MultiAI/`: Giao diện SwiftUI (Dashboard, Card, Add/Edit Sheet, Menu Bar).
- `Tests/MultiAITests/`: Unit tests cho toàn bộ core logic.
- `scripts/build-app.sh`: Đóng gói `MultiAI.app` với icon và chữ ký ad-hoc.
