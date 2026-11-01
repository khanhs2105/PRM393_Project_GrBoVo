# Cài đặt Firebase cho app Alo, Trả Tiền! (đăng nhập, đăng ký, lưu dữ liệu, JWT)

Code đã viết xong. Bạn chỉ cần tạo project Firebase và tải **1 file** `google-services.json`
về đặt vào repo. Mất khoảng 10 phút.

## Bước 1. Tạo project Firebase

1. Mở <https://console.firebase.google.com> và đăng nhập bằng tài khoản Google.
2. Bấm **Create a project** (hoặc **Add project**).
3. Tên project: `Chipin` (tên nào cũng được). Bấm **Continue**.
4. Màn Google Analytics: **tắt** cho nhanh, bấm **Create project**, đợi xong bấm **Continue**.

## Bước 2. Bật đăng nhập bằng Email/Mật khẩu

1. Menu trái: **Build > Authentication** (hoặc **Security > Authentication**), bấm **Get started**.
2. Tab **Sign-in method**, chọn **Email/Password**.
3. Bật công tắc **Email/Password** đầu tiên (không cần bật "Email link"), bấm **Save**.

> Quên bước này thì app báo: *"Chưa bật đăng nhập Email/Password trong Firebase Console."*

## Bước 3. Tạo Cloud Firestore (database lưu dữ liệu người dùng)

1. Menu trái: **Build > Firestore Database**, bấm **Create database**.
2. Edition chọn **Standard** nếu được hỏi. Database ID để mặc định `(default)`.
3. Location: chọn **asia-southeast1 (Singapore)** cho nhanh ở Việt Nam. (Không đổi được sau này.)
4. Chọn **Start in production mode**, bấm **Create**.
5. Khi database đã tạo xong, mở tab **Rules**, xóa hết nội dung cũ, dán toàn bộ nội dung file
   [`firestore.rules`](../firestore.rules) ở thư mục gốc repo vào, bấm **Publish**.

> Không dán rules thì đăng nhập vẫn được nhưng hồ sơ và sao lưu báo lỗi `PERMISSION_DENIED`.

## Bước 4. Thêm app Android và tải `google-services.json`

1. Bấm bánh răng cạnh **Project Overview** > **Project settings**.
2. Kéo xuống mục **Your apps**, bấm biểu tượng **Android**.
3. Điền:
   - **Android package name**: `com.grbovo.chia_tien` (phải gõ đúng y hệt)
   - **App nickname**: `Chipin`
   - **Debug signing certificate SHA-1**: bỏ trống (chỉ cần khi dùng đăng nhập Google)
4. Bấm **Register app**, rồi bấm **Download google-services.json**.
5. Chép file vừa tải vào đúng chỗ này (tên file giữ nguyên):

   ```
   D:\dev\PRM393_Project_GrBoVo\android\app\google-services.json
   ```

   Tức là nằm cạnh file `android\app\build.gradle.kts`.
6. Các bước tiếp theo trên web (sửa Gradle, thêm SDK) **bỏ qua**, bấm **Next** đến hết
   rồi **Continue to console**. Phần Gradle đã sửa sẵn trong repo.

## Bước 5. Chạy app

Mở terminal trong VS Code ở thư mục project:

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run
```

Lần build đầu sau khi thêm Firebase hơi lâu (Gradle tải Firebase SDK), cứ đợi.

## Bước 6. Kiểm tra đã chạy đúng

1. App mở lên màn **Đăng nhập**. Bấm **Đăng ký**, nhập tên, email, mật khẩu (ít nhất 6 ký tự,
   có chữ và số). Đăng ký xong app vào thẳng màn chính, lời chào có tên bạn.
2. Trên Firebase Console:
   - **Authentication > Users**: thấy email vừa đăng ký.
   - **Firestore Database > Data**: thấy collection `users`, trong đó có document mang uid của bạn
     với `displayName`, `email`, `plan`, `createdAt`, `lastLoginAt`, `loginCount`.
3. Trong app bấm biểu tượng **tài khoản** (hình người, góc trên phải):
   - **Xem JWT (ID token)**: thấy token 3 phần tô màu, header, payload, hạn dùng và dòng
     **"Token hợp lệ · Chữ ký RS256 hợp lệ"**.
   - **Sao lưu lên Firebase**: trên Console xuất hiện `users/{uid}/backups/latest`.
   - **Khôi phục từ Firebase**: cài app trên máy khác, đăng nhập cùng tài khoản, bấm khôi phục là
     có lại toàn bộ nhóm.
   - Đổi gói "troll" ở màn Gói: trường `plan` trên Firestore đổi theo. Đăng nhập lại trên máy
     khác thì gói được lấy về.
4. Đăng xuất, đóng app, mở lại: quay về màn đăng nhập. Đăng nhập lại: `loginCount` tăng lên 1.

## Có nên commit `google-services.json` không?

Nên, để cả nhóm clone về là build được. File này chỉ chứa thông tin nhận diện project, không phải
mật khẩu. Dữ liệu được bảo vệ bởi `firestore.rules` (mỗi người chỉ đọc/ghi được dữ liệu của chính
mình).

## Gặp lỗi thì xem ở đây

| Lỗi | Cách sửa |
|---|---|
| `File google-services.json is missing` khi build | File chưa nằm đúng `android/app/google-services.json`, hoặc bị đổi tên thành `google-services (1).json`. |
| `No matching client found for package name 'com.grbovo.chia_tien'` | Lúc đăng ký app Android gõ sai package name. Thêm lại app Android đúng tên rồi tải file mới. |
| Lỗi Gradle nhắc tới `com.google.gms.google-services` / plugin không tương thích | Mở `android/settings.gradle.kts`, đổi `version "4.4.4"` của plugin đó sang bản mới nhất ghi trên trang tải file của Firebase. |
| `minSdkVersion ... cannot be smaller than 24` | Đã đặt sẵn `minSdk = maxOf(flutter.minSdkVersion, 24)`. Nếu vẫn lỗi, sửa thành `minSdk = 24`. |
| App hiện "Chưa kết nối được Firebase" | Firebase không khởi tạo được, thường do thiếu/sai file json. Làm lại bước 4 rồi `flutter clean`. |
| Đăng nhập báo "Không có mạng" trên máy ảo | Máy ảo mất mạng: tắt mở lại emulator hoặc chạy bằng điện thoại thật. |
| Hồ sơ/sao lưu báo `PERMISSION_DENIED` | Chưa dán và **Publish** rules ở bước 3. |
| `The database (default) does not exist` | Chưa tạo Firestore ở bước 3. |

## Giải thích cho báo cáo: JWT trong app

- Khi đăng nhập/đăng ký, **Firebase Authentication** cấp cho app một **ID token**. Token này là
  một **JWT** (JSON Web Token) dạng `header.payload.signature`, mã hóa base64url.
  - `header`: `{"alg": "RS256", "kid": "...", "typ": "JWT"}`
  - `payload`: `sub`/`user_id` (uid), `email`, `name`, `iat` (lúc cấp), `exp` (hết hạn sau 1 giờ),
    `aud` (project id), `iss` (`https://securetoken.google.com/<project id>`), `auth_time`.
  - `signature`: chữ ký RSA SHA-256 bằng khóa bí mật của Google.
- Firebase SDK tự gửi token này kèm mọi yêu cầu tới Firestore. Server kiểm token rồi mới điền
  `request.auth.uid`, và `firestore.rules` dùng uid đó để chỉ cho đọc/ghi dữ liệu của chính chủ.
  Token hết hạn thì SDK tự xin token mới bằng refresh token.
- Màn **Xem JWT** trong app tự làm lại việc kiểm token đó ngay trên máy để minh họa
  (code ở `lib/logic/jwt.dart`, `lib/services/jwt_verifier.dart`):
  1. Tách 3 phần, giải mã header và payload.
  2. Tải khóa công khai của Google (JWKS) tại
     `https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com`,
     chọn khóa theo `kid`.
  3. Kiểm chữ ký RS256: tính `s^e mod n`, so với SHA-256 của `header.payload` theo chuẩn PKCS#1 v1.5.
  4. Kiểm claim: `alg = RS256`, `exp` chưa qua, `iat` không ở tương lai, `aud` = project id,
     `iss` đúng, `sub` không rỗng.
- Unit test `test/jwt_test.dart` dùng một token ký bằng khóa RSA tạo riêng để chứng minh: token
  đúng thì qua, sửa 1 chữ trong payload (đổi uid) thì chữ ký sai, hết hạn hoặc sai project thì bị báo.

## Dữ liệu trên Firestore

```
users/{uid}
  uid, displayName, email, plan, provider,
  createdAt, lastLoginAt, loginCount, lastBackupAt
users/{uid}/backups/latest
  schemaVersion, createdAt, platform,
  counts:  { groups, members, expenses, ... }
  tables:  { groups: [...], members: [...], expenses: [...],
             expense_shares: [...], settlements: [...], activities: [...] }
```

Dữ liệu nhóm vẫn lưu chính trên máy bằng SQLite (dùng được khi không có mạng). Firestore lưu hồ sơ
tài khoản và bản sao lưu để chuyển sang máy khác.
