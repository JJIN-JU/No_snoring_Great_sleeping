import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

class KakaoLoginResult {
  final String kakaoId;
  final String? nickname;
  final String? email;
  final String? profileImageUrl;
  final String accessToken;

  const KakaoLoginResult({
    required this.kakaoId,
    required this.nickname,
    required this.email,
    required this.profileImageUrl,
    required this.accessToken,
  });
}

class KakaoAuthService {
  // 지금은 이메일 제외
  // Kakao Developers 동의항목에 설정된 것만 요청해야 KOE205가 안 남
  static const List<String> _profileScopes = [
    'profile_nickname',
    'profile_image',
  ];

  Future<KakaoLoginResult> login() async {
    OAuthToken token;

    if (await isKakaoTalkInstalled()) {
      try {
        token = await UserApi.instance.loginWithKakaoTalk();
      } catch (_) {
        token = await UserApi.instance.loginWithKakaoAccount();
      }
    } else {
      token = await UserApi.instance.loginWithKakaoAccount();
    }

    User user = await UserApi.instance.me();

    final missingScopes = <String>[];

    final nickname = user.kakaoAccount?.profile?.nickname;
    final profileImageUrl = user.kakaoAccount?.profile?.profileImageUrl;

    if (nickname == null || nickname.isEmpty) {
      missingScopes.add('profile_nickname');
    }

    if (profileImageUrl == null || profileImageUrl.isEmpty) {
      missingScopes.add('profile_image');
    }

    if (missingScopes.isNotEmpty) {
      try {
        token = await UserApi.instance.loginWithNewScopes(missingScopes);
        user = await UserApi.instance.me();
      } catch (_) {
        // 사용자가 추가 동의를 거부하거나 설정이 안 된 항목이면
        // 앱이 죽지 않게 null 값으로 진행
      }
    }

    return KakaoLoginResult(
      kakaoId: user.id.toString(),
      nickname: user.kakaoAccount?.profile?.nickname,
      email: null,
      profileImageUrl: user.kakaoAccount?.profile?.profileImageUrl,
      accessToken: token.accessToken,
    );
  }

  Future<void> logout() async {
    try {
      await UserApi.instance.logout();
    } catch (_) {}
  }

  Future<void> unlink() async {
    try {
      await UserApi.instance.unlink();
    } catch (_) {}
  }
}