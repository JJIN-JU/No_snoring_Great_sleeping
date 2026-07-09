import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

class SnoreNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // 기존 채널이 진동 OFF로 저장됐을 수 있어서 새 채널 ID 사용
  static const String channelId = 'snore_alert_channel_v3';
  static const String channelName = '코골이 감지 알림';
  static const String channelDescription = '코골이가 감지되었을 때 알림과 진동을 보냅니다.';

  static final Int64List _vibrationPattern =
      Int64List.fromList([0, 800, 300, 800, 300, 1000]);

  static Future<void> init() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
    );

    await _plugin.initialize(initSettings);

    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.requestNotificationsPermission();

    final AndroidNotificationChannel channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: _vibrationPattern,
    );

    await androidPlugin?.createNotificationChannel(channel);
  }

  static Future<void> showSnoreAlert({
    String title = '코골이 감지',
    String body = '코골이가 감지되었습니다. 자세를 바꿔보세요.',
  }) async {
    // 1. 폰 자체 진동 먼저 실행
    final bool hasVibrator = await Vibration.hasVibrator() ?? false;

    if (hasVibrator) {
      await Vibration.vibrate(
        pattern: [0, 800, 300, 800, 300, 1000],
      );
    }

    // 2. 알림 생성
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: _vibrationPattern,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }
}