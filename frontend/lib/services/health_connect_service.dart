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

    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);

    // 어제 18시 ~ 오늘 12시
    // 자정 넘어서 잔 수면을 잡기 위한 범위
    final start = todayMidnight.subtract(const Duration(hours: 6));
    final end = todayMidnight.add(const Duration(hours: 12));

    final granted = await requestSleepPermission();

    if (!granted) {
      throw Exception('Health Connect 수면 권한이 허용되지 않았습니다.');
    }

    var points = await _health.getHealthDataFromTypes(
      types: _sleepTypes,
      startTime: start,
      endTime: end,
    );

    points = _health.removeDuplicates(points);

    DateTime? bedtime;
    DateTime? wakeTime;

    double sessionMinutes = 0;
    double asleepMinutes = 0;
    double lightMinutes = 0;
    double deepMinutes = 0;
    double remMinutes = 0;
    double awakeMinutes = 0;

    for (final point in points) {
      final minutes =
          point.dateTo.difference(point.dateFrom).inMinutes.toDouble();

      if (minutes <= 0) continue;

      bedtime ??= point.dateFrom;
      if (point.dateFrom.isBefore(bedtime)) {
        bedtime = point.dateFrom;
      }

      wakeTime ??= point.dateTo;
      if (point.dateTo.isAfter(wakeTime)) {
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

    return HealthSleepSummary(
      bedtime: bedtime,
      wakeTime: wakeTime,
      totalSleepMinutes: totalSleepMinutes,
      stages: stages,
    );
  }
}