import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

/// Đổi lỗi kỹ thuật (TimeoutException, FirebaseException, StateError...)
/// thành câu tiếng Việt cho người dùng, thay vì in nguyên văn kiểu
/// "[cloud_firestore/permission-denied] ...".
String friendlyError(Object e) {
  if (e is TimeoutException) {
    return 'Mạng chậm hoặc mất mạng, thử lại sau nhé.';
  }
  if (e is FirebaseException) {
    switch (e.code) {
      case 'permission-denied':
        return 'Bạn không có quyền làm việc này (có thể đã bị gỡ khỏi sổ '
            'hoặc sổ đã bị xóa).';
      case 'not-found':
        return 'Không tìm thấy dữ liệu, có thể đã bị xóa.';
      case 'unavailable':
      case 'network-request-failed':
      case 'deadline-exceeded':
        return 'Không kết nối được máy chủ, kiểm tra mạng rồi thử lại.';
      case 'resource-exhausted':
        return 'Đã vượt giới hạn miễn phí của Firebase hôm nay, thử lại sau.';
      default:
        return 'Có lỗi từ máy chủ (${e.code}), thử lại sau nhé.';
    }
  }
  if (e is StateError) return e.message;
  if (e is FormatException) return e.message;
  if (e is ArgumentError) return '${e.message}';
  return 'Có lỗi xảy ra, thử lại sau nhé.';
}
