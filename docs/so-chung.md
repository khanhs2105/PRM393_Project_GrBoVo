# Sổ chung: mỗi người một tài khoản, chủ sổ nhắc nợ

## Cách hoạt động

1. **Chủ sổ** (người tạo nhóm) đăng nhập tài khoản của mình, tạo nhóm như cũ, thêm thành viên.
2. Trong nhóm, tab **Thành viên** > **Bật sổ chung** (hoặc menu ⋮ > *Bật sổ chung*), chọn
   "Bạn là ai trong nhóm này". App tạo sổ trên Firestore.
3. Bấm **Mời** cạnh từng thành viên. Mỗi người có **một mã 6 ký tự riêng**, bấm *Gửi mã* để gửi
   qua Zalo/Messenger.
4. **Thành viên** đăng ký tài khoản riêng trên máy của họ, bấm biểu tượng 🔑 *Nhập mã mời* ở màn
   chính, nhập mã. Từ đó tài khoản này **đứng tên** đúng thành viên đó trong sổ, nên app biết
   "Nam" là tài khoản nào.
5. Thành viên thấy mục **Sổ bạn được mời** ở màn chính: số dư của mình, mình cần trả ai bao
   nhiêu (có mã QR chuyển khoản nếu người nhận đã điền ngân hàng), số dư cả nhóm, các khoản chi.
   Sổ tự cập nhật khi chủ sổ thêm khoản chi hoặc ghi nhận trả tiền. Thành viên **chỉ xem**.
6. **Chỉ chủ sổ** thấy nút 🔔 ở tab **Số dư**, cạnh những lượt "X trả <chủ sổ>" mà X đã có tài
   khoản. Bấm để soạn và gửi nhắc nợ. Máy của X hiện thông báo "<chủ sổ> nhắc nợ".

Thành viên chưa nhập mã thì không có nút chuông (chưa biết gửi cho tài khoản nào). Nhấn giữ nhãn
*Đã vào: ...* để gỡ tài khoản nhận nhầm. Xóa nhóm thì sổ chung cũng bị xóa.

## Bảo mật (firestore.rules)

- Sổ: chỉ tài khoản trong `memberUids` đọc được; chỉ chủ sổ sửa/xóa.
- Người được mời chỉ được thêm **chính mình** vào sổ, và phải kèm mã mời đúng của sổ đó; tài
  khoản tự động đứng tên đúng thành viên ghi trong mã (không tự chọn tên người khác được).
- Mã mời: đọc được nếu biết mã, không liệt kê được; chỉ chủ sổ tạo.
- Nhắc nợ: chỉ chủ sổ của sổ đó tạo được, và chỉ gửi cho tài khoản đang trong sổ. Người nhận chỉ
  được đánh dấu "đã nhận".

## Giới hạn (vì dùng gói Spark miễn phí)

Gửi push khi app đã tắt hẳn cần Cloud Functions (gói Blaze trả phí). App dùng cách miễn phí: máy
người nhận lắng nghe collection `notifications` và bật thông báo trên máy. Thông báo hiện ngay
khi app đang mở hoặc chạy nền; nếu app đã bị tắt hẳn thì thông báo hiện ở lần mở app tiếp theo.

## Thử trên 2 máy (hoặc 1 máy + 1 máy ảo)

1. Dán `firestore.rules` mới vào Firebase Console > Firestore > Rules > **Publish**.
2. `flutter pub get` rồi `flutter run` trên cả hai máy.
3. Máy A: đăng ký tài khoản *Huy*, tạo nhóm "Đi ăn" với Huy, Nam; thêm khoản 200.000đ Huy trả,
   chia đều. Tab Thành viên > Bật sổ chung > chọn Huy. Bấm **Mời** cạnh Nam, ghi lại mã.
4. Máy B: đăng ký tài khoản *Nam*, bấm 🔑, nhập mã. Thấy sổ "Đi ăn", *Bạn đang nợ 100.000đ*.
5. Máy A: mở lại nhóm, tab Thành viên thấy *Đã vào: Nam*. Tab Số dư bấm 🔔 cạnh "Nam trả Huy",
   bấm Gửi.
6. Máy B: hiện thông báo "Huy nhắc nợ · Đi ăn", trong sổ có mục *Nhắc nợ từ chủ sổ*.
7. Trên Firebase Console thấy 3 collection `ledgers`, `invites`, `notifications`.

Chỉ có 1 máy: đăng xuất A, đăng nhập B trên cùng máy cũng được (dữ liệu nhóm trên máy vẫn còn
nhưng sổ chung gắn theo tài khoản nên B không thấy nút của chủ sổ).
