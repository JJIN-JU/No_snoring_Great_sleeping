import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/sleep_data.dart';
import '../services/health_connect_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class StatsTab extends StatefulWidget {
  final AppState state;

  const StatsTab({
    super.key,
    required this.state,
  });

  @override
  State<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<StatsTab> {
  bool daily = true;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 16),
          child: Center(
            child: Text(
              '통계',
              style: TextStyle(
                color: AppColors.foreground,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              _toggle(
                '일별',
                daily,
                () => setState(() => daily = true),
              ),
              _toggle(
                '월별',
                !daily,
                () => setState(() => daily = false),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (daily) ..._dailyCharts() else ..._monthlyCharts(),
      ],
    );
  }

  Widget _toggle(
    String label,
    bool active,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active
                  ? const Color(0xFF10142A)
                  : AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // =========================
  // 일별 통계
  // =========================

  List<Widget> _dailyCharts() {
    // 최근 7개 기록을 오래된 순서부터 표시
    final recs = widget.state.records
        .take(7)
        .toList()
        .reversed
        .toList();

    final labels = recs
        .map(
          (r) => DateFormat('E', 'ko').format(r.date),
        )
        .toList();

    final sleepHours = recs
        .map(
          (r) => _safeDouble(r.totalSleepHours),
        )
        .toList();

    final noiseValues = recs
        .map(
          (r) => _safeDouble(r.noiseDb),
        )
        .toList();

    final deficitValues = recs.map((r) {
      final deficit = r.sleepDeficitHours;

      if (deficit.isNaN ||
          deficit.isInfinite ||
          deficit <= 0) {
        return 0.0;
      }

      return double.parse(
        deficit.toStringAsFixed(1),
      );
    }).toList();

    return [
      _chartCard(
        '일별 수면 점수',
        _scoreBarChart(
          recs
              .map(
                (r) => r.score.clamp(0, 100),
              )
              .toList(),
          labels,
        ),
      ),
      const SizedBox(height: 16),

      _apneaRiskCard(),
      const SizedBox(height: 16),

      _chartCard(
        '수면 시간 (시간)',
        _barChart(
          sleepHours,
          labels,
          AppColors.accent,
          maxY: max(
            10,
            _niceMax(sleepHours),
          ),
        ),
      ),
      const SizedBox(height: 16),

      _chartCard(
        '취침 · 기상 시각',
        _bedWakeChart(
          recs,
          labels,
        ),
        legend: const [
          _LegendDot(
            '취침',
            AppColors.primary,
          ),
          _LegendDot(
            '기상',
            AppColors.gold,
          ),
        ],
      ),
      const SizedBox(height: 16),

      _chartCard(
        '소음 (dB)',
        _lineChart(
          noiseValues,
          labels,
          AppColors.pink,
          maxY: max(
            60,
            _niceMax(noiseValues),
          ),
        ),
      ),
      const SizedBox(height: 16),

      _chartCard(
        '부족 수면 (시간)',
        _barChart(
          deficitValues,
          labels,
          AppColors.orange,
          maxY: max(
            3,
            _niceMax(deficitValues),
          ),
        ),
      ),
    ];
  }

  // =========================
  // 월별 통계
  // =========================

  List<Widget> _monthlyCharts() {
    final monthlyRecords = widget.state.monthlyRecords;

    final labels = monthlyRecords.map((m) => m.label).toList();

    final sleepValues = monthlyRecords
        .map((m) => _safeDouble(m.avgSleepHours))
        .toList();

    return [
      _monthlySummarySection(monthlyRecords),
      const SizedBox(height: 16),

      _chartCard(
        '월평균 수면 시간 추세',
        _monthlySleepLineChart(
          sleepValues,
          labels,
        ),
      ),
      const SizedBox(height: 16),

      _monthlyComparisonCard(
        title: '월평균 소음',
        unit: 'dB',
        color: AppColors.pink,
        records: monthlyRecords,
        valueOf: (record) => _safeDouble(record.avgNoiseDb),
        maxValue: max(
          60,
          _niceMax(
            monthlyRecords
                .map((record) => _safeDouble(record.avgNoiseDb))
                .toList(),
          ),
        ).toDouble(),
      ),
      const SizedBox(height: 16),

      _monthlyComparisonCard(
        title: '월평균 부족 수면',
        unit: '시간',
        color: AppColors.orange,
        records: monthlyRecords,
        valueOf: (record) => _safeDouble(record.avgDeficitHours),
        maxValue: max(
          3,
          _niceMax(
            monthlyRecords
                .map((record) => _safeDouble(record.avgDeficitHours))
                .toList(),
          ),
        ).toDouble(),
      ),
    ];
  }

  Widget _monthlySummarySection(
    List<MonthlyRecord> records,
  ) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('최근 3개월 요약'),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < records.length; i++) ...[
                Expanded(
                  child: _monthlySummaryCard(
                    record: records[i],
                    previous: i > 0 ? records[i - 1] : null,
                  ),
                ),
                if (i != records.length - 1)
                  const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _monthlySummaryCard({
    required MonthlyRecord record,
    MonthlyRecord? previous,
  }) {
    final score = record.avgScore.clamp(0, 100);
    final difference = previous == null
        ? null
        : score - previous.avgScore.clamp(0, 100);

    final scoreColor = ScoreGrade.of(score).color;

    IconData? trendIcon;
    Color trendColor = AppColors.muted;
    String trendText = '';

    if (difference != null) {
      if (difference > 0) {
        trendIcon = Icons.trending_up_rounded;
        trendColor = AppColors.accent;
        trendText = '+$difference';
      } else if (difference < 0) {
        trendIcon = Icons.trending_down_rounded;
        trendColor = AppColors.orange;
        trendText = '$difference';
      } else {
        trendIcon = Icons.remove_rounded;
        trendText = '0';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            record.label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  '$score',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scoreColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              const Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Text(
                  '점',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${record.avgSleepHours.toStringAsFixed(1)}시간',
            style: const TextStyle(
              color: AppColors.foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 16,
            child: difference == null
                ? const Text(
                    '기준 월',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                    ),
                  )
                : Row(
                    children: [
                      Icon(
                        trendIcon,
                        size: 13,
                        color: trendColor,
                      ),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          '$trendText점',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: trendColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _monthlySleepLineChart(
    List<double> values,
    List<String> labels,
  ) {
    final maxValue = max(
      10,
      _niceMax(values),
    ).toDouble();

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxValue,
        gridData: _grid(2),
        titlesData: _titles(labels, 2),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) {
              return spots.map((spot) {
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(1)}시간',
                  const TextStyle(
                    color: AppColors.foreground,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < values.length; i++)
                FlSpot(
                  i.toDouble(),
                  values[i].clamp(0, maxValue),
                ),
            ],
            isCurved: true,
            curveSmoothness: 0.25,
            color: AppColors.accent,
            barWidth: 4,
            dotData: FlDotData(
              show: true,
              getDotPainter: (
                spot,
                percent,
                barData,
                index,
              ) {
                return FlDotCirclePainter(
                  radius: 5,
                  color: AppColors.accent,
                  strokeWidth: 3,
                  strokeColor: AppColors.card,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.accent.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthlyComparisonCard({
    required String title,
    required String unit,
    required Color color,
    required List<MonthlyRecord> records,
    required double Function(MonthlyRecord) valueOf,
    required double maxValue,
  }) {
    final safeMaxValue = maxValue <= 0 ? 1.0 : maxValue;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title),
          const SizedBox(height: 16),
          for (var i = 0; i < records.length; i++) ...[
            _monthlyProgressRow(
              label: records[i].label,
              value: valueOf(records[i]),
              unit: unit,
              color: color,
              maxValue: safeMaxValue,
            ),
            if (i != records.length - 1)
              const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _monthlyProgressRow({
    required String label,
    required double value,
    required String unit,
    required Color color,
    required double maxValue,
  }) {
    final normalized = (value / maxValue).clamp(0.0, 1.0).toDouble();

    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: normalized,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 64,
          child: Text(
            '${value.toStringAsFixed(1)}$unit',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppColors.foreground,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  // =========================
  // 차트 카드
  // =========================

  Widget _chartCard(
    String title,
    Widget chart, {
    List<Widget>? legend,
  }) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SectionTitle(title),
              ),
              if (legend != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in legend) ...[
                      item,
                      const SizedBox(width: 10),
                    ],
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: chart,
          ),
        ],
      ),
    );
  }

  // =========================
  // 산소포화도 / 무호흡 위험
  // =========================

  Widget _apneaRiskCard() {
    final history = widget.state.apneaHistory;
    final loading = widget.state.apneaLoading;
    final error = widget.state.apneaError;

    // index 0이 최근이므로 그래프에서는 오래된 순으로 표시
    final recs = history.reversed.toList();

    final hasAnyData = recs.any(
      (r) => r.hasData,
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('수면 중 산소포화도'),
          const SizedBox(height: 8),

          if (loading)
            const SizedBox(
              height: 180,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
            )
          else if (error != null)
            const SizedBox(
              height: 180,
              child: Center(
                child: Text(
                  '데이터를 불러오지 못했습니다.\n'
                  '워치 연동 상태를 확인해 주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                  ),
                ),
              ),
            )
          else if (!hasAnyData)
            const SizedBox(
              height: 180,
              child: Center(
                child: Text(
                  '산소포화도 데이터가 없습니다.\n'
                  '워치 연동 시 확인할 수 있어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                  ),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 180,
              child: _apneaChart(recs),
            ),
            const SizedBox(height: 14),
            _apneaInsight(recs),
          ],

          const SizedBox(height: 10),
          const Text(
            '※ 참고용 정보이며 의학적 진단이 아닙니다.',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _apneaChart(List<ApneaRiskSummary> recs) {
    final labels =
        recs.map((r) => DateFormat('E', 'ko').format(r.date)).toList();

    final spo2Values = recs.map((r) {
      final value = r.avgSpO2 ?? 0;

      if (value.isNaN || value.isInfinite) {
        return 0.0;
      }

      return value.clamp(80.0, 100.0).toDouble();
    }).toList();

    return LineChart(
      LineChartData(
        minY: 80,
        maxY: 100,
        clipData: const FlClipData.all(),
        gridData: _grid(5),
        titlesData: _titles(labels, 5),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < recs.length; i++)
                if (recs[i].hasData)
                  FlSpot(
                    i.toDouble(),
                    spo2Values[i],
                  ),
            ],

            // 곡선이 차트 밖으로 휘는 현상 방지
            isCurved: false,

            color: AppColors.accent,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) {
                final isLow =
                    spot.y < HealthConnectService.lowSpO2Threshold;

                return FlDotCirclePainter(
                  radius: isLow ? 5 : 3,
                  color: isLow
                      ? AppColors.pink
                      : AppColors.accent,
                  strokeWidth: 0,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.accent.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _apneaInsight(
    List<ApneaRiskSummary> recs,
  ) {
    final validRecs = recs
        .where(
          (r) => r.hasData,
        )
        .toList();

    final totalLowEvents = validRecs.fold<int>(
      0,
      (sum, r) => sum + r.lowSpO2Events,
    );

    final daysWithLowEvents = validRecs
        .where(
          (r) => r.lowSpO2Events > 0,
        )
        .length;

    final message = totalLowEvents == 0
        ? '최근 기록에서는 산소포화도가 낮아지는 구간이 '
            '발견되지 않았어요.'
        : '최근 ${validRecs.length}일 중 '
            '$daysWithLowEvents일 동안 산소포화도가 낮아지는 '
            '구간이 감지됐어요. 이런 패턴이 반복되면 '
            '전문의 상담을 권장해요.';

    final accentColor = totalLowEvents == 0
        ? AppColors.accent
        : AppColors.orange;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accentColor.withValues(
          alpha: 0.1,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentColor.withValues(
            alpha: 0.25,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            totalLowEvents == 0
                ? Icons.check_circle_outline
                : Icons.info_outline,
            color: accentColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.foreground,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // 점수 막대 차트
  // =========================

  Widget _scoreBarChart(
    List<int> scores,
    List<String> labels,
  ) {
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: 100,
        gridData: _grid(20),
        titlesData: _titles(
          labels,
          20,
        ),
        borderData: FlBorderData(
          show: false,
        ),
        barGroups: [
          for (var i = 0; i < scores.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: scores[i]
                      .toDouble()
                      .clamp(0, 100),
                  color: ScoreGrade.of(
                    scores[i],
                  ).color,
                  width: 14,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // =========================
  // 일반 막대 차트
  // =========================

  Widget _barChart(
    List<double> vals,
    List<String> labels,
    Color color, {
    required double maxY,
  }) {
    final safeMaxY = max(
      1.0,
      maxY,
    );

    final interval = max(
      1.0,
      safeMaxY / 5,
    );

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: safeMaxY,
        gridData: _grid(interval),
        titlesData: _titles(
          labels,
          interval,
        ),
        borderData: FlBorderData(
          show: false,
        ),
        barGroups: [
          for (var i = 0; i < vals.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: _safeDouble(
                    vals[i],
                  ).clamp(
                    0,
                    safeMaxY,
                  ),
                  color: color,
                  width: 14,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // =========================
  // 일반 선 차트
  // =========================

  Widget _lineChart(
    List<double> vals,
    List<String> labels,
    Color color, {
    required double maxY,
  }) {
    final safeMaxY = max(
      1.0,
      maxY,
    );

    final interval = max(
      1.0,
      safeMaxY / 5,
    );

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: safeMaxY,
        gridData: _grid(interval),
        titlesData: _titles(
          labels,
          interval,
        ),
        borderData: FlBorderData(
          show: false,
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < vals.length; i++)
                FlSpot(
                  i.toDouble(),
                  _safeDouble(
                    vals[i],
                  ).clamp(
                    0,
                    safeMaxY,
                  ),
                ),
            ],
            isCurved: true,
            color: color,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (
                spot,
                _,
                __,
                ___,
              ) {
                return FlDotCirclePainter(
                  radius: 3,
                  color: color,
                  strokeWidth: 0,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(
                alpha: 0.12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // 취침 / 기상 시각 차트
  // =========================

  Widget _bedWakeChart(
    List<SleepRecord> recs,
    List<String> labels,
  ) {
    double bedHour(String time) {
      final parsed = _parseHour(time);

      if (parsed == null) {
        return 0;
      }

      var hour = parsed;

      // 오후 시간은 자정 전 값으로 음수 변환
      // 23:00 → -1
      // 22:00 → -2
      if (hour > 12) {
        hour -= 24;
      }

      return hour;
    }

    double wakeHour(String time) {
      return _parseHour(time) ?? 0;
    }

    return LineChart(
      LineChartData(
        // 기존 -3~9보다 범위를 넓혀
        // 데이터가 카드 밖으로 잘리는 현상 방지
        minY: -6,
        maxY: 12,

        gridData: _grid(3),

        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(
              showTitles: false,
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(
              showTitles: false,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: 3,
              getTitlesWidget: (
                value,
                meta,
              ) {
                if (value.isNaN ||
                    value.isInfinite) {
                  return const SizedBox.shrink();
                }

                final hour = value.toInt();

                final label = hour < 0
                    ? '${24 + hour}시'
                    : '$hour시';

                return Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 9,
                  ),
                );
              },
            ),
          ),
          bottomTitles: _bottom(labels),
        ),

        borderData: FlBorderData(
          show: false,
        ),

        lineBarsData: [
          // 취침 시각
          LineChartBarData(
            spots: [
              for (var i = 0; i < recs.length; i++)
                FlSpot(
                  i.toDouble(),
                  bedHour(
                    recs[i].bedtimeActual,
                  ).clamp(
                    -6,
                    12,
                  ),
                ),
            ],

            // 곡선이 과하게 휘어지는 현상 방지
            isCurved: false,

            color: AppColors.primary,
            barWidth: 3,

            dotData: const FlDotData(
              show: true,
            ),
          ),

          // 기상 시각
          LineChartBarData(
            spots: [
              for (var i = 0; i < recs.length; i++)
                FlSpot(
                  i.toDouble(),
                  wakeHour(
                    recs[i].wakeActual,
                  ).clamp(
                    -6,
                    12,
                  ),
                ),
            ],

            // 곡선이 과하게 휘어지는 현상 방지
            isCurved: false,

            color: AppColors.gold,
            barWidth: 3,

            dotData: const FlDotData(
              show: true,
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // 공통 설정
  // =========================

  FlGridData _grid(double interval) {
    return FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: interval <= 0
          ? 1
          : interval,
      getDrawingHorizontalLine: (
        value,
      ) {
        return const FlLine(
          color: AppColors.border,
          strokeWidth: 1,
        );
      },
    );
  }

  FlTitlesData _titles(
    List<String> labels,
    double interval,
  ) {
    return FlTitlesData(
      topTitles: const AxisTitles(
        sideTitles: SideTitles(
          showTitles: false,
        ),
      ),
      rightTitles: const AxisTitles(
        sideTitles: SideTitles(
          showTitles: false,
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 34,
          interval: interval <= 0
              ? 1
              : interval,
          getTitlesWidget: (
            value,
            meta,
          ) {
            if (value.isNaN ||
                value.isInfinite) {
              return const SizedBox.shrink();
            }

            final text = value % 1 == 0
                ? '${value.toInt()}'
                : value.toStringAsFixed(1);

            return Text(
              text,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 9,
              ),
            );
          },
        ),
      ),
      bottomTitles: _bottom(labels),
    );
  }

  AxisTitles _bottom(
    List<String> labels,
  ) {
    return AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 24,
        interval: 1,
        getTitlesWidget: (
          value,
          meta,
        ) {
          if (value.isNaN ||
              value.isInfinite) {
            return const SizedBox.shrink();
          }

          final index = value.toInt();

          if (index < 0 ||
              index >= labels.length) {
            return const SizedBox.shrink();
          }

          return Padding(
            padding: const EdgeInsets.only(
              top: 6,
            ),
            child: Text(
              labels[index],
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 10,
              ),
            ),
          );
        },
      ),
    );
  }

  // =========================
  // 유틸
  // =========================

  double _safeDouble(
    double value,
  ) {
    if (value.isNaN ||
        value.isInfinite) {
      return 0;
    }

    return value;
  }

  double _niceMax(
    List<double> values,
  ) {
    if (values.isEmpty) {
      return 1;
    }

    final cleanValues = values
        .map(_safeDouble)
        .where(
          (value) => value > 0,
        )
        .toList();

    if (cleanValues.isEmpty) {
      return 1;
    }

    final maxValue = cleanValues.reduce(max);

    if (maxValue <= 1) return 1;
    if (maxValue <= 3) return 3;
    if (maxValue <= 5) return 5;
    if (maxValue <= 8) return 8;
    if (maxValue <= 10) return 10;
    if (maxValue <= 20) return 20;
    if (maxValue <= 40) return 40;
    if (maxValue <= 60) return 60;
    if (maxValue <= 80) return 80;
    if (maxValue <= 100) return 100;

    return (
      (maxValue / 50).ceil() * 50
    ).toDouble();
  }

  double? _parseHour(
    String time,
  ) {
    final parts = time.split(':');

    if (parts.length != 2) {
      return null;
    }

    final hour = int.tryParse(
      parts[0],
    );

    final minute = int.tryParse(
      parts[1],
    );

    if (hour == null ||
        minute == null) {
      return null;
    }

    return hour + minute / 60;
  }
}

class _LegendDot extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendDot(
    this.label,
    this.color,
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}