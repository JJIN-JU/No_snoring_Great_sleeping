import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'snore_notification_service.dart';

class SnoreRealtimeService {
  WebSocketChannel? _channel;
  Timer? _pingTimer;
  bool _connected = false;

  /// Android 에뮬레이터면 10.0.2.2
  /// 실제 핸드폰이면 PC와 같은 와이파이에서 PC IP 사용
  ///
  /// 예:
  /// ws://192.168.0.15:8000/ws/snore
  final String wsUrl;

  SnoreRealtimeService({
    required this.wsUrl,
  });

  void connect() {
    if (_connected) return;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _connected = true;

      print('코골이 WebSocket 연결됨: $wsUrl');

      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onError: (error) {
          print('코골이 WebSocket 에러: $error');
          _reconnect();
        },
        onDone: () {
          print('코골이 WebSocket 종료');
          _reconnect();
        },
      );

      _startPing();
    } catch (e) {
      print('코골이 WebSocket 연결 실패: $e');
      _reconnect();
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message.toString());

      final type = data['type'];
      final vibration = data['vibration'] == true;

      if (type == 'SNORE_ALERT' && vibration) {
        final title = data['title']?.toString() ?? '코골이 감지';
        final body = data['message']?.toString() ?? '코골이가 감지되었습니다.';

        SnoreNotificationService.showSnoreAlert(
          title: title,
          body: body,
        );
      }
    } catch (e) {
      print('코골이 WebSocket 메시지 파싱 실패: $e');
    }
  }

  void _startPing() {
    _pingTimer?.cancel();

    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      try {
        _channel?.sink.add('ping');
      } catch (_) {}
    });
  }

  void _reconnect() {
    disconnect();

    Future.delayed(const Duration(seconds: 3), () {
      connect();
    });
  }

  void disconnect() {
    _connected = false;
    _pingTimer?.cancel();
    _pingTimer = null;

    try {
      _channel?.sink.close();
    } catch (_) {}

    _channel = null;
  }
}