import 'package:flutter/material.dart';

/// 밤하늘 느낌의 다크 테마 색상 팔레트
class AppColors {
  static const background = Color(0xFF161A2B);
  static const card = Color(0xFF212642);
  static const cardAlt = Color(0xFF2A2F52);
  static const foreground = Color(0xFFF2F4FB);
  static const muted = Color(0xFF9AA0BF);
  static const border = Color(0xFF343A5E);

  // 브랜드/포인트 색상
  static const primary = Color(0xFF6C8BFF); // 파랑 (수면 점수)
  static const accent = Color(0xFF3ED6C5); // 청록 (렘/보조)
  static const gold = Color(0xFFF2C94C); // 노랑 (통계/경고)
  static const orange = Color(0xFFF2994A); // 주황 (부족 수면)
  static const pink = Color(0xFFEB6F92); // 코골이 강조

  static const kakao = Color(0xFFFEE500);
  static const kakaoText = Color(0xFF191600);
}

/// 수면 점수를 등급으로 변환
class ScoreGrade {
  final String label;
  final Color color;
  const ScoreGrade(this.label, this.color);

  static ScoreGrade of(int score) {
    if (score >= 90) return const ScoreGrade('매우 좋음', AppColors.accent);
    if (score >= 80) return const ScoreGrade('좋음', AppColors.primary);
    if (score >= 70) return const ScoreGrade('보통', AppColors.gold);
    if (score >= 60) return const ScoreGrade('나쁨', AppColors.orange);
    return const ScoreGrade('매우 나쁨', AppColors.pink);
  }
}

ThemeData buildAppTheme() {
  const base = ColorScheme.dark(
    surface: AppColors.background,
    primary: AppColors.primary,
    secondary: AppColors.accent,
    onPrimary: Color(0xFF10142A),
    onSurface: AppColors.foreground,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: base,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Roboto',
    textTheme: const TextTheme().apply(
      bodyColor: AppColors.foreground,
      displayColor: AppColors.foreground,
    ),
  );
}
