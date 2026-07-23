/// 오디오 파일을 FastAPI에 보내고 AI 코골이 판별 결과를 받아옴

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';

class AIService {
  static const int maxAttempts = 2;
  static const Duration retryDelay = Duration(seconds: 2);
  static const Duration requestTimeout = Duration(seconds: 15);

  Future<Map<String, dynamic>> predict({
    required String userId,
    required File wavFile,
    bool save = true,
  }) async {
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await _sendPredictRequest(
          userId: userId,
          wavFile: wavFile,
          save: save,
        );
      } catch (e) {
        lastError = e;

        if (attempt >= maxAttempts) {
          break;
        }

        await Future.delayed(retryDelay);
      }
    }

    throw Exception(
      'AI 서버 연결에 실패했습니다. 잠시 후 다시 시도해 주세요.\n'
      '상세 오류: $lastError',
    );
  }

  Future<Map<String, dynamic>> _sendPredictRequest({
    required String userId,
    required File wavFile,
    required bool save,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConfig.baseUrl}/predict'),
    );

    request.fields['user_id'] = userId;
    request.fields['timestamp'] = DateTime.now().toIso8601String();
    request.fields['save'] = save ? 'true' : 'false';

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        wavFile.path,
      ),
    );

    final streamedResponse = await request
        .send()
        .timeout(requestTimeout);

    final response = await http.Response.fromStream(
      streamedResponse,
    ).timeout(requestTimeout);

    if (response.statusCode != 200) {
      throw Exception(
        'AI 서버 오류 (${response.statusCode})\n${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    throw Exception('AI 서버 응답 형식이 올바르지 않습니다.');
  }
}
