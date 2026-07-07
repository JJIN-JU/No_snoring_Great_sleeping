import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme.dart';

class LoginScreen extends StatelessWidget {
  final AppState state;

  const LoginScreen({
    super.key,
    required this.state,
  });

  Future<void> _handleKakaoLogin(BuildContext context) async {
    await state.loginWithKakao();

    if (!context.mounted) return;

    if (state.loginError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('카카오 로그인 실패: ${state.loginError}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF10142A),
              AppColors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 3),

                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.nightlight_round,
                    size: 48,
                    color: AppColors.primary,
                  ),
                ),

                const SizedBox(height: 28),

                const Text(
                  '숙면',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: AppColors.foreground,
                  ),
                ),

                const SizedBox(height: 10),

                const Text(
                  '매일 밤의 수면과 코골이를 기록하고\n더 나은 아침을 만들어보세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.muted,
                    height: 1.5,
                  ),
                ),

                const Spacer(flex: 4),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: state.loginLoading
                        ? null
                        : () => _handleKakaoLogin(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.kakao,
                      foregroundColor: AppColors.kakaoText,
                      elevation: 0,
                      disabledBackgroundColor: AppColors.kakao,
                      disabledForegroundColor: AppColors.kakaoText,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: state.loginLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.kakaoText,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                '카카오로 시작하기',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                const Text(
                  '로그인 시 서비스 이용약관에 동의하게 됩니다',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                  ),
                ),

                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}