import 'dart:math' as math;

import '../models/sleep_data.dart';
import '../models/sleep_tag_result.dart';

class SleepTagAnalysisService {
  const SleepTagAnalysisService._();

  /// 실행일을 포함한 최근 7일을 분석한다.
  ///
  /// 예:
  /// 실행일이 2026.07.20이라면
  /// 분석 기간은 2026.07.14 ~ 2026.07.20이다.
  static SleepTagAnalysis analyze(
    List<SleepRecord> records, {
    DateTime? referenceDate,
  }) {
    final today = _dateOnly(
      referenceDate ?? DateTime.now(),
    );

    final periodEnd = today;

    final periodStart = today.subtract(
      const Duration(days: 6),
    );

    /*
     * 최근 7일 범위에 포함되는 기록만 가져온다.
     *
     * 동일 날짜 기록이 여러 개 들어온 경우
     * 정렬 후 가장 최신 기록 하나만 사용한다.
     */
    final sortedRecords = records.where((record) {
      final recordDate = _dateOnly(record.date);

      return !recordDate.isBefore(periodStart) &&
          !recordDate.isAfter(periodEnd);
    }).toList()
      ..sort(
        (a, b) => b.date.compareTo(a.date),
      );

    final recordsByDate = <String, SleepRecord>{};

    for (final record in sortedRecords) {
      final dateKey = _dateKey(record.date);

      recordsByDate.putIfAbsent(
        dateKey,
        () => record,
      );
    }

    final recentRecords =
        recordsByDate.values.toList()
          ..sort(
            (a, b) => b.date.compareTo(a.date),
          );

    if (recentRecords.isEmpty) {
      return _emptyAnalysis(
        periodStart: periodStart,
        periodEnd: periodEnd,
      );
    }

    final sleepRecords = recentRecords.where((record) {
      return _isValidDouble(
            record.totalSleepHours,
          ) &&
          record.totalSleepHours > 0;
    }).toList();

    final snoreRecords = recentRecords.where((record) {
      return record.snoreCount > 0 ||
          record.snoreHours > 0 ||
          record.avgSnoreDb > 0;
    }).toList();

    final averageSleepHours = _average(
      sleepRecords.map(
        (record) => record.totalSleepHours,
      ),
    );

    final averageTargetSleepHours = _average(
      sleepRecords
          .where(
            (record) =>
                record.targetSleepHours > 0,
          )
          .map(
            (record) =>
                record.targetSleepHours,
          ),
    );

    final bedtimeMinutes = sleepRecords
        .map(
          (record) => _parseClockMinutes(
            record.bedtimeActual,
            isBedtime: true,
          ),
        )
        .whereType<int>()
        .toList();

    final wakeMinutes = sleepRecords
        .map(
          (record) => _parseClockMinutes(
            record.wakeActual,
            isBedtime: false,
          ),
        )
        .whereType<int>()
        .toList();

    final averageBedtimeMinutes =
        bedtimeMinutes.isEmpty
            ? null
            : _averageInt(bedtimeMinutes);

    final averageWakeMinutes =
        wakeMinutes.isEmpty
            ? null
            : _averageInt(wakeMinutes);

    final averageBedtime =
        averageBedtimeMinutes == null
            ? '--:--'
            : _formatClock(
                averageBedtimeMinutes,
              );

    final averageWakeTime =
        averageWakeMinutes == null
            ? '--:--'
            : _formatClock(
                averageWakeMinutes,
              );

    final totalSnoreCount =
        snoreRecords.fold<int>(
      0,
      (sum, record) =>
          sum + record.snoreCount,
    );

    final totalSnoreHours =
        snoreRecords.fold<double>(
      0,
      (sum, record) {
        if (!_isValidDouble(
          record.snoreHours,
        )) {
          return sum;
        }

        return sum + record.snoreHours;
      },
    );

    final snoreRatios = recentRecords
        .where(
          (record) =>
              record.totalSleepHours > 0 &&
              record.snoreHours > 0 &&
              _isValidDouble(
                record.totalSleepHours,
              ) &&
              _isValidDouble(
                record.snoreHours,
              ),
        )
        .map((record) {
          final ratio =
              record.snoreHours /
                  record.totalSleepHours *
                  100;

          return ratio
              .clamp(0, 100)
              .toDouble();
        });

    final averageSnoreRatio = _average(
      snoreRatios,
    );

    final tags = <SleepTagResult>[];

    if (sleepRecords.length >= 3) {
      _addSleepShortageTag(
        tags: tags,
        sleepRecords: sleepRecords,
        averageSleepHours:
            averageSleepHours,
        averageTargetSleepHours:
            averageTargetSleepHours,
      );

      _addNightOwlTag(
        tags: tags,
        bedtimeMinutes: bedtimeMinutes,
        averageBedtimeMinutes:
            averageBedtimeMinutes,
      );

      _addWeekendOversleepTag(
        tags: tags,
        sleepRecords: sleepRecords,
      );
    }

    if (recentRecords.length >= 3) {
      _addSnoreTag(
        tags: tags,
        recentRecords: recentRecords,
        snoreRecords: snoreRecords,
        totalSnoreCount: totalSnoreCount,
        totalSnoreHours: totalSnoreHours,
        averageSnoreRatio:
            averageSnoreRatio,
      );
    }

    if (recentRecords.length < 3) {
      tags.add(
        SleepTagResult(
          name: '분석 데이터 부족',
          description:
              '현재 기록만으로는 반복적인 수면 패턴을 판단하기 어렵습니다.',
          severity:
              SleepTagSeverity.caution,
          evidence: [
            '최근 7일 중 분석 가능 기록: '
                '${recentRecords.length}일',
            '수면 패턴 분석 권장 기록: '
                '최소 3일 이상',
            '수면 데이터가 추가되면 '
                '다시 분석할 수 있습니다.',
          ],
        ),
      );
    } else if (tags.isEmpty) {
      tags.add(
        SleepTagResult(
          name: '안정적인 수면 패턴',
          description:
              '최근 7일 기록에서 크게 관리가 필요한 수면 패턴이 발견되지 않았습니다.',
          severity:
              SleepTagSeverity.good,
          evidence: [
            '최근 평균 수면 시간: '
                '${_formatHours(averageSleepHours)}',
            '최근 평균 취침 시간: '
                '${_formatKoreanClock(averageBedtime)}',
            '반복적인 코골이 주의 패턴이 '
                '확인되지 않았습니다.',
          ],
        ),
      );
    }

    final overallSeverity =
        _getOverallSeverity(tags);

    final overallStatus =
        _getOverallStatus(
      overallSeverity,
    );

    return SleepTagAnalysis(
      periodStart: periodStart,
      periodEnd: periodEnd,
      sourceRecordCount:
          recentRecords.length,
      sleepRecordCount:
          sleepRecords.length,
      snoreRecordCount:
          snoreRecords.length,
      averageSleepHours:
          averageSleepHours,
      averageTargetSleepHours:
          averageTargetSleepHours,
      averageBedtime: averageBedtime,
      averageWakeTime: averageWakeTime,
      snoreDays: snoreRecords.length,
      totalSnoreCount: totalSnoreCount,
      totalSnoreHours: totalSnoreHours,
      averageSnoreRatio:
          averageSnoreRatio,
      overallStatus: overallStatus,
      overallSeverity: overallSeverity,
      summary:
          '실행일을 포함한 최근 7일의 수면 및 코골이 기록을 바탕으로 AI 맞춤 분석을 준비하고 있습니다.',
      tags: tags,
      weeklyGoals: const [],
      cautionNote:
          '본 분석은 수면 습관 관리를 위한 참고 정보이며 의료 진단을 대신하지 않습니다.',
    );
  }

  static void _addSleepShortageTag({
    required List<SleepTagResult> tags,
    required List<SleepRecord>
        sleepRecords,
    required double averageSleepHours,
    required double
        averageTargetSleepHours,
  }) {
    if (averageTargetSleepHours <= 0) {
      return;
    }

    final averageDeficit = math.max(
      0.0,
      averageTargetSleepHours -
          averageSleepHours,
    ).toDouble();

    final shortageDays =
        sleepRecords.where((record) {
      if (record.targetSleepHours <= 0) {
        return false;
      }

      return record.totalSleepHours +
              0.25 <
          record.targetSleepHours;
    }).length;

    final requiredDays = math.max(
      2,
      (sleepRecords.length / 2).ceil(),
    );

    if (averageDeficit < 0.5 &&
        shortageDays < requiredDays) {
      return;
    }

    final severity =
        averageDeficit >= 1.5
            ? SleepTagSeverity.attention
            : SleepTagSeverity.caution;

    tags.add(
      SleepTagResult(
        name: '수면 부족',
        description:
            '설정한 목표 수면 시간보다 실제 수면 시간이 짧은 날이 반복되었습니다.',
        severity: severity,
        evidence: [
          '평균 목표 수면: '
              '${_formatHours(averageTargetSleepHours)}',
          '실제 평균 수면: '
              '${_formatHours(averageSleepHours)}',
          '하루 평균 부족: '
              '${_formatHours(averageDeficit)}',
          '목표 수면 미달: '
              '${sleepRecords.length}일 중 '
              '$shortageDays일',
        ],
      ),
    );
  }

  static void _addNightOwlTag({
    required List<SleepTagResult> tags,
    required List<int> bedtimeMinutes,
    required int?
        averageBedtimeMinutes,
  }) {
    if (averageBedtimeMinutes == null ||
        bedtimeMinutes.length < 3) {
      return;
    }

    final afterMidnightCount =
        bedtimeMinutes.where((minutes) {
      return minutes >= 24 * 60;
    }).length;

    final requiredCount =
        (bedtimeMinutes.length / 2).ceil();

    if (averageBedtimeMinutes <
            24 * 60 ||
        afterMidnightCount <
            requiredCount) {
      return;
    }

    final latestBedtime =
        bedtimeMinutes.reduce(
      (a, b) => a > b ? a : b,
    );

    final severity =
        averageBedtimeMinutes >=
                26 * 60
            ? SleepTagSeverity.attention
            : SleepTagSeverity.caution;

    tags.add(
      SleepTagResult(
        name: '야행성',
        description:
            '자정 이후 잠드는 수면 패턴이 최근 기록에서 반복적으로 나타났습니다.',
        severity: severity,
        evidence: [
          '평균 취침 시간: '
              '${_formatKoreanClock(
                _formatClock(
                  averageBedtimeMinutes,
                ),
              )}',
          '자정 이후 취침: '
              '${bedtimeMinutes.length}일 중 '
              '$afterMidnightCount일',
          '가장 늦은 취침: '
              '${_formatKoreanClock(
                _formatClock(
                  latestBedtime,
                ),
              )}',
        ],
      ),
    );
  }

  static void _addWeekendOversleepTag({
    required List<SleepTagResult> tags,
    required List<SleepRecord>
        sleepRecords,
  }) {
    final weekdayWakeMinutes = <int>[];
    final weekendWakeMinutes = <int>[];

    for (final record in sleepRecords) {
      final minutes = _parseClockMinutes(
        record.wakeActual,
        isBedtime: false,
      );

      if (minutes == null) {
        continue;
      }

      final isWeekend =
          record.date.weekday ==
                  DateTime.saturday ||
              record.date.weekday ==
                  DateTime.sunday;

      if (isWeekend) {
        weekendWakeMinutes.add(minutes);
      } else {
        weekdayWakeMinutes.add(minutes);
      }
    }

    if (weekdayWakeMinutes.isEmpty ||
        weekendWakeMinutes.isEmpty) {
      return;
    }

    final weekdayAverage =
        _averageInt(
      weekdayWakeMinutes,
    );

    final weekendAverage =
        _averageInt(
      weekendWakeMinutes,
    );

    final difference =
        weekendAverage - weekdayAverage;

    if (difference < 60) {
      return;
    }

    final severity = difference >= 120
        ? SleepTagSeverity.attention
        : SleepTagSeverity.caution;

    tags.add(
      SleepTagResult(
        name: '주말 늦잠',
        description:
            '주말 기상 시간이 평일보다 늦어지는 패턴이 나타났습니다.',
        severity: severity,
        evidence: [
          '평일 평균 기상: '
              '${_formatKoreanClock(
                _formatClock(
                  weekdayAverage,
                ),
              )}',
          '주말 평균 기상: '
              '${_formatKoreanClock(
                _formatClock(
                  weekendAverage,
                ),
              )}',
          '평일·주말 기상 차이: '
              '${_formatMinutes(difference)}',
        ],
      ),
    );
  }

  static void _addSnoreTag({
    required List<SleepTagResult> tags,
    required List<SleepRecord>
        recentRecords,
    required List<SleepRecord>
        snoreRecords,
    required int totalSnoreCount,
    required double totalSnoreHours,
    required double averageSnoreRatio,
  }) {
    final snoreDays =
        snoreRecords.length;

    final requiredDays = math.max(
      2,
      (recentRecords.length * 0.3)
          .ceil(),
    );

    if (snoreDays < requiredDays &&
        totalSnoreCount < 5) {
      return;
    }

    final severity =
        snoreDays >= 4 ||
                totalSnoreCount >= 20 ||
                averageSnoreRatio >= 10
            ? SleepTagSeverity.attention
            : SleepTagSeverity.caution;

    tags.add(
      SleepTagResult(
        name: '코골이 주의',
        description:
            '최근 수면 중 코골이가 여러 날 반복적으로 감지되었습니다.',
        severity: severity,
        evidence: [
          '코골이 감지 일수: '
              '${recentRecords.length}일 중 '
              '$snoreDays일',
          '코골이 감지 횟수: '
              '총 $totalSnoreCount회',
          '누적 코골이 시간: '
              '${_formatHours(totalSnoreHours)}',
          if (averageSnoreRatio > 0)
            '수면 대비 코골이 비율: '
                '평균 '
                '${averageSnoreRatio.toStringAsFixed(1)}%',
        ],
      ),
    );
  }

  static SleepTagSeverity
      _getOverallSeverity(
    List<SleepTagResult> tags,
  ) {
    if (tags.any(
      (tag) =>
          tag.severity ==
          SleepTagSeverity.attention,
    )) {
      return SleepTagSeverity.attention;
    }

    if (tags.any(
      (tag) =>
          tag.severity ==
          SleepTagSeverity.caution,
    )) {
      return SleepTagSeverity.caution;
    }

    return SleepTagSeverity.good;
  }

  static String _getOverallStatus(
    SleepTagSeverity severity,
  ) {
    switch (severity) {
      case SleepTagSeverity.good:
        return '양호';

      case SleepTagSeverity.caution:
        return '관리 권장';

      case SleepTagSeverity.attention:
        return '집중 관리 권장';
    }
  }

  static SleepTagAnalysis
      _emptyAnalysis({
    required DateTime periodStart,
    required DateTime periodEnd,
  }) {
    return SleepTagAnalysis(
      periodStart: periodStart,
      periodEnd: periodEnd,
      sourceRecordCount: 0,
      sleepRecordCount: 0,
      snoreRecordCount: 0,
      averageSleepHours: 0,
      averageTargetSleepHours: 0,
      averageBedtime: '--:--',
      averageWakeTime: '--:--',
      snoreDays: 0,
      totalSnoreCount: 0,
      totalSnoreHours: 0,
      averageSnoreRatio: 0,
      overallStatus: '분석 전',
      overallSeverity:
          SleepTagSeverity.caution,
      summary:
          '최근 7일 동안 분석할 수면 또는 코골이 기록이 없습니다.',
      tags: const [],
      weeklyGoals: const [],
      cautionNote:
          '본 분석은 수면 습관 관리를 위한 참고 정보이며 의료 진단을 대신하지 않습니다.',
    );
  }

  static DateTime _dateOnly(
    DateTime date,
  ) {
    return DateTime(
      date.year,
      date.month,
      date.day,
    );
  }

  static String _dateKey(
    DateTime date,
  ) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static int? _parseClockMinutes(
    String value, {
    required bool isBedtime,
  }) {
    if (value.isEmpty ||
        value == '--:--') {
      return null;
    }

    final parts = value.split(':');

    if (parts.length != 2) {
      return null;
    }

    final hour =
        int.tryParse(parts[0]);

    final minute =
        int.tryParse(parts[1]);

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }

    var totalMinutes =
        hour * 60 + minute;

    /*
     * 23:30과 00:30을 평균 냈을 때
     * 정오로 계산되는 문제를 방지한다.
     */
    if (isBedtime && hour < 12) {
      totalMinutes += 24 * 60;
    }

    return totalMinutes;
  }

  static int _averageInt(
    List<int> values,
  ) {
    if (values.isEmpty) {
      return 0;
    }

    final sum = values.fold<int>(
      0,
      (total, value) =>
          total + value,
    );

    return (sum / values.length)
        .round();
  }

  static double _average(
    Iterable<double> values,
  ) {
    final safeValues = values
        .where(_isValidDouble)
        .toList();

    if (safeValues.isEmpty) {
      return 0;
    }

    final sum =
        safeValues.fold<double>(
      0,
      (total, value) =>
          total + value,
    );

    return sum / safeValues.length;
  }

  static bool _isValidDouble(
    double value,
  ) {
    return !value.isNaN &&
        !value.isInfinite;
  }

  static String _formatClock(
    int totalMinutes,
  ) {
    final normalized =
        totalMinutes % (24 * 60);

    final hour = normalized ~/ 60;
    final minute = normalized % 60;

    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  static String _formatKoreanClock(
    String clock,
  ) {
    if (clock == '--:--') {
      return '기록 없음';
    }

    final parts = clock.split(':');

    if (parts.length != 2) {
      return clock;
    }

    final hour =
        int.tryParse(parts[0]);

    final minute =
        int.tryParse(parts[1]);

    if (hour == null ||
        minute == null) {
      return clock;
    }

    final period =
        hour < 12 ? '오전' : '오후';

    final displayHour =
        hour % 12 == 0
            ? 12
            : hour % 12;

    if (minute == 0) {
      return '$period $displayHour시';
    }

    return '$period $displayHour시 '
        '$minute분';
  }

  static String _formatHours(
    double hours,
  ) {
    if (!_isValidDouble(hours) ||
        hours <= 0) {
      return '0분';
    }

    final totalMinutes =
        (hours * 60).round();

    final displayHours =
        totalMinutes ~/ 60;

    final minutes =
        totalMinutes % 60;

    if (displayHours <= 0) {
      return '$minutes분';
    }

    if (minutes == 0) {
      return '$displayHours시간';
    }

    return '$displayHours시간 '
        '$minutes분';
  }

  static String _formatMinutes(
    int totalMinutes,
  ) {
    if (totalMinutes <= 0) {
      return '0분';
    }

    final hours =
        totalMinutes ~/ 60;

    final minutes =
        totalMinutes % 60;

    if (hours <= 0) {
      return '$minutes분';
    }

    if (minutes == 0) {
      return '$hours시간';
    }

    return '$hours시간 $minutes분';
  }
}