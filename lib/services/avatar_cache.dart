import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

/// Ảnh đại diện công khai của các tài khoản, đọc từ Firestore `avatars/{uid}`.
///
/// Hồ sơ `users/{uid}` chỉ chủ tài khoản đọc được (có số điện thoại...), nên
/// ảnh đại diện được ghi thêm một bản vào `avatars/{uid}` để người cùng sổ
/// chung xem được. Mỗi uid lắng nghe một lần, ảnh đổi thì tự cập nhật.
class AvatarCache {
  static final _images = <String, ValueNotifier<ImageProvider?>>{};

  static ValueNotifier<ImageProvider?> of(String uid) =>
      _images.putIfAbsent(uid, () {
        final n = ValueNotifier<ImageProvider?>(null);
        FirebaseFirestore.instance
            .collection('avatars')
            .doc(uid)
            .snapshots()
            .listen(
              (s) => n.value = decode(s.data()?['avatar']),
              onError: (Object e) => debugPrint('Không đọc được ảnh $uid: $e'),
            );
        return n;
      });

  /// Cập nhật ngay ảnh của chính mình sau khi đổi, khỏi chờ Firestore.
  static void put(String uid, Uint8List? jpeg) =>
      of(uid).value = jpeg == null ? null : MemoryImage(jpeg);

  static ImageProvider? decode(Object? b64) {
    if (b64 is! String || b64.isEmpty) return null;
    try {
      return MemoryImage(base64Decode(b64));
    } catch (_) {
      return null;
    }
  }
}
