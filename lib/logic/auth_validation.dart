/// Kiểm tra dữ liệu ô nhập ở màn đăng nhập/đăng ký và đổi mã lỗi của
/// Firebase Auth sang câu tiếng Việt. Không phụ thuộc Firebase để dễ test.
library;

final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

/// Trả về câu báo lỗi, hoặc null nếu hợp lệ (đúng kiểu validator của TextFormField).
String? validateEmail(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'Nhập email';
  if (!_emailRe.hasMatch(s)) return 'Email không hợp lệ';
  return null;
}

/// Firebase yêu cầu tối thiểu 6 ký tự. App đòi thêm có cả chữ và số.
String? validatePassword(String? v) {
  final s = v ?? '';
  if (s.isEmpty) return 'Nhập mật khẩu';
  if (s.length < 6) return 'Mật khẩu cần ít nhất 6 ký tự';
  if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) {
    return 'Mật khẩu cần có cả chữ và số';
  }
  return null;
}

String? validateDisplayName(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'Nhập tên của bạn';
  if (s.length > 40) return 'Tên dài quá (tối đa 40 ký tự)';
  return null;
}

String? validateConfirmPassword(String? v, String password) {
  if ((v ?? '').isEmpty) return 'Nhập lại mật khẩu';
  if (v != password) return 'Mật khẩu nhập lại không khớp';
  return null;
}

/// Mã lỗi FirebaseAuthException.code → câu hiển thị.
String authErrorMessage(String code) => switch (code) {
      'invalid-email' => 'Email không hợp lệ.',
      'user-disabled' => 'Tài khoản này đã bị khóa.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' ||
      'INVALID_LOGIN_CREDENTIALS' =>
        'Sai email hoặc mật khẩu.',
      'email-already-in-use' => 'Email này đã được đăng ký. Hãy đăng nhập.',
      'weak-password' => 'Mật khẩu quá yếu.',
      'operation-not-allowed' =>
        'Chưa bật đăng nhập Email/Password trong Firebase Console.',
      'too-many-requests' => 'Thử sai nhiều lần quá. Đợi một lúc rồi thử lại.',
      'network-request-failed' => 'Không có mạng. Kiểm tra kết nối rồi thử lại.',
      'requires-recent-login' => 'Cần đăng nhập lại để làm thao tác này.',
      _ => 'Có lỗi xảy ra ($code).',
    };
