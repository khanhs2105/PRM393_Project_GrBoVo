# GrBoVo Split: app chia tiền nhóm và nhắc nợ

Đồ án PRM393 (Flutter, Android). Ghi lại khoản chi của nhóm (đi ăn, phòng trọ, du lịch),
tự tính ai nợ ai, rút gọn thành ít lượt chuyển nhất, hiện QR VietQR để trả, và nhắc nợ.

## Tính năng

- Nhóm, thành viên, khoản chi (chia đều hoặc theo số tiền), ảnh hóa đơn
- Số dư từng người và gợi ý thanh toán đã rút gọn (tối đa n-1 lượt cho n người)
- Thanh toán bằng QR VietQR có sẵn số tiền và nội dung, lưu QR vào máy, copy số TK
- **Quét QR ngân hàng bằng camera** để tự điền ngân hàng + số tài khoản (đọc chuẩn EMVCo)
- Nhắc nợ: chia sẻ tin nhắn sang Zalo/Messenger, hẹn giờ thông báo trên máy
- 3 gói "troll": Con Nợ, Chủ Nợ, Đòi Nợ Thuê (giả lập, không thanh toán thật)
- Lắc điện thoại để random người bao bữa (gia tốc kế)
- Lưu offline bằng SQLite, có dữ liệu mẫu để demo

Module phần cứng dùng: camera, cảm biến gia tốc, rung, thông báo, bộ nhớ (thư viện ảnh), clipboard, chia sẻ.

## Chạy lần đầu

```bash
# trong thư mục repo
flutter create --project-name chia_tien --org com.grbovo --platforms android .
flutter pub get
```

`flutter create` chỉ tạo thêm thư mục `android/` và các file còn thiếu, không ghi đè code trong `lib/`.

Sau đó làm theo [docs/android-config.md](docs/android-config.md) (thêm quyền vào AndroidManifest
và bật desugaring), rồi:

```bash
flutter test          # 37 unit test
flutter run           # cắm điện thoại Android, bật USB debugging
flutter build apk --release   # file ở build/app/outputs/flutter-apk/app-release.apk
```

## Cấu trúc

```
lib/
  models/     Group, Member, Expense, Settlement/Transfer, Bank
  logic/      chia tiền, số dư, rút gọn nợ, VietQR, đọc QR EMVCo, gói troll (thuần Dart, có test)
  data/       SQLite: tạo bảng, repository, dữ liệu mẫu
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
