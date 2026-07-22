import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiServerManager {
  ApiServerManager._();

  static const List<String> _serverUrls = [
    // 팀 공용 서버 'https://lets-literally-communicate-say.trycloudflare.com',

    // 현재 개인 서버
    'https://owen-curious-scenic-ron.trycloudflare.com',
  ];

  static String? _activeBaseUrl;

  static String? get activeBaseUrl => _activeBaseUrl;

  static Future<String> findAvailableServer({
    bool forceCheck = false,
  }) async {
    if (!forceCheck && _activeBaseUrl != null) {
      return _activeBaseUrl!;
    }

    for (final baseUrl in _serverUrls) {
      try {
        final uri = Uri.parse(
          '$baseUrl/sleep-tags/health',
        );

        print('[API SERVER] 연결 확인: $uri');

        final response = await http
            .get(
              uri,
              headers: const {
                'Accept': 'application/json',
              },
            )
            .timeout(
              const Duration(seconds: 5),
            );

        if (response.statusCode != 200) {
          print(
            '[API SERVER] 연결 실패: '
            '$baseUrl / ${response.statusCode}',
          );
          continue;
        }

        final responseText = utf8.decode(
          response.bodyBytes,
        );

        final decoded = jsonDecode(responseText);

        if (decoded is Map &&
            decoded['success'] == true) {
          _activeBaseUrl = baseUrl;

          print(
            '[API SERVER] 연결 성공: $baseUrl',
          );

          return baseUrl;
        }
      } catch (error) {
        print(
          '[API SERVER] 연결 오류: '
          '$baseUrl / $error',
        );
      }
    }

    throw Exception(
      '연결 가능한 AI 분석 서버가 없습니다. '
      'FastAPI와 Cloudflare 실행 상태를 확인해 주세요.',
    );
  }

  static void reset() {
    _activeBaseUrl = null;
  }
}