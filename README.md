# Chipin: app chia tiền nhóm và nhắc nợ

<img src="assets/brand/chipin_logo.png" width="120" alt="Chipin">

Đồ án PRM393 (Flutter, Android). Ghi lại khoản chi của nhóm (đi ăn, phòng trọ, du lịch),
tự tính ai nợ ai, rút gọn thành ít lượt chuyển nhất, hiện QR VietQR để trả, và nhắc nợ.

## Tính năng

- Nhóm, thành viên, khoản chi với **4 cách chia** như Splitwise: chia đều, theo số tiền,
  theo phần (2:1:1), theo phần trăm. Phần lẻ chia theo phương pháp phần dư lớn nhất nên tổng luôn khớp
- Danh mục (tự đoán theo nội dung hoặc tự chọn), ghi chú, ảnh hóa đơn
- Màn chi tiết khoản chi: ai trả, mỗi người chịu bao nhiêu, xem ảnh hóa đơn phóng to
- Tìm kiếm khoản chi (không cần gõ dấu) và lọc theo người, theo danh mục
- Số dư từng người và gợi ý thanh toán đã rút gọn (tối đa n-1 lượt cho n người)
- Ghi nhận thanh toán tùy ý: trả một phần, trả tiền mặt, có ghi chú; hoàn tác khi bấm nhầm
- Thống kê: chi theo danh mục, theo người (đã trả / đã tiêu), theo tháng
- Lịch sử hoạt động của từng nhóm và của cả app
- Xuất file CSV (mở bằng Excel/Google Sheets) và chia sẻ bản tóm tắt nhóm qua Zalo/Messenger
- Thanh toán bằng QR VietQR có sẵn số tiền và nội dung, lưu QR vào máy, copy số TK
- **Quét QR ngân hàng bằng camera** để tự điền ngân hàng + số tài khoản (đọc chuẩn EMVCo)
- Nhắc nợ: chia sẻ tin nhắn sang Zalo/Messenger, hẹn giờ thông báo trên máy
- 3 gói "troll": Con Nợ, Chủ Nợ, Đòi Nợ Thuê (giả lập, không thanh toán thật)
- Lắc điện thoại để random người bao bữa (gia tốc kế)
- Lưu offline bằng SQLite, có dữ liệu mẫu để demo

Module phần cứng dùng: camera, cảm biến gia tốc, rung, thông báo, bộ nhớ (thư viện ảnh), clipboard, chia sẻ.

## Chạy lần đầu

Thư mục `android/` đã có trong repo, chỉ cần:

```bash
flutter pub get
```

Cấu hình Android (quyền, desugaring) đã có sẵn trong repo, giải thích ở
[docs/android-config.md](docs/android-config.md). Sau đó:

```bash
flutter test          # unit test cho logic và database
flutter run           # cắm điện thoại Android, bật USB debugging
flutter build apk --release   # file ở build/app/outputs/flutter-apk/app-release.apk
```

## Cấu trúc

```
lib/
  models/     Group, Member, Expense, Settlement/Transfer, Activity, Bank
  logic/      chia tiền, số dư, rút gọn nợ, thống kê, lọc, xuất CSV, VietQR, đọc QR EMVCo, gói troll (thuần Dart, có test)
  data/       SQLite: tạo bảng, nâng cấp bản 1 lên 2, repository, dữ liệu mẫu
  services/   App (khởi tạo dùng chung), NotificationService
  screens/    các màn hình
  widgets/    widget dùng chung, lắc để chọn người
assets/banks.json   danh sách ngân hàng (BIN theo NAPAS)
test/               unit test
```

## Thuật toán rút gọn nợ

1. Số dư mỗi người = tiền đã trả cho nhóm − phần phải chịu + tiền đã chuyển − tiền đã nhận.
2. Ghép người được nợ nhiều nhất với người nợ nhiều nhất, chuyển số nhỏ hơn, lặp lại.
   Mỗi vòng có ít nhất 1 người về 0 nên tối đa n − 1 lượt. Xem `lib/logic/debt_simplifier.dart`.
