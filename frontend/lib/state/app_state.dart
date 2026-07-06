import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/sleep_data.dart';
import '../theme.dart';

/// 앱 전역 상태. 로그인, 날짜 이동, 수면 측정, 목표 설정을 관리한다.
class AppState extends ChangeNotifier {
  // 로그인 상태
  bool loggedIn = false;
  String userName = '홍길동';

  // 현재 보고 있는 날짜 인덱스 (0 = 가장 최근)
  int selectedIndex = 0;

  // 목표 수면 시간
  String bedtimeTarget = '23:30';
  String wakeTarget = '07:00';

  // 측정 상태
  bool measuring = false;
  Duration measuredElapsed = Duration.zero;
  Timer? _timer;

  final List<SleepRecord> _records = _seedRecords();

  List<SleepRecord> get records => _records;
  SleepRecord get current => _records[selectedIndex];

  bool get canGoPrev => selectedIndex < _records.length - 1;
  bool get canGoNext => selectedIndex > 0;

  // --- 로그인 ---
  void loginWithKakao() {
    loggedIn = true;
    notifyListeners();
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

  // --- 수면 측정 ---
  void startMeasuring() {
    if (measuring) return;
    measuring = true;
    measuredElapsed = Duration.zero;
    // 데모용으로 1초 = 12분처럼 빠르게 흐르게 한다.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      measuredElapsed += const Duration(minutes: 12);
      notifyListeners();
    });
    notifyListeners();
  }

  void stopMeasuring() {
    if (!measuring) return;
    _timer?.cancel();
    measuring = false;
    _addRecordFromMeasurement();
    selectedIndex = 0;
    measuredElapsed = Duration.zero;
    notifyListeners();
  }

  void _addRecordFromMeasurement() {
    final rnd = Random();
    final hours = max(4.0, measuredElapsed.inMinutes / 60.0);
    final deep = hours * 60 * 0.22;
    final rem = hours * 60 * 0.23;
    final light = hours * 60 * 0.48;
    final awake = hours * 60 * 0.07;
    final score = (65 + rnd.nextInt(30)).clamp(0, 100);
    final target = _parseHours(bedtimeTarget, wakeTarget);

    _records.insert(
      0,
      SleepRecord(
        date: DateTime.now(),
        score: score,
        bedtimeTarget: bedtimeTarget,
        wakeTarget: wakeTarget,
        bedtimeActual: bedtimeTarget,
        wakeActual: wakeTarget,
        totalSleepHours: double.parse(hours.toStringAsFixed(1)),
        targetSleepHours: target,
        avgSnoreDb: 38 + rnd.nextInt(12).toDouble(),
        maxSnoreDb: 55 + rnd.nextInt(15).toDouble(),
        snoreHours: double.parse((rnd.nextDouble() * 2).toStringAsFixed(1)),
        snoreFreqHz: 60 + rnd.nextInt(60),
        snoreCount: 20 + rnd.nextInt(80),
        noiseDb: 30 + rnd.nextInt(10).toDouble(),
        stages: [
          SleepStage('깊은 수면', deep, AppColors.primary),
          SleepStage('렘 수면', rem, AppColors.accent),
          SleepStage('얕은 수면', light, AppColors.gold),
          SleepStage('깸', awake, AppColors.orange),
        ],
        snoreTimeline: _genTimeline(rnd),
      ),
    );
  }

  static double _parseHours(String bed, String wake) {
    final b = _toMinutes(bed);
    var w = _toMinutes(wake);
    if (w <= b) w += 24 * 60;
    return double.parse(((w - b) / 60).toStringAsFixed(1));
  }

  static int _toMinutes(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

List<SnorePoint> _genTimeline(Random rnd) {
  const times = [
    '23:30', '00:00', '00:30', '01:00', '01:30', '02:00',
    '02:30', '03:00', '03:30', '04:00', '04:30', '05:00',
    '05:30', '06:00', '06:30',
  ];
  return times
      .map((t) => SnorePoint(t, 25 + rnd.nextInt(45).toDouble()))
      .toList();
}

/// 초기 샘플 데이터 (최근 7일)
List<SleepRecord> _seedRecords() {
  final now = DateTime.now();
  final stages1 = [
    const SleepStage('깊은 수면', 95, AppColors.primary),
    const SleepStage('렘 수면', 105, AppColors.accent),
    const SleepStage('얕은 수면', 210, AppColors.gold),
    const SleepStage('깸', 25, AppColors.orange),
  ];

  const timeline = [
    SnorePoint('23:30', 30),
    SnorePoint('00:00', 42),
    SnorePoint('00:30', 55),
    SnorePoint('01:00', 48),
    SnorePoint('01:30', 62),
    SnorePoint('02:00', 58),
    SnorePoint('02:30', 70),
    SnorePoint('03:00', 45),
    SnorePoint('03:30', 38),
    SnorePoint('04:00', 52),
    SnorePoint('04:30', 60),
    SnorePoint('05:00', 40),
    SnorePoint('05:30', 33),
    SnorePoint('06:00', 28),
    SnorePoint('06:30', 25),
  ];

  final scores = [88, 92, 74, 81, 67, 95, 79];
  final sleep = [7.1, 7.8, 6.2, 6.9, 5.5, 8.0, 6.7];
  final beds = ['23:40', '23:10', '00:20', '23:55', '01:10', '22:50', '00:05'];
  final wakes = ['06:50', '07:00', '06:40', '06:55', '06:45', '07:00', '06:50'];

  return List.generate(7, (i) {
    final total = sleep[i];
    return SleepRecord(
      date: now.subtract(Duration(days: i)),
      score: scores[i],
      bedtimeTarget: '23:30',
      wakeTarget: '07:00',
      bedtimeActual: beds[i],
      wakeActual: wakes[i],
      totalSleepHours: total,
      targetSleepHours: 7.5,
      avgSnoreDb: 36 + (i * 2).toDouble(),
      maxSnoreDb: 58 + i.toDouble(),
      snoreHours: 0.8 + (i % 3) * 0.6,
      snoreFreqHz: 70 + i * 6,
      snoreCount: 30 + i * 9,
      noiseDb: 32 + (i % 4).toDouble(),
      stages: stages1
          .map((s) => SleepStage(
                s.name,
                s.minutes * (total / 7.4),
                s.color,
              ))
          .toList(),
      snoreTimeline: timeline,
    );
  });
}

/// 월별 샘플 데이터
const monthlyRecords = [
  MonthlyRecord('7월', 76, 6.8, 34, 1.2),
  MonthlyRecord('8월', 82, 7.2, 32, 0.8),
  MonthlyRecord('9월', 79, 7.0, 36, 1.0),
  MonthlyRecord('10월', 85, 7.4, 30, 0.6),
  MonthlyRecord('11월', 73, 6.5, 38, 1.4),
  MonthlyRecord('12월', 88, 7.6, 29, 0.4),
];
