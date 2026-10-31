import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Thông báo nhắc nợ chạy trên máy (không cần server).
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'debt_reminder',
      'Nhắc nợ',
      channelDescription: 'Nhắc các khoản nợ trong nhóm',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    // App dùng ở Việt Nam nên đặt cố định múi giờ.
    tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
  }

  /// Android 13+ phải xin quyền hiện thông báo. Trả về true nếu được phép.
  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  /// Đặt lịch nhắc. Dùng lịch không chính xác tuyệt đối (có thể lệch vài
  /// phút) để khỏi phải xin quyền báo thức chính xác trên Android 14.
  static Future<void> schedule({
    required DateTime at,
    required String title,
    required String body,
  }) async {
    final id = at.millisecondsSinceEpoch ~/ 1000 % 0x7fffffff;
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: title,
      body: body,
    );
    debugPrint('Đã đặt nhắc nợ #$id lúc $at');
  }

  /// Hiện ngay một thông báo (dùng để thử).
  static Future<void> showNow(String title, String body) => _plugin.show(
        id: 0,
        title: title,
        body: body,
        notificationDetails: _details,
      );
}
