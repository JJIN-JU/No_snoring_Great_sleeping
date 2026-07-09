import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'snore_notification_service.dart';

const String snoreBaseUrl =
    'https://lets-literally-communicate-say.trycloudflare.com';

final SnorePollingService snorePollingService = SnorePollingService(
  baseUrl: snoreBaseUrl,
);

class SnorePollingService {
  final String baseUrl;

  Timer? _timer;
  int _lastAlertId = 0;
  bool _isFetching = false;
  bool _measurementActive = false;

  SnorePollingService({
    required this.baseUrl,
  });

  void start() {
    _timer?.cancel();

    print('코골이 알림 polling 시작: $baseUrl');

    _fetchLatestAlert();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _fetchLatestAlert(),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void setMeasurementActive(bool value) {
    _measurementActive = value;

    if (value) {
      print('코골이 측정 알림 활성화');
    } else {
      print('코골이 측정 알림 비활성화');
    }
  }

  bool get measurementActive => _measurementActive;

  Future<void> _fetchLatestAlert() async {
    if (_isFetching) return;

    _isFetching = true;

    try {
      final uri = Uri.parse(
        '$baseUrl/alerts/snore/latest?last_id=$_lastAlertId',
      );

      final response = await http.get(uri).timeout(
            const Duration(seconds: 5),
          );

      if (response.statusCode != 200) {
        print('코골이 알림 조회 실패: ${response.statusCode}');
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final currentIdRaw = data['current_id'];
      final currentId = currentIdRaw is int
          ? currentIdRaw
          : int.tryParse(currentIdRaw.toString()) ?? _lastAlertId;

      final hasNew = data['has_new'] == true;

      if (!hasNew) {
        _lastAlertId = currentId;
        return;
      }

      final alert = data['alert'];

      // 측정 중이 아닐 때는 알림을 울리지 않고 id만 소비함
      if (!_measurementActive) {
        _lastAlertId = currentId;
        print('코골이 알림 감지됨 but 측정 중 아님. id=$currentId');
        return;
      }

      if (alert is Map<String, dynamic>) {
        final title = alert['title']?.toString() ?? '코골이 감지';
        final body = alert['message']?.toString() ?? '코골이가 감지되었습니다.';

        await SnoreNotificationService.showSnoreAlert(
          title: title,
          body: body,
        );

        print('코골이 알림 수신 완료 id=$currentId');
      }

      _lastAlertId = currentId;
    } catch (e) {
      print('코골이 polling 에러: $e');
    } finally {
      _isFetching = false;
    }
  }
}