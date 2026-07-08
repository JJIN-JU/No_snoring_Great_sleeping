/// 오디오 파일을 FastAPI에 보내고 AI 코골이 판별 결과를 받아옴

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class AIService {
  static const String baseUrl =
      "https://attitude-contamination-partially-coal.trycloudflare.com";

  Future<Map<String, dynamic>> predict({
    required String userId,
    required File wavFile,
    bool save = true,
  }) async {
    final request = http.MultipartRequest(
      "POST",
      Uri.parse("$baseUrl/predict"),
    );

    request.fields["user_id"] = userId;
    request.fields["timestamp"] = DateTime.now().toIso8601String();
    request.fields["save"] = save ? "true" : "false";

    request.files.add(
      await http.MultipartFile.fromPath(
        "file",
        wavFile.path,
      ),
    );

    final streamedResponse = await request.send();

    final response = await http.Response.fromStream(
      streamedResponse,
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      throw Exception("AI 서버 응답 형식이 올바르지 않습니다.");
    }

    throw Exception(
      "AI 서버 오류 (${response.statusCode})\n${response.body}",
    );
  }
}
