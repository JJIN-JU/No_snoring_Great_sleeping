import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class SnoreNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // 기존 채널의 진동 설정이 유지될 수 있으므로 새 채널 ID 사용
  static const String channelId = 'snore_alert_channel_v4';
  static const String channelName = '코골이 감지 알림';
  static const String channelDescription =
      '코골이가 감지되었을 때 알림만 표시합니다.';

  static Future<void> init() async {
    if (kIsWeb) return;

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
    );

    await _plugin.initialize(initSettings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.requestNotificationsPermission();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.high,
      playSound: true,
      enableVibration: false,
    );

    await androidPlugin?.createNotificationChannel(channel);
  }

  static Future<void> showSnoreAlert({
    String title = '코골이 감지',
    String body = '코골이가 감지되었습니다. 자세를 바꿔보세요.',
  }) async {
    if (kIsWeb) return;

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: false,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _plugin.show(
      1001,
      title,
      body,
      details,
    );
  }
}