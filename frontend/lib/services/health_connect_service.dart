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
  final DateTime date; // 이 밤이 속한 날짜 (기상일 기준)
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

  /// 가장 최근 하룻밤만 필요할 때 쓰는 편의 메서드.
  /// 내부적으로 [fetchSleepHistory]의 1일치 결과를 그대로 반환한다.
  Future<HealthSleepSummary> fetchLastNightSleep() async {
    final history = await fetchSleepHistory(nights: 1);
    return history.first;
  }

  /// 최근 [nights]일치 수면 데이터를 밤 단위로 찾아 리스트로 반환한다.
  /// index 0 = 가장 최근 밤, index 1 = 그 전날 밤 ... 순서.
  /// Health Connect에 실제로 기록된 밤의 개수가 [nights]보다 적으면
  /// 찾은 만큼만 반환한다 (예외를 던지지 않음 — 개별 밤이 아니라
  /// "Health Connect 자체에 데이터가 전혀 없는 경우"에만 예외를 던진다).
  Future<List<HealthSleepSummary>> fetchSleepHistory({int nights = 7}) async {
    await _health.configure();

    final granted = await requestSleepPermission();

    if (!granted) {
      throw Exception('Health Connect 수면 권한이 허용되지 않았습니다.');
    }

    final now = DateTime.now();

    // 밤 개수(nights)보다 넉넉하게 과거로 조회한다.
    // (하루 이틀 측정이 비어있는 경우를 대비해 +7일 여유를 둔다)
    final start = now.subtract(Duration(days: nights + 7));
    final end = now.add(const Duration(minutes: 1));

    var points = await _health.getHealthDataFromTypes(
      types: _sleepTypes,
      startTime: start,
      endTime: end,
    );

    points = _health.removeDuplicates(points);

    if (points.isEmpty) {
      throw Exception(
        '최근 Health Connect에 수면 데이터가 없습니다. 삼성 헬스에서 Health Connect 동기화를 먼저 확인해 주세요.',
      );
    }

    // 가장 최근 순으로 정렬된 SLEEP_SESSION 목록
    final sessionPoints = points
        .where((point) => point.type == HealthDataType.SLEEP_SESSION)
        .toList()
      ..sort((a, b) => b.dateTo.compareTo(a.dateTo));

    final windows = <_SleepWindow>[];

    if (sessionPoints.isNotEmpty) {
      for (final session in sessionPoints) {
        if (windows.length >= nights) break;

        // 이미 잡힌 밤(window)과 겹치면 같은 밤이므로 건너뛴다.
        final alreadyCaptured = windows.any(
          (w) => _overlaps(session.dateFrom, session.dateTo, w.start, w.end),
        );
        if (alreadyCaptured) continue;

        windows.add(_SleepWindow(session.dateFrom, session.dateTo));
      }
    } else {
      // SLEEP_SESSION이 전혀 없으면, 가장 최근 포인트 기준으로
      // 창(window) 1개만 추정한다 (여러 밤을 정확히 나눌 근거가 없음).
      final sorted = [...points]..sort((a, b) => b.dateTo.compareTo(a.dateTo));
      final latest = sorted.first;

      windows.add(
        _SleepWindow(
          latest.dateTo.subtract(const Duration(hours: 18)),
          latest.dateTo,
        ),
      );
    }

    if (windows.isEmpty) {
      throw Exception('최근 수면 기록을 찾았지만 세부 데이터를 불러오지 못했습니다.');
    }

    return windows
        .map(
          (w) => _summarizeWindow(
            w.start,
            w.end,
            points,
            hasSession: sessionPoints.isNotEmpty,
          ),
        )
        .toList();
  }

  HealthSleepSummary _summarizeWindow(
    DateTime windowStart,
    DateTime windowEnd,
    List<HealthDataPoint> points, {
    required bool hasSession,
  }) {
    final relatedPoints = points.where((point) {
      return _overlaps(point.dateFrom, point.dateTo, windowStart, windowEnd);
    }).toList();

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

    // SLEEP_SESSION 기준으로 창이 정의된 경우, 취침/기상 시간은 세션 그대로 고정
    if (hasSession) {
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

    // 이 밤을 어느 날짜로 표시할지는 기상 시각(wakeTime) 기준으로 정한다.
    final refDate = wakeTime ?? windowEnd;

    return HealthSleepSummary(
      date: DateTime(refDate.year, refDate.month, refDate.day),
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

class _SleepWindow {
  final DateTime start;
  final DateTime end;
  const _SleepWindow(this.start, this.end);
}
