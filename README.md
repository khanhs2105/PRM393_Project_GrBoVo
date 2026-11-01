# Alo, Trả Tiền!: app chia tiền nhóm và nhắc nợ

<img src="assets/brand/chipin_logo.png" width="120" alt="Alo, Trả Tiền!">

Đồ án PRM393 (Flutter, Android). Ghi lại khoản chi của nhóm (đi ăn, phòng trọ, du lịch),
tự tính ai nợ ai, rút gọn thành ít lượt chuyển nhất, hiện QR VietQR để trả, và nhắc nợ.

## Tính năng

- **Đăng ký, đăng nhập, quên mật khẩu, đăng xuất** bằng Firebase Authentication (email + mật khẩu).
  Mở lại app không phải đăng nhập lại
- **Hồ sơ người dùng lưu trên Cloud Firestore** (`users/{uid}`): tên, email, gói, lần đăng nhập.
  Luật bảo mật ở [firestore.rules](firestore.rules): mỗi người chỉ đọc/ghi dữ liệu của mình
- **JWT**: màn "Xem JWT" hiện ID token của Firebase, giải mã header/payload, hạn dùng, và tự kiểm
  chữ ký RS256 bằng khóa công khai của Google cùng các claim `iss`, `aud`, `exp`, `iat`, `sub`
- **Sao lưu/khôi phục** toàn bộ dữ liệu nhóm lên Firestore để chuyển sang máy khác
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

Giao diện "Clean Minimal" kiểu shadcn/ui: font Be Vietnam Pro (SIL OFL 1.1) và icon Lucide (ISC),
cả hai đóng gói sẵn trong `assets/fonts/` nên không cần mạng. Mã icon ở `lib/widgets/app_icons.dart`.

Module phần cứng dùng: camera, cảm biến gia tốc, rung, thông báo, bộ nhớ (thư viện ảnh), clipboard, chia sẻ.

## Chạy lần đầu

Thư mục `android/` đã có trong repo, chỉ cần:

```bash
flutter pub get
```

**Firebase**: làm theo [docs/firebase-setup.md](docs/firebase-setup.md) để tạo project và đặt file
`android/app/google-services.json` (thiếu file này thì không build được).

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
  logic/      JWT (tách, kiểm chữ ký RS256), kiểm ô nhập đăng nhập, chia tiền, số dư, rút gọn nợ, thống kê, lọc, xuất CSV, VietQR, đọc QR EMVCo, gói troll (thuần Dart, có test)
  data/       SQLite, sao lưu/khôi phục lên Firestore: tạo bảng, nâng cấp bản 1 lên 2, repository, dữ liệu mẫu
  services/   App (khởi tạo dùng chung), AuthService (Firebase Auth + Firestore), kiểm JWT, NotificationService
  screens/    các màn hình
  widgets/    widget dùng chung, lắc để chọn người
assets/banks.json   danh sách ngân hàng (BIN theo NAPAS)
test/               unit test
```

## Thuật toán rút gọn nợ

1. Số dư mỗi người = tiền đã trả cho nhóm − phần phải chịu + tiền đã chuyển − tiền đã nhận.
2. Ghép người được nợ nhiều nhất với người nợ nhiều nhất, chuyển số nhỏ hơn, lặp lại.
   Mỗi vòng có ít nhất 1 người về 0 nên tối đa n − 1 lượt. Xem `lib/logic/debt_simplifier.dart`.
