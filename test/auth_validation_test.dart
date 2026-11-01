import 'package:chia_tien/logic/auth_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('email', () {
    expect(validateEmail(''), isNotNull);
    expect(validateEmail('abc'), isNotNull);
    expect(validateEmail('a@b'), isNotNull);
    expect(validateEmail(' huy@gmail.com '), isNull);
  });

  test('mật khẩu', () {
    expect(validatePassword(''), isNotNull);
    expect(validatePassword('ab1'), 'Mật khẩu cần ít nhất 6 ký tự');
    expect(validatePassword('abcdef'), 'Mật khẩu cần có cả chữ và số');
    expect(validatePassword('123456'), 'Mật khẩu cần có cả chữ và số');
    expect(validatePassword('chipin1'), isNull);
  });

  test('nhập lại mật khẩu và tên', () {
    expect(validateConfirmPassword('abc123', 'abc124'), isNotNull);
    expect(validateConfirmPassword('abc123', 'abc123'), isNull);
    expect(validateDisplayName('  '), isNotNull);
    expect(validateDisplayName('Huy'), isNull);
  });

  test('mã lỗi Firebase ra tiếng Việt', () {
    expect(authErrorMessage('invalid-credential'), 'Sai email hoặc mật khẩu.');
    expect(authErrorMessage('email-already-in-use'), contains('đã được đăng ký'));
    expect(authErrorMessage('la-lam'), contains('la-lam'));
  });
}
