import 'package:health/health.dart';

class HealthSleepStage {
  final String name;
  final double minutes;

  const HealthSleepStage({
    required this.name,
    required this.minutes,
  });
}

class HealthSleepSummary {
  final DateTime? bedtime;
  final DateTime? wakeTime;
  final double totalSleepMinutes;
  final List<HealthSleepStage> stages;

  const HealthSleepSummary({
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
      permissions: _sleepTypes
          .map((type) => HealthDataAccess.READ)
          .toList(),
    );

    return granted;
  }

  Future<HealthSleepSummary> fetchLastNightSleep() async {
    await _health.configure();

    final granted = await requestSleepPermission();

    if (!granted) {
      throw Exception('Health Connect 수면 권한이 허용되지 않았습니다.');
    }

    final now = DateTime.now();

    // 최근 30일 전체 조회
    final start = now.subtract(const Duration(days: 30));
    final end = now.add(const Duration(minutes: 1));

    var points = await _health.getHealthDataFromTypes(
      types: _sleepTypes,
      startTime: start,
      endTime: end,
    );

    points = _health.removeDuplicates(points);

    if (points.isEmpty) {
      throw Exception(
        '최근 30일 Health Connect에 수면 데이터가 없습니다. 삼성 헬스에서 Health Connect 동기화를 먼저 확인해 주세요.',
      );
    }

    // 가장 최근 수면 세션 찾기
    final sessionPoints = points
        .where((point) => point.type == HealthDataType.SLEEP_SESSION)
        .toList();

    DateTime windowStart;
    DateTime windowEnd;

    if (sessionPoints.isNotEmpty) {
      sessionPoints.sort((a, b) => b.dateTo.compareTo(a.dateTo));

      final latestSession = sessionPoints.first;

      windowStart = latestSession.dateFrom;
      windowEnd = latestSession.dateTo;
    } else {
      // SLEEP_SESSION이 없으면 가장 최근 수면 단계 기준으로 묶기
      final sortedPoints = [...points]
        ..sort((a, b) => b.dateTo.compareTo(a.dateTo));

      final latestPoint = sortedPoints.first;

      windowEnd = latestPoint.dateTo;
      windowStart = windowEnd.subtract(const Duration(hours: 18));
    }

    final relatedPoints = points.where((point) {
      return _overlaps(
        point.dateFrom,
        point.dateTo,
        windowStart,
        windowEnd,
      );
    }).toList();

    if (relatedPoints.isEmpty) {
      throw Exception(
        '최근 수면 기록을 찾았지만 세부 데이터를 불러오지 못했습니다.',
      );
    }

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

    // SLEEP_SESSION이 있으면 취침/기상 시간은 세션 기준으로 고정
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