import 'package:flutter/foundation.dart';
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

/// 하루치 산소포화도/호흡 관련 요약.
/// 의료 진단이 아닌 참고용 데이터임에 유의.
class ApneaRiskSummary {
  final DateTime date;
  final double? avgSpO2;
  final double? minSpO2;
  final int lowSpO2Events; // 기준치 미만으로 떨어진 측정 횟수
  final double? avgRespiratoryRate;
  final double? avgHeartRate;
  final bool hasData;

  const ApneaRiskSummary({
    required this.date,
    required this.avgSpO2,
    required this.minSpO2,
    required this.lowSpO2Events,
    required this.avgRespiratoryRate,
    required this.avgHeartRate,
    required this.hasData,
  });

  factory ApneaRiskSummary.empty(DateTime date) {
    return ApneaRiskSummary(
      date: date,
      avgSpO2: null,
      minSpO2: null,
      lowSpO2Events: 0,
      avgRespiratoryRate: null,
      avgHeartRate: null,
      hasData: false,
    );
  }

  /// 참고용 위험도 표시. 의학적 진단이 아님.
  String get riskLevel {
    if (!hasData) return '데이터 없음';
    if (lowSpO2Events == 0) return '낮음';
    if (lowSpO2Events <= 3) return '주의';
    return '높음';
  }
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

  final List<HealthDataType> _apneaTypes = const [
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.RESPIRATORY_RATE,
    HealthDataType.HEART_RATE,
  ];

  /// 낮은 산소포화도로 간주하는 기준값 (참고용, 임상 기준 아님).
  static const double lowSpO2Threshold = 90.0;

  Future<bool> requestSleepPermission() async {
    await _health.configure();

    final granted = await _health.requestAuthorization(
      _sleepTypes,
      permissions: _sleepTypes.map((type) => HealthDataAccess.READ).toList(),
    );

    return granted;
  }

  Future<bool> requestApneaPermission() async {
    await _health.configure();

    final granted = await _health.requestAuthorization(
      _apneaTypes,
      permissions: _apneaTypes.map((type) => HealthDataAccess.READ).toList(),
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
    final start = now.subtract(Duration(days: nights + 23));
    final end = now.add(const Duration(minutes: 1));

    var points = await _health.getHealthDataFromTypes(
      types: _sleepTypes,
      startTime: start,
      endTime: end,
    );

    points = _health.removeDuplicates(points);

    // 수면 세션은 들어오는데 단계만 비는 문제를 확인하기 위한 타입별 로그.
    final typeCounts = <HealthDataType, int>{};

    for (final point in points) {
      typeCounts.update(
        point.type,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    debugPrint(
      'Health Connect 수면 데이터 타입별 개수: '
      '${typeCounts.entries.map((e) => '${e.key.name}=${e.value}').join(', ')}',
    );

    if (points.isEmpty) {
      throw Exception(
        '최근 30일간 Health Connect에 수면 데이터가 없습니다. 삼성 헬스에서 Health Connect 동기화를 먼저 확인해 주세요.',
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

  /// 최근 [nights]일치 산소포화도/호흡수 데이터를,
  /// [fetchSleepHistory]가 찾은 수면 창(window)에 맞춰 요약해서 반환한다.
  /// 수면 기록 자체를 먼저 찾고, 그 시간대에 겹치는 SpO2/호흡수만 집계하는 방식.
  Future<List<ApneaRiskSummary>> fetchApneaRiskHistory({int nights = 7}) async {
    await _health.configure();

    // 먼저 수면 창을 알아야 그 구간의 SpO2를 집계할 수 있다.
    List<HealthSleepSummary> sleepSummaries;

    try {
      sleepSummaries = await fetchSleepHistory(nights: nights);
    } catch (_) {
      // 수면 기록 자체가 없으면 산소포화도도 의미 있게 묶을 수 없음
      return [];
    }

    final granted = await requestApneaPermission();

    if (!granted) {
      return sleepSummaries.map((s) => ApneaRiskSummary.empty(s.date)).toList();
    }

    final now = DateTime.now();
    final start = now.subtract(Duration(days: nights + 7));
    final end = now.add(const Duration(minutes: 1));

    var points = await _health.getHealthDataFromTypes(
      types: _apneaTypes,
      startTime: start,
      endTime: end,
    );

    points = _health.removeDuplicates(points);

    return sleepSummaries.map((sleep) {
      if (sleep.bedtime == null || sleep.wakeTime == null) {
        return ApneaRiskSummary.empty(sleep.date);
      }

      final relatedPoints = points.where((p) {
        return _overlaps(p.dateFrom, p.dateTo, sleep.bedtime!, sleep.wakeTime!);
      }).toList();

      return _summarizeApnea(sleep.date, relatedPoints);
    }).toList();
  }

  ApneaRiskSummary _summarizeApnea(
    DateTime date,
    List<HealthDataPoint> points,
  ) {
    final spo2Values = <double>[];
    final respRateValues = <double>[];
    final heartRateValues = <double>[];

    for (final point in points) {
      final value = point.value;

      if (value is! NumericHealthValue) continue;

      final numeric = value.numericValue.toDouble();

      if (point.type == HealthDataType.BLOOD_OXYGEN) {
        spo2Values.add(numeric);
      } else if (point.type == HealthDataType.RESPIRATORY_RATE) {
        respRateValues.add(numeric);
      } else if (point.type == HealthDataType.HEART_RATE) {
        heartRateValues.add(numeric);
      }
    }

    if (spo2Values.isEmpty &&
        respRateValues.isEmpty &&
        heartRateValues.isEmpty) {
      return ApneaRiskSummary.empty(date);
    }

    double? avgSpO2;
    double? minSpO2;
    var lowSpO2Events = 0;

    if (spo2Values.isNotEmpty) {
      avgSpO2 = spo2Values.reduce((a, b) => a + b) / spo2Values.length;
      minSpO2 = spo2Values.reduce((a, b) => a < b ? a : b);
      lowSpO2Events = spo2Values.where((v) => v < lowSpO2Threshold).length;
    }

    double? avgRespRate;

    if (respRateValues.isNotEmpty) {
      avgRespRate =
          respRateValues.reduce((a, b) => a + b) / respRateValues.length;
    }

    double? avgHeartRate;

    if (heartRateValues.isNotEmpty) {
      avgHeartRate =
          heartRateValues.reduce((a, b) => a + b) / heartRateValues.length;
    }

    return ApneaRiskSummary(
      date: date,
      avgSpO2: avgSpO2,
      minSpO2: minSpO2,
      lowSpO2Events: lowSpO2Events,
      avgRespiratoryRate: avgRespRate,
      avgHeartRate: avgHeartRate,
      hasData: true,
    );
  }

  HealthSleepSummary _summarizeWindow(
    DateTime windowStart,
    DateTime windowEnd,
    List<HealthDataPoint> points, {
    required bool hasSession,
  }) {
    // 삼성헬스의 수면 단계 포인트가 SLEEP_SESSION 경계보다
    // 수 분~수십 분 바깥으로 기록되는 경우가 있어 단계 데이터만
    // 앞뒤 90분의 여유 범위에서 다시 포함한다.
    final stageWindowStart = windowStart.subtract(
      const Duration(minutes: 90),
    );
    final stageWindowEnd = windowEnd.add(
      const Duration(minutes: 90),
    );

    final relatedPoints = points.where((point) {
      final isDetailedStage = point.type == HealthDataType.SLEEP_ASLEEP ||
          point.type == HealthDataType.SLEEP_LIGHT ||
          point.type == HealthDataType.SLEEP_DEEP ||
          point.type == HealthDataType.SLEEP_REM ||
          point.type == HealthDataType.SLEEP_AWAKE;

      if (isDetailedStage) {
        return _overlaps(
          point.dateFrom,
          point.dateTo,
          stageWindowStart,
          stageWindowEnd,
        );
      }

      return _overlaps(
        point.dateFrom,
        point.dateTo,
        windowStart,
        windowEnd,
      );
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
      final isDetailedStage = point.type == HealthDataType.SLEEP_ASLEEP ||
          point.type == HealthDataType.SLEEP_LIGHT ||
          point.type == HealthDataType.SLEEP_DEEP ||
          point.type == HealthDataType.SLEEP_REM ||
          point.type == HealthDataType.SLEEP_AWAKE;

      final minutes = _overlapMinutes(
        point.dateFrom,
        point.dateTo,
        isDetailedStage ? stageWindowStart : windowStart,
        isDetailedStage ? stageWindowEnd : windowEnd,
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

    debugPrint(
      '수면 요약 ${refDate.year}-${refDate.month}-${refDate.day}: '
      'session=${sessionMinutes.toStringAsFixed(1)}분, '
      'asleep=${asleepMinutes.toStringAsFixed(1)}분, '
      'light=${lightMinutes.toStringAsFixed(1)}분, '
      'deep=${deepMinutes.toStringAsFixed(1)}분, '
      'rem=${remMinutes.toStringAsFixed(1)}분, '
      'awake=${awakeMinutes.toStringAsFixed(1)}분',
    );

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
    return !aStart.isAfter(bEnd) && !aEnd.isBefore(bStart);
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
