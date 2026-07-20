import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'kakao_auth_service.dart';
import '../config.dart';

class SavedUser {
  final String userId;
  final String kakaoId;
  final String? nickname;
  final String? email;
  final String? profileImageUrl;

  const SavedUser({
    required this.userId,
    required this.kakaoId,
    required this.nickname,
    required this.email,
    required this.profileImageUrl,
  });

  factory SavedUser.fromJson(Map<String, dynamic> json) {
    return SavedUser(
      userId: json['user_id'].toString(),
      kakaoId: json['kakao_id'].toString(),
      nickname: json['nickname'],
      email: json['email'],
      profileImageUrl: json['profile_image_url'],
    );
  }
}

class AuthApiService {
  Future<SavedUser> saveKakaoUser(KakaoLoginResult result) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/auth/kakao'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'kakao_id': result.kakaoId,
              'nickname': result.nickname,
              'email': result.email,
              'profile_image_url': result.profileImageUrl,
            }),
          )
          .timeout(
            const Duration(seconds: 8),
          );

      if (response.statusCode != 200) {
        throw Exception(
          '회원 정보 DB 저장 실패: ${response.statusCode} / ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      if (decoded['success'] != true) {
        throw Exception('회원 정보 DB 저장 실패');
      }

      return SavedUser.fromJson(decoded['user']);
    } on TimeoutException {
      throw Exception(
        '서버 연결 시간이 초과됐습니다. 백엔드가 켜져 있는지, 휴대폰에서 ${AppConfig.baseUrl} 접속이 되는지 확인해 주세요.',
      );
    } catch (e) {
      throw Exception('회원 정보 DB 저장 중 오류: $e');
    }
  }

  Future<void> deleteKakaoUser(String kakaoId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('${AppConfig.baseUrl}/auth/kakao/$kakaoId'),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        throw Exception(
          '회원 정보 DB 삭제 실패: ${response.statusCode} / ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      if (decoded['success'] != true) {
        throw Exception('회원 정보 DB 삭제 실패');
      }
    } on TimeoutException {
      throw Exception('서버 연결 시간이 초과됐습니다. 현재 주소: ${AppConfig.baseUrl}');
    } catch (e) {
      throw Exception('회원 정보 DB 삭제 중 오류: $e');
    }
  }
}
