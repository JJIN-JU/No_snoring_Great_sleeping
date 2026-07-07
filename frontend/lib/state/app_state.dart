import 'dart:async';

import 'package:flutter/material.dart';

import '../models/sleep_data.dart';
import '../services/health_connect_service.dart';
import '../theme.dart';

/// 앱 전역 상태.
/// 로그인, 날짜 이동, 수면 측정, 목표 설정, Health Connect 수면 데이터 반영을 관리한다.
class AppState extends ChangeNotifier {
  // 로그인 상태
  bool loggedIn = false;
  String userName = '홍길동';

  // 현재 보고 있는 날짜 인덱스 (0 = 가장 최근)
  int selectedIndex = 0;

  // 목표 수면 시간
  String bedtimeTarget = '23:30';
  String wakeTarget = '07:00';

  // Health Connect 상태
  bool healthLoading = false;
  String? healthError;
  DateTime? lastHealthSyncAt;

  // 실제 Health Connect 데이터만 반영한다 (목업/샘플 데이터 없음).
  final List<SleepRecord> _records = [];

  List<SleepRecord> get records => _records;
  bool get hasRecords => _records.isNotEmpty;
  SleepRecord get current => _records[selectedIndex];

  bool get canGoPrev => selectedIndex < _records.length - 1;
  bool get canGoNext => selectedIndex > 0;

  // --- 로그인 ---
  void loginWithKakao() {
    loggedIn = true;
    notifyListeners();

    // 로그인 직후 Health Connect 수면 데이터를 자동으로 동기화한다.
    loadHealthConnectSleep();
  }

  void logout() {
    loggedIn = false;
    selectedIndex = 0;
    notifyListeners();
  }

  // --- 날짜 이동 ---
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

  // --- 목표 시간 설정 ---
  void setTargets(String bedtime, String wake) {
    bedtimeTarget = bedtime;
    wakeTarget = wake;
    notifyListeners();
  }

  // --- Health Connect 수면 데이터 불러오기 (최근 며칠치) ---
  Future<void> loadHealthConnectSleep({int nights = 7}) async {
    if (healthLoading) return;

    healthLoading = true;
    healthError = null;
    notifyListeners();

    try {
      final service = HealthConnectService();
      final history = await service.fetchSleepHistory(nights: nights);

      final targetHours = _parseHours(bedtimeTarget, wakeTarget);

      // 같은 날짜의 기존 레코드가 있다면(예: 수동 측정으로 채운 코골이 값)
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
            : (old?.stages ?? <SleepStage>[]);

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

          // 코골이는 아직 Health Connect와 연동되지 않았으므로
          // 기존 값이 있으면 유지하고, 없으면 0으로 둔다 (이번 작업 범위 밖).
          avgSnoreDb: old?.avgSnoreDb ?? 0,
          maxSnoreDb: old?.maxSnoreDb ?? 0,
          snoreHours: old?.snoreHours ?? 0,
          snoreFreqHz: old?.snoreFreqHz ?? 0,
          snoreCount: old?.snoreCount ?? 0,
          noiseDb: old?.noiseDb ?? 0,
          stages: stages,
          snoreTimeline: old?.snoreTimeline ?? const [],
        );
      }).toList();

      // history는 이미 최신 -> 과거 순으로 정렬되어 있으므로 그대로 교체한다.
      _records
        ..clear()
        ..addAll(newRecords);

      selectedIndex = 0;
      lastHealthSyncAt = DateTime.now();
    } catch (e) {
      healthError = e.toString();

      // Health Connect를 아예 처음 못 불러온 경우, 빈 화면 대신
      // 0/기본값으로 채운 레코드를 넣어서 페이지 자체는 정상적으로 뜨게 한다.
      if (_records.isEmpty) {
        _records.addAll(_fallbackRecords(nights));
        selectedIndex = 0;
      }
    } finally {
      healthLoading = false;
      notifyListeners();
    }
  }

  List<SleepRecord> _fallbackRecords(int nights) {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final targetHours = _parseHours(bedtimeTarget, wakeTarget);

    return List.generate(nights, (i) {
      final date = todayMidnight.subtract(Duration(days: i));

      return SleepRecord(
        date: date,
        score: 0,
        bedtimeTarget: bedtimeTarget,
        wakeTarget: wakeTarget,
        bedtimeActual: bedtimeTarget,
        wakeActual: wakeTarget,
        totalSleepHours: 0,
        targetSleepHours: targetHours,
        avgSnoreDb: 0,
        maxSnoreDb: 0,
        snoreHours: 0,
        snoreFreqHz: 0,
        snoreCount: 0,
        noiseDb: 0,
        stages: const [],
        snoreTimeline: const [],
      );
    });
  }

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
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }
}

/// 월별 샘플 데이터
/// (통계 탭의 '월별' 보기는 이번 작업 범위 밖이라 기존 샘플을 유지한다)
const monthlyRecords = [
  MonthlyRecord('7월', 76, 6.8, 34, 1.2),
  MonthlyRecord('8월', 82, 7.2, 32, 0.8),
  MonthlyRecord('9월', 79, 7.0, 36, 1.0),
  MonthlyRecord('10월', 85, 7.4, 30, 0.6),
  MonthlyRecord('11월', 73, 6.5, 38, 1.4),
  MonthlyRecord('12월', 88, 7.6, 29, 0.4),
];
