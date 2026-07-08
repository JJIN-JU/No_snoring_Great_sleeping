import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/sleep_data.dart';
import '../services/auth_api_service.dart';
import '../services/health_connect_service.dart';
import '../services/kakao_auth_service.dart';
import '../services/snore_classification_service.dart';
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

  bool apneaLoading = false;
  String? apneaError;
  List<ApneaRiskSummary> apneaHistory = [];

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
    if (loggedIn) {
      await refreshAllHealthData();
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
    if (loginLoading) return;

    loginLoading = true;
    loginError = null;
    notifyListeners();

    final currentKakaoId = kakaoId;

    try {
      if (currentKakaoId == null || currentKakaoId.isEmpty) {
        throw Exception('카카오 사용자 ID가 없어 DB 삭제를 진행할 수 없습니다.');
      }

      // 1. FastAPI 서버에 DB 사용자 삭제 요청
      await AuthApiService().deleteKakaoUser(currentKakaoId);

      // 2. 카카오 연결 해제
      await KakaoAuthService().unlink();

      // 3. 앱 내부 로그인 상태 초기화
      _clearLoginState();
    } catch (e) {
      loginError = e.toString();
    } finally {
      loginLoading = false;
      notifyListeners();
    }
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

        // 목표 시간 변경 시 기존 녹음 클립 유지
        snoreAudioClips: old.snoreAudioClips,
      );
    }

    notifyListeners();
  }

  // =========================
  // Health Connect 수면 데이터 불러오기
  // =========================

  Future<void> loadHealthConnectSleep({int nights = 7}) async {
    if (healthLoading) return;

    healthLoading = true;
    healthError = null;
    notifyListeners();

    try {
      final service = HealthConnectService();
      final history = await service.fetchSleepHistory(nights: nights);

      final targetHours = _parseHours(bedtimeTarget, wakeTarget);

      // 같은 날짜의 기존 레코드가 있다면(폰 마이크로 측정한 코골이 값 등)
      // 코골이 관련 필드는 최대한 유지한다.
      final oldByDate = <String, SleepRecord>{
        for (final r in _records) _dateKey(r.date): r,
      };

      final newRecords = history.map((result) {
        final old = oldByDate[_dateKey(result.date)];

        final totalSleepHours = double.parse(
          (result.totalSleepMinutes / 60).toStringAsFixed(1),
        );

        final bedtimeActual = result.bedtime == null
            ? (old?.bedtimeActual ?? bedtimeTarget)
            : _formatTime(result.bedtime!);

        final wakeActual = result.wakeTime == null
            ? (old?.wakeActual ?? wakeTarget)
            : _formatTime(result.wakeTime!);

        final stages = result.stages.isNotEmpty
            ? result.stages.map((stage) {
                return SleepStage(
                  stage.name,
                  stage.minutes,
                  _stageColor(stage.name),
                );
              }).toList()
            : (old?.stages ?? const <SleepStage>[]);

        final score = _calculateSleepScore(
          totalSleepHours: totalSleepHours,
          targetSleepHours: targetHours,
          stages: stages,
        );

        return SleepRecord(
          date: result.date,
          score: score,
          bedtimeTarget: bedtimeTarget,
          wakeTarget: wakeTarget,
          bedtimeActual: bedtimeActual,
          wakeActual: wakeActual,
          totalSleepHours: totalSleepHours,
          targetSleepHours: targetHours,

          // 코골이/소음 값은 Health Connect가 아니라 폰 마이크 측정값 유지
          avgSnoreDb: old?.avgSnoreDb ?? 0,
          maxSnoreDb: old?.maxSnoreDb ?? 0,
          snoreHours: old?.snoreHours ?? 0,
          snoreFreqHz: old?.snoreFreqHz ?? 0,
          snoreCount: old?.snoreCount ?? 0,
          noiseDb: old?.noiseDb ?? 0,
          snoreTimeline: old?.snoreTimeline ?? const [],

          // Health Connect 동기화 후에도 기존 녹음 클립 유지
          snoreAudioClips: old?.snoreAudioClips ?? const [],

          stages: stages,
        );
      }).toList();

      // history는 이미 최신 -> 과거 순으로 정렬돼 있으므로 그대로 교체한다.
      _records
        ..clear()
        ..addAll(newRecords);

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
  // Health Connect 산소포화도/호흡 데이터 불러오기
  // =========================

  Future<void> loadApneaRiskHistory({int nights = 7}) async {
    if (apneaLoading) return;

    apneaLoading = true;
    apneaError = null;
    notifyListeners();

    try {
      final service = HealthConnectService();
      apneaHistory = await service.fetchApneaRiskHistory(nights: nights);
    } catch (e) {
      apneaError = e.toString();
      apneaHistory = [];
    } finally {
      apneaLoading = false;
      notifyListeners();
    }
  }

  /// 수면 데이터와 무호흡 위험(SpO2/호흡수) 데이터를 함께 갱신한다.
  /// 수면 탭의 "Health Connect 불러오기" 버튼에서 이 함수를 호출하면 된다.
  Future<void> refreshAllHealthData({int nights = 7}) async {
    await loadHealthConnectSleep(nights: nights);
    await loadApneaRiskHistory(nights: nights);
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

    // 핵심 추가:
    // 화면에는 TOP 5만 남은 상태이고, 그 TOP 5만 서버로 업로드
    await _uploadSnoreClipsToServer(snoreResult);

    notifyListeners();
  }

  Future<void> _uploadSnoreClipsToServer(
    SnoreMeasureResult snoreResult,
  ) async {
    if (userId == null || userId!.isEmpty) {
      return;
    }

    if (snoreResult.audioClips.isEmpty) {
      return;
    }

    final aiService = AIService();

    var uploadedCount = 0;
    Object? lastError;

    for (final clip in snoreResult.audioClips) {
      try {
        final file = File(clip.path);

        if (!await file.exists()) {
          continue;
        }

        await aiService.predict(
          userId: userId!,
          wavFile: file,
        );

        uploadedCount++;
      } catch (e) {
        lastError = e;
      }
    }

    if (lastError != null) {
      snoreError = '일부 코골이 녹음 DB 저장 실패: $lastError';
      return;
    }

    if (uploadedCount > 0) {
      snoreError = null;
    }
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

        // 감지된 코골이 녹음 클립 저장
        // 여기에는 이미 10분 단위 대표 TOP 5만 들어옴
        snoreAudioClips: snoreResult.audioClips,

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

      // 새 녹음이 있으면 새 TOP 5 클립 사용, 없으면 기존 클립 유지
      snoreAudioClips: snoreResult.audioClips.isEmpty
          ? old.snoreAudioClips
          : snoreResult.audioClips,

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

  static String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

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

    // 빈 기록에서는 녹음 클립 없음
    snoreAudioClips: const [],
  );
}

// =========================
// 월별 통계
// =========================

// 임시 월별 샘플 제거.
// 월별 통계를 실제 값으로 만들려면 stats_tab.dart에서 state.records를 월별로 묶어 평균 내도록 수정해야 함.
const List<MonthlyRecord> monthlyRecords = [];
