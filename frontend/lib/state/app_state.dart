import 'dart:async';

import 'package:flutter/material.dart';

import '../models/sleep_data.dart';
import '../services/auth_api_service.dart';
import '../services/health_connect_service.dart';
import '../services/kakao_auth_service.dart';
import '../services/snore_measure_service.dart';
import '../theme.dart';

class AppState extends ChangeNotifier {
  // =========================
  // 로그인 상태
  // =========================

  bool loggedIn = false;
  String userName = '홍길동';

  bool loginLoading = false;
  String? loginError;

  // MongoDB users 컬렉션의 _id
  String? userId;

  String? kakaoId;
  String? kakaoEmail;
  String? profileImageUrl;
  String? kakaoAccessToken;

  // =========================
  // 화면 / 날짜 상태
  // =========================

  int selectedIndex = 0;

  String bedtimeTarget = '23:30';
  String wakeTarget = '07:00';

  // =========================
  // 수면 + 코골이 측정 상태
  // =========================

  bool measuring = false;
  Duration measuredElapsed = Duration.zero;

  DateTime? _measureStartedAt;
  Timer? _timer;

  final SnoreMeasureService _snoreMeasureService = SnoreMeasureService();

  String? snoreError;

  bool get snoreRecording => _snoreMeasureService.isRunning;

  // =========================
  // Health Connect 상태
  // =========================

  bool healthLoading = false;
  String? healthError;
  DateTime? lastHealthSyncAt;

  // 샘플 데이터 없음
  // Health Connect 수면 데이터 또는 폰 마이크 측정 데이터가 들어올 때만 records에 추가됨
  final List<SleepRecord> _records = [];

  List<SleepRecord> get records => _records;

  SleepRecord get current {
    if (_records.isEmpty) {
      return _emptyRecord();
    }

    if (selectedIndex < 0) {
      selectedIndex = 0;
    }

    if (selectedIndex >= _records.length) {
      selectedIndex = _records.length - 1;
    }

    return _records[selectedIndex];
  }

  bool get hasRecords => _records.isNotEmpty;

  bool get canGoPrev => selectedIndex < _records.length - 1;
  bool get canGoNext => selectedIndex > 0;

  // =========================
  // 카카오 로그인 + DB 저장
  // =========================

  Future<void> loginWithKakao() async {
    if (loginLoading) return;

    loginLoading = true;
    loginError = null;
    notifyListeners();

    try {
      // 1. 카카오 로그인
      final kakaoResult = await KakaoAuthService().login();

      // 2. 카카오 사용자 정보를 FastAPI 서버로 전송
      // 3. FastAPI가 MongoDB users 컬렉션에 저장 또는 업데이트
      // 4. 저장된 user_id 반환
      final savedUser = await AuthApiService().saveKakaoUser(kakaoResult);

      loggedIn = true;

      userId = savedUser.userId;
      kakaoId = savedUser.kakaoId;
      kakaoEmail = savedUser.email;
      profileImageUrl = savedUser.profileImageUrl;

      // 토큰은 앱 내부 로그인 상태 확인용으로만 보관
      // DB에는 저장하지 않음
      kakaoAccessToken = kakaoResult.accessToken;

      userName = savedUser.nickname?.isNotEmpty == true
          ? savedUser.nickname!
          : kakaoResult.nickname?.isNotEmpty == true
              ? kakaoResult.nickname!
              : '카카오 사용자';
    } catch (e) {
      loginError = e.toString();
      loggedIn = false;

      userId = null;
      kakaoId = null;
      kakaoEmail = null;
      profileImageUrl = null;
      kakaoAccessToken = null;
    } finally {
      loginLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      await KakaoAuthService().logout();
    } catch (_) {
      // 카카오 로그아웃 실패해도 앱 내부에서는 로그아웃 처리
    }

    _clearLoginState();
    notifyListeners();
  }

  Future<void> withdraw() async {
    try {
      await KakaoAuthService().unlink();
    } catch (_) {
      // 카카오 연결 해제 실패해도 앱 내부 상태는 초기화
    }

    _clearLoginState();
    notifyListeners();
  }

  void _clearLoginState() {
    loggedIn = false;
    loginLoading = false;
    loginError = null;

    userName = '홍길동';

    userId = null;
    kakaoId = null;
    kakaoEmail = null;
    profileImageUrl = null;
    kakaoAccessToken = null;
  }

  // =========================
  // 날짜 이동
  // =========================

  void goPrev() {
    if (canGoPrev) {
      selectedIndex++;
      notifyListeners();
    }
  }

  void goNext() {
    if (canGoNext) {
      selectedIndex--;
      notifyListeners();
    }
  }

  // =========================
  // 목표 시간 설정
  // =========================

  void setTargets(String bedtime, String wake) {
    bedtimeTarget = bedtime;
    wakeTarget = wake;

    if (_records.isNotEmpty) {
      final old = current;

      _records[selectedIndex] = SleepRecord(
        date: old.date,
        score: old.score,
        bedtimeTarget: bedtimeTarget,
        wakeTarget: wakeTarget,
        bedtimeActual: old.bedtimeActual,
        wakeActual: old.wakeActual,
        totalSleepHours: old.totalSleepHours,
        targetSleepHours: _parseHours(bedtimeTarget, wakeTarget),
        avgSnoreDb: old.avgSnoreDb,
        maxSnoreDb: old.maxSnoreDb,
        snoreHours: old.snoreHours,
        snoreFreqHz: old.snoreFreqHz,
        snoreCount: old.snoreCount,
        noiseDb: old.noiseDb,
        stages: old.stages,
        snoreTimeline: old.snoreTimeline,
      );
    }

    notifyListeners();
  }

  // =========================
  // Health Connect 수면 데이터 불러오기
  // =========================

  Future<void> loadHealthConnectSleep() async {
    if (healthLoading) return;

    healthLoading = true;
    healthError = null;
    notifyListeners();

    try {
      final service = HealthConnectService();
      final result = await service.fetchLastNightSleep();

      final hasSleepTime = result.totalSleepMinutes > 0;
      final hasBedWake = result.bedtime != null || result.wakeTime != null;
      final hasStages = result.stages.isNotEmpty;

      if (!hasSleepTime && !hasBedWake && !hasStages) {
        throw Exception(
          'Health Connect에 불러올 수면 데이터가 없습니다. 삼성 헬스에서 Health Connect 동기화를 먼저 확인해 주세요.',
        );
      }

      final totalSleepHours = double.parse(
        (result.totalSleepMinutes / 60).toStringAsFixed(1),
      );

      final targetHours = _parseHours(bedtimeTarget, wakeTarget);

      final old = _records.isEmpty ? _emptyRecord() : current;

      final bedtimeActual = result.bedtime == null
          ? old.bedtimeActual
          : _formatTime(result.bedtime!);

      final wakeActual = result.wakeTime == null
          ? old.wakeActual
          : _formatTime(result.wakeTime!);

      final stages = result.stages.isEmpty
          ? old.stages
          : result.stages.map((stage) {
              return SleepStage(
                stage.name,
                stage.minutes,
                _stageColor(stage.name),
              );
            }).toList();

      final score = _calculateSleepScore(
        totalSleepHours: totalSleepHours,
        targetSleepHours: targetHours,
        stages: stages,
      );

      final updatedRecord = SleepRecord(
        date: DateTime.now(),
        score: score,
        bedtimeTarget: bedtimeTarget,
        wakeTarget: wakeTarget,
        bedtimeActual: bedtimeActual,
        wakeActual: wakeActual,
        totalSleepHours: totalSleepHours,
        targetSleepHours: targetHours,

        // 코골이/소음 값은 Health Connect가 아니라 폰 마이크 측정값 유지
        avgSnoreDb: old.avgSnoreDb,
        maxSnoreDb: old.maxSnoreDb,
        snoreHours: old.snoreHours,
        snoreFreqHz: old.snoreFreqHz,
        snoreCount: old.snoreCount,
        noiseDb: old.noiseDb,
        snoreTimeline: old.snoreTimeline,

        stages: stages,
      );

      if (_records.isNotEmpty && _isSameDate(_records[0].date, DateTime.now())) {
        _records[0] = updatedRecord;
      } else {
        _records.insert(0, updatedRecord);
      }

      selectedIndex = 0;
      lastHealthSyncAt = DateTime.now();
    } catch (e) {
      healthError = e.toString();
    } finally {
      healthLoading = false;
      notifyListeners();
    }
  }

  // =========================
  // 실제 마이크 기반 코골이/소음 측정
  // =========================

  Future<void> startMeasuring() async {
    if (measuring) return;

    try {
      snoreError = null;

      await _snoreMeasureService.start();

      measuring = true;
      measuredElapsed = Duration.zero;
      _measureStartedAt = DateTime.now();

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_measureStartedAt == null) return;

        measuredElapsed = DateTime.now().difference(_measureStartedAt!);
        notifyListeners();
      });

      notifyListeners();
    } catch (e) {
      snoreError = e.toString();
      measuring = false;
      measuredElapsed = Duration.zero;
      _measureStartedAt = null;
      notifyListeners();
    }
  }

  Future<void> stopMeasuring() async {
    if (!measuring) return;

    _timer?.cancel();

    final snoreResult = await _snoreMeasureService.stop();

    measuring = false;

    if (_records.isNotEmpty) {
      // Health Connect 수면 기록이 있으면 그 기록에 코골이 측정값만 덮어씀
      updateTodaySnoreData(snoreResult);
    } else {
      // Health Connect 수면 기록이 아직 없으면 코골이 측정값만 들어간 기록 생성
      _addSnoreOnlyRecord(snoreResult);
    }

    selectedIndex = 0;
    measuredElapsed = Duration.zero;
    _measureStartedAt = null;

    notifyListeners();
  }

  void _addSnoreOnlyRecord(SnoreMeasureResult snoreResult) {
    final start = _measureStartedAt ?? DateTime.now();
    final end = DateTime.now();

    final timeline = snoreResult.snoreTimeline.isEmpty
        ? const <SnorePoint>[]
        : snoreResult.snoreTimeline;

    _records.insert(
      0,
      SleepRecord(
        date: DateTime.now(),

        // Health Connect 수면 데이터가 없으므로 수면 점수는 0
        score: 0,
        bedtimeTarget: bedtimeTarget,
        wakeTarget: wakeTarget,

        // 실제 마이크 측정 시작/종료 시각
        bedtimeActual: _formatTime(start),
        wakeActual: _formatTime(end),

        // 수면 시간은 Health Connect 값이 아니므로 0으로 둠
        totalSleepHours: 0,
        targetSleepHours: _parseHours(bedtimeTarget, wakeTarget),

        // 실제 폰 마이크 측정 결과
        avgSnoreDb: snoreResult.avgSnoreDb,
        maxSnoreDb: snoreResult.maxSnoreDb,
        snoreHours: snoreResult.snoreHours,
        snoreFreqHz: snoreResult.snoreFreqHz,
        snoreCount: snoreResult.snoreCount,
        noiseDb: snoreResult.noiseDb,
        snoreTimeline: timeline,

        // 수면 단계는 Health Connect에서 받아오기 전까지 비워둠
        stages: const [],
      ),
    );
  }

  // Health Connect로 수면 기록을 먼저 가져온 뒤,
  // 마이크 측정 결과만 현재 기록에 덮어씌움
  void updateTodaySnoreData(SnoreMeasureResult snoreResult) {
    if (_records.isEmpty) return;

    final old = current;

    _records[selectedIndex] = SleepRecord(
      date: old.date,
      score: old.score,
      bedtimeTarget: old.bedtimeTarget,
      wakeTarget: old.wakeTarget,
      bedtimeActual: old.bedtimeActual,
      wakeActual: old.wakeActual,
      totalSleepHours: old.totalSleepHours,
      targetSleepHours: old.targetSleepHours,

      // 실제 폰 마이크 측정값
      avgSnoreDb: snoreResult.avgSnoreDb,
      maxSnoreDb: snoreResult.maxSnoreDb,
      snoreHours: snoreResult.snoreHours,
      snoreFreqHz: snoreResult.snoreFreqHz,
      snoreCount: snoreResult.snoreCount,
      noiseDb: snoreResult.noiseDb,
      snoreTimeline: snoreResult.snoreTimeline.isEmpty
          ? old.snoreTimeline
          : snoreResult.snoreTimeline,

      // 수면 단계는 Health Connect 값 유지
      stages: old.stages,
    );

    notifyListeners();
  }

  // =========================
  // 공통 유틸
  // =========================

  static String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  static bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static Color _stageColor(String name) {
    if (name.contains('깊')) return AppColors.primary;
    if (name.contains('REM') || name.contains('렘')) return AppColors.accent;
    if (name.contains('얕')) return AppColors.gold;
    if (name.contains('깸') || name.contains('기상')) return AppColors.orange;
    return AppColors.muted;
  }

  static int _calculateSleepScore({
    required double totalSleepHours,
    required double targetSleepHours,
    required List<SleepStage> stages,
  }) {
    if (totalSleepHours <= 0) {
      return 0;
    }

    var score = 100.0;

    final diff = (targetSleepHours - totalSleepHours).abs();
    score -= diff * 8;

    final totalStageMinutes = stages.fold<double>(
      0,
      (sum, stage) => sum + stage.minutes,
    );

    if (totalStageMinutes > 0) {
      final deepMinutes = stages
          .where((s) => s.name.contains('깊'))
          .fold<double>(0, (sum, s) => sum + s.minutes);

      final remMinutes = stages
          .where((s) => s.name.contains('REM') || s.name.contains('렘'))
          .fold<double>(0, (sum, s) => sum + s.minutes);

      final awakeMinutes = stages
          .where((s) => s.name.contains('깸'))
          .fold<double>(0, (sum, s) => sum + s.minutes);

      final deepRatio = deepMinutes / totalStageMinutes;
      final remRatio = remMinutes / totalStageMinutes;
      final awakeRatio = awakeMinutes / totalStageMinutes;

      if (deepRatio < 0.12) score -= 8;
      if (remRatio < 0.15) score -= 6;
      if (awakeRatio > 0.12) score -= 10;
    }

    return score.clamp(0, 100).round();
  }

  static double _parseHours(String bed, String wake) {
    final b = _toMinutes(bed);
    var w = _toMinutes(wake);

    if (w <= b) {
      w += 24 * 60;
    }

    return double.parse(((w - b) / 60).toStringAsFixed(1));
  }

  static int _toMinutes(String hhmm) {
    final p = hhmm.split(':');

    if (p.length != 2) {
      return 0;
    }

    final hour = int.tryParse(p[0]) ?? 0;
    final minute = int.tryParse(p[1]) ?? 0;

    return hour * 60 + minute;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _snoreMeasureService.cancel();
    super.dispose();
  }
}

// =========================
// 빈 기록
// =========================

SleepRecord _emptyRecord() {
  final now = DateTime.now();

  return SleepRecord(
    date: now,
    score: 0,
    bedtimeTarget: '23:30',
    wakeTarget: '07:00',
    bedtimeActual: '--:--',
    wakeActual: '--:--',
    totalSleepHours: 0,
    targetSleepHours: 7.5,
    avgSnoreDb: 0,
    maxSnoreDb: 0,
    snoreHours: 0,
    snoreFreqHz: 0,
    snoreCount: 0,
    noiseDb: 0,
    stages: const [],
    snoreTimeline: const [],
  );
}

// =========================
// 월별 통계
// =========================

// 임시 월별 샘플 제거.
// 월별 통계를 실제 값으로 만들려면 stats_tab.dart에서 state.records를 월별로 묶어 평균 내도록 수정해야 함.
const List<MonthlyRecord> monthlyRecords = [];