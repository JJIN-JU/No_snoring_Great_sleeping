import 'package:health/health.dart';
import 'package:flutter/foundation.dart';

class HealthSleepStage {
  final String name;
  final double minutes;

  const HealthSleepStage({
    required this.name,
    required this.minutes,
  });
}

class HealthSleepSummary {
  final DateTime date; // 이 밤이 속한 날짜 (기상일 기준 자정)
  final DateTime? bedtime;
  final DateTime? wakeTime;
  final double totalSleepMinutes;
  final List<HealthSleepStage> stages;

  const HealthSleepSummary({
    required this.date,
    required this.bedtime,
    required this.wakeTime,
    required this.totalSleepMinutes,
    required this.stages,
  });
}

class HealthConnectService {
  final Health _health = Health();

  final List<HealthDataType> _sleepTypes = const [
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_AWAKE,
  ];

  Future<bool> requestSleepPermission() async {
    await _health.configure();

    final granted = await _health.requestAuthorization(
      _sleepTypes,
      permissions: _sleepTypes.map((type) => HealthDataAccess.READ).toList(),
    );

    return granted;
  }

  /// 어젯밤 하루치만 필요할 때 쓰는 편의 메서드.
  /// 내부적으로 [fetchSleepHistory]의 1일치 결과를 그대로 반환한다.
  Future<HealthSleepSummary> fetchLastNightSleep() async {
    final history = await fetchSleepHistory(nights: 1);
    return history.first;
  }

  /// 최근 [nights]일치 수면 데이터를 하루 단위로 묶어서 반환한다.
  /// 반환 리스트의 index 0 = 가장 최근 밤(어젯밤), index 1 = 그 하루 전... 순서.
  Future<List<HealthSleepSummary>> fetchSleepHistory({int nights = 7}) async {
    await _health.configure();

    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);

    // 각 "밤"은 전날 18시 ~ 당일 12시로 정의한다 (자정 넘어 잔 수면 포함).
    // 조회는 가장 오래된 밤의 시작부터 가장 최근 밤의 끝까지 한 번에 수행한다.
    final overallStart =
        todayMidnight.subtract(Duration(days: nights - 1, hours: 6));
    final overallEnd = todayMidnight.add(const Duration(hours: 12));

    final granted = await requestSleepPermission();

    if (!granted) {
      throw Exception('Health Connect 수면 권한이 허용되지 않았습니다.');
    }

    final now = DateTime.now();

    // 기존: 어제 18시 ~ 오늘 12시
    // 변경: 최근 30일 전체 조회
    final start = now.subtract(const Duration(days: 30));
    final end = now.add(const Duration(minutes: 1));

    var points = await _health.getHealthDataFromTypes(
      types: _sleepTypes,
      startTime: overallStart,
      endTime: overallEnd,
    );

    points = _health.removeDuplicates(points);

    final results = <HealthSleepSummary>[];

    for (var i = 0; i < nights; i++) {
      final targetMidnight = todayMidnight.subtract(Duration(days: i));
      final nightStart = targetMidnight.subtract(const Duration(hours: 6));
      final nightEnd = targetMidnight.add(const Duration(hours: 12));

      final nightPoints = points
          .where((p) =>
              p.dateFrom.isBefore(nightEnd) && p.dateTo.isAfter(nightStart))
          .toList();

      results.add(_summarize(targetMidnight, nightPoints));
    }

    return results;
  }

  HealthSleepSummary _summarize(
    DateTime date,
    List<HealthDataPoint> points,
  ) {
    DateTime? bedtime;
    DateTime? wakeTime;

    double sessionMinutes = 0;
    double asleepMinutes = 0;
    double lightMinutes = 0;
    double deepMinutes = 0;
    double remMinutes = 0;
    double awakeMinutes = 0;

    for (final point in relatedPoints) {
      final minutes = _overlapMinutes(
        point.dateFrom,
        point.dateTo,
        windowStart,
        windowEnd,
      );

      if (minutes <= 0) continue;

      bedtime ??= point.dateFrom;
      if (point.dateFrom.isBefore(bedtime!)) {
        bedtime = point.dateFrom;
      }

      wakeTime ??= point.dateTo;
      if (point.dateTo.isAfter(wakeTime!)) {
        wakeTime = point.dateTo;
      }

      switch (point.type) {
        case HealthDataType.SLEEP_SESSION:
          sessionMinutes += minutes;
          break;

        case HealthDataType.SLEEP_ASLEEP:
          asleepMinutes += minutes;
          break;

        case HealthDataType.SLEEP_LIGHT:
          lightMinutes += minutes;
          break;

        case HealthDataType.SLEEP_DEEP:
          deepMinutes += minutes;
          break;

        case HealthDataType.SLEEP_REM:
          remMinutes += minutes;
          break;

        case HealthDataType.SLEEP_AWAKE:
          awakeMinutes += minutes;
          break;

        default:
          break;
      }
    }

    // SLEEP_SESSION이 있으면 취침/기상은 세션 기준으로 고정
    if (sessionPoints.isNotEmpty) {
      bedtime = windowStart;
      wakeTime = windowEnd;
    }

    final stages = <HealthSleepStage>[
      HealthSleepStage(name: '깊은 수면', minutes: deepMinutes),
      HealthSleepStage(name: 'REM 수면', minutes: remMinutes),
      HealthSleepStage(name: '얕은 수면', minutes: lightMinutes),
      HealthSleepStage(name: '깸', minutes: awakeMinutes),
    ].where((stage) => stage.minutes > 0).toList();

    final stageTotal = stages.fold<double>(
      0,
      (sum, stage) => sum + stage.minutes,
    );

    final totalSleepMinutes = stageTotal > 0
        ? stageTotal
        : asleepMinutes > 0
            ? asleepMinutes
            : sessionMinutes;

    if (totalSleepMinutes <= 0) {
      throw Exception(
        'Health Connect에서 수면 기록은 찾았지만 수면 시간이 0분으로 조회됐습니다.',
      );
    }

    return HealthSleepSummary(
      date: date,
      bedtime: bedtime,
      wakeTime: wakeTime,
      totalSleepMinutes: totalSleepMinutes,
      stages: stages,
    );
  }

  bool _overlaps(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) {
    return aStart.isBefore(bEnd) && aEnd.isAfter(bStart);
  }

  double _overlapMinutes(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) {
    final start = _maxDate(aStart, bStart);
    final end = _minDate(aEnd, bEnd);

    if (!end.isAfter(start)) {
      return 0;
    }

    return end.difference(start).inMinutes.toDouble();
  }

  DateTime _maxDate(DateTime a, DateTime b) {
    return a.isAfter(b) ? a : b;
  }

  DateTime _minDate(DateTime a, DateTime b) {
    return a.isBefore(b) ? a : b;
  }
}
