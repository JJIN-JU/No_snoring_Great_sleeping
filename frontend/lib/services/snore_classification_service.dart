  /// WAV 파일을 FastAPI에 보내고 결과를 받아옴

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class AIService {

  static const String baseUrl =
      "서버 여는 사람 컴퓨터 IP로 바꿔주세요";

  Future<Map<String, dynamic>> predict({
    required String userId,
    required File wavFile,
  }) async {
    final request = http.MultipartRequest(
    "POST",
    Uri.parse("$baseUrl/predict"),
  );

  // user_id 추가
  request.fields["user_id"] = userId;

  // timestamp 추가
  request.fields["timestamp"] =
      DateTime.now().toIso8601String();

  // wav 파일 추가
  request.files.add(
    await http.MultipartFile.fromPath(
      "file",
      wavFile.path,
    ),
  );

  // 요청 전송
  final streamedResponse = await request.send();

  // 응답 읽기
  final response = await http.Response.fromStream(
    streamedResponse,
  );

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  }

  throw Exception(
    "AI 서버 오류 (${response.statusCode})\n${response.body}",
  );
}
}