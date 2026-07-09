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
              _toggle('일별', daily, () => setState(() => daily = true)),
              _toggle('월별', !daily, () => setState(() => daily = false)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (daily) ..._dailyCharts() else ..._monthlyCharts(),
      ],
    );
  }

  Widget _toggle(String label, bool active, VoidCallback onTap) {
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
              color: active ? const Color(0xFF10142A) : AppColors.muted,
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
    // 최신 기록이 너무 많이 쌓여도 최근 7개만 보여줌
    final recs = widget.state.records.take(7).toList().reversed.toList();

    final labels =
        recs.map((r) => DateFormat('E', 'ko').format(r.date)).toList();

    final sleepHours = recs.map((r) => _safeDouble(r.totalSleepHours)).toList();

    final noiseValues = recs.map((r) => _safeDouble(r.noiseDb)).toList();

    final deficitValues = recs.map((r) {
      final deficit = r.sleepDeficitHours;
      if (deficit.isNaN || deficit.isInfinite || deficit <= 0) {
        return 0.0;
      }
      return double.parse(deficit.toStringAsFixed(1));
    }).toList();

    return [
      _chartCard(
        '일별 수면 점수',
        _scoreBarChart(
          recs.map((r) => r.score.clamp(0, 100)).toList(),
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
          maxY: max(10, _niceMax(sleepHours)),
        ),
      ),
      const SizedBox(height: 16),
      _chartCard(
        '취침 · 기상 시각',
        _bedWakeChart(recs, labels),
        legend: const [
          _LegendDot('취침', AppColors.primary),
          _LegendDot('기상', AppColors.gold),
        ],
      ),
      const SizedBox(height: 16),
      _chartCard(
        '소음 (dB)',
        _lineChart(
          noiseValues,
          labels,
          AppColors.pink,
          maxY: max(60, _niceMax(noiseValues)),
        ),
      ),
      const SizedBox(height: 16),
      _chartCard(
        '부족 수면 (시간)',
        _barChart(
          deficitValues,
          labels,
          AppColors.orange,
          maxY: max(3, _niceMax(deficitValues)),
        ),
      ),
    ];
  }

  // =========================
  // 월별 통계
  // =========================

  List<Widget> _monthlyCharts() {
    final labels = monthlyRecords.map((m) => m.label).toList();

    final sleepValues =
        monthlyRecords.map((m) => _safeDouble(m.avgSleepHours)).toList();

    final noiseValues =
        monthlyRecords.map((m) => _safeDouble(m.avgNoiseDb)).toList();

    final deficitValues =
        monthlyRecords.map((m) => _safeDouble(m.avgDeficitHours)).toList();

    return [
      _chartCard(
        '월별 평균 수면 점수',
        _scoreBarChart(
          monthlyRecords.map((m) => m.avgScore.clamp(0, 100)).toList(),
          labels,
        ),
      ),
      const SizedBox(height: 16),
      _chartCard(
        '월평균 수면 시간 (시간)',
        _barChart(
          sleepValues,
          labels,
          AppColors.accent,
          maxY: max(10, _niceMax(sleepValues)),
        ),
      ),
      const SizedBox(height: 16),
      _chartCard(
        '월평균 소음 (dB)',
        _lineChart(
          noiseValues,
          labels,
          AppColors.pink,
          maxY: max(60, _niceMax(noiseValues)),
        ),
      ),
      const SizedBox(height: 16),
      _chartCard(
        '월평균 부족 수면 (시간)',
        _barChart(
          deficitValues,
          labels,
          AppColors.orange,
          maxY: max(3, _niceMax(deficitValues)),
        ),
      ),
    ];
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
              Expanded(child: SectionTitle(title)),
              if (legend != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final l in legend) ...[
                      l,
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

    // history는 index 0 = 최근이므로, 그래프는 오래된 -> 최신 순으로 뒤집는다.
    final recs = history.reversed.toList();

    final hasAnyData = recs.any((r) => r.hasData);

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
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (error != null)
            const SizedBox(
              height: 180,
              child: Center(
                child: Text(
                  '데이터를 불러오지 못했습니다.\n워치 연동 상태를 확인해 주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            )
          else if (!hasAnyData)
            const SizedBox(
              height: 180,
              child: Center(
                child: Text(
                  '산소포화도 데이터가 없습니다.\n워치 연동 시 확인할 수 있어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
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
            style: TextStyle(color: AppColors.muted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _apneaChart(List<ApneaRiskSummary> recs) {
    final labels =
        recs.map((r) => DateFormat('E', 'ko').format(r.date)).toList();

    final spo2Values = recs.map((r) => r.avgSpO2 ?? 0).toList();

    return LineChart(
      LineChartData(
        minY: 80,
        maxY: 100,
        gridData: _grid(5),
        titlesData: _titles(labels, 5),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < recs.length; i++)
                if (recs[i].hasData) FlSpot(i.toDouble(), spo2Values[i]),
            ],
            isCurved: true,
            color: AppColors.accent,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) {
                final isLow = spot.y < HealthConnectService.lowSpO2Threshold;
                return FlDotCirclePainter(
                  radius: isLow ? 5 : 3,
                  color: isLow ? AppColors.pink : AppColors.accent,
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

  Widget _apneaInsight(List<ApneaRiskSummary> recs) {
    final validRecs = recs.where((r) => r.hasData).toList();

    final totalLowEvents = validRecs.fold<int>(
      0,
      (sum, r) => sum + r.lowSpO2Events,
    );

    final daysWithLowEvents =
        validRecs.where((r) => r.lowSpO2Events > 0).length;

    final message = totalLowEvents == 0
        ? '최근 기록에서는 산소포화도가 낮아지는 구간이 발견되지 않았어요.'
        : '최근 ${validRecs.length}일 중 $daysWithLowEvents일 동안 '
            '산소포화도가 낮아지는 구간이 감지됐어요. '
            '이런 패턴이 반복되면 전문의 상담을 권장해요.';

    final accentColor =
        totalLowEvents == 0 ? AppColors.accent : AppColors.orange;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
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

  Widget _scoreBarChart(List<int> scores, List<String> labels) {
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: 100,
        gridData: _grid(20),
        titlesData: _titles(labels, 20),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var i = 0; i < scores.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: scores[i].toDouble().clamp(0, 100),
                  color: ScoreGrade.of(scores[i]).color,
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
    final safeMaxY = max(1.0, maxY);
    final interval = max(1.0, safeMaxY / 5);

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: safeMaxY,
        gridData: _grid(interval),
        titlesData: _titles(labels, interval),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var i = 0; i < vals.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: _safeDouble(vals[i]).clamp(0, safeMaxY),
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
  // 선 차트
  // =========================

  Widget _lineChart(
    List<double> vals,
    List<String> labels,
    Color color, {
    required double maxY,
  }) {
    final safeMaxY = max(1.0, maxY);
    final interval = max(1.0, safeMaxY / 5);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: safeMaxY,
        gridData: _grid(interval),
        titlesData: _titles(labels, interval),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < vals.length; i++)
                FlSpot(
                  i.toDouble(),
                  _safeDouble(vals[i]).clamp(0, safeMaxY),
                ),
            ],
            isCurved: true,
            color: color,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (s, _, __, ___) {
                return FlDotCirclePainter(
                  radius: 3,
                  color: color,
                  strokeWidth: 0,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // 취침 / 기상 시각 차트
  // =========================

  Widget _bedWakeChart(List<SleepRecord> recs, List<String> labels) {
    double bedHour(String t) {
      final parsed = _parseHour(t);

      if (parsed == null) return 0;

      var h = parsed;

      if (h > 12) {
        h -= 24;
      }

      return h;
    }

    double wakeHour(String t) {
      return _parseHour(t) ?? 0;
    }

    return LineChart(
      LineChartData(
        minY: -3,
        maxY: 9,
        gridData: _grid(3),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: 3,
              getTitlesWidget: (v, _) {
                if (v.isNaN || v.isInfinite) {
                  return const SizedBox.shrink();
                }

                final h = v.toInt();
                final label = h < 0 ? '${24 + h}시' : '$h시';

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
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < recs.length; i++)
                FlSpot(
                  i.toDouble(),
                  bedHour(recs[i].bedtimeActual),
                ),
            ],
            isCurved: true,
            color: AppColors.primary,
            barWidth: 3,
            dotData: const FlDotData(show: true),
          ),
          LineChartBarData(
            spots: [
              for (var i = 0; i < recs.length; i++)
                FlSpot(
                  i.toDouble(),
                  wakeHour(recs[i].wakeActual),
                ),
            ],
            isCurved: true,
            color: AppColors.gold,
            barWidth: 3,
            dotData: const FlDotData(show: true),
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
      horizontalInterval: interval <= 0 ? 1 : interval,
      getDrawingHorizontalLine: (v) {
        return const FlLine(
          color: AppColors.border,
          strokeWidth: 1,
        );
      },
    );
  }

  FlTitlesData _titles(List<String> labels, double interval) {
    return FlTitlesData(
      topTitles: const AxisTitles(
        sideTitles: SideTitles(showTitles: false),
      ),
      rightTitles: const AxisTitles(
        sideTitles: SideTitles(showTitles: false),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 34,
          interval: interval <= 0 ? 1 : interval,
          getTitlesWidget: (v, _) {
            if (v.isNaN || v.isInfinite) {
              return const SizedBox.shrink();
            }

            final text = v % 1 == 0 ? '${v.toInt()}' : v.toStringAsFixed(1);

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

  AxisTitles _bottom(List<String> labels) {
    return AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 24,
        interval: 1,
        getTitlesWidget: (v, _) {
          if (v.isNaN || v.isInfinite) {
            return const SizedBox.shrink();
          }

          final i = v.toInt();

          if (i < 0 || i >= labels.length) {
            return const SizedBox.shrink();
          }

          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              labels[i],
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

  double _safeDouble(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0;
    }

    return value;
  }

  double _niceMax(List<double> values) {
    if (values.isEmpty) return 1;

    final cleanValues = values.map(_safeDouble).where((v) => v > 0).toList();

    if (cleanValues.isEmpty) return 1;

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

    return ((maxValue / 50).ceil() * 50).toDouble();
  }

  double? _parseHour(String time) {
    final parts = time.split(':');

    if (parts.length != 2) {
      return null;
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null || minute == null) {
      return null;
    }

    return hour + minute / 60;
  }
}

class _LegendDot extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendDot(this.label, this.color);

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
