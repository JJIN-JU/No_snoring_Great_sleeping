import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sleep_data.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class StatsTab extends StatefulWidget {
  final AppState state;
  const StatsTab({super.key, required this.state});

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
            child: Text('통계',
                style: TextStyle(
                    color: AppColors.foreground,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ),
        ),

        // 일별 / 월별 토글
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

  // ---------- 일별 ----------
  List<Widget> _dailyCharts() {
    // 최근 7일 (오래된 -> 최신 순서)
    final recs = widget.state.records.reversed.toList();
    final labels =
        recs.map((r) => DateFormat('E', 'ko').format(r.date)).toList();

    return [
      _chartCard(
        '일별 수면 점수',
        _scoreBarChart(recs.map((r) => r.score).toList(), labels),
      ),
      const SizedBox(height: 16),
      _chartCard(
        '수면 시간 (시간)',
        _barChart(
          recs.map((r) => r.totalSleepHours).toList(),
          labels,
          AppColors.accent,
          maxY: 10,
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
          recs.map((r) => r.noiseDb).toList(),
          labels,
          AppColors.pink,
          maxY: 60,
        ),
      ),
      const SizedBox(height: 16),
      _chartCard(
        '부족 수면 (시간)',
        _barChart(
          recs
              .map((r) => r.sleepDeficitHours > 0 ? r.sleepDeficitHours : 0.0)
              .toList(),
          labels,
          AppColors.orange,
          maxY: 3,
        ),
      ),
    ];
  }

  // ---------- 월별 ----------
  List<Widget> _monthlyCharts() {
    final labels = monthlyRecords.map((m) => m.label).toList();
    return [
      _chartCard(
        '월별 평균 수면 점수',
        _scoreBarChart(monthlyRecords.map((m) => m.avgScore).toList(), labels),
      ),
      const SizedBox(height: 16),
      _chartCard(
        '월평균 수면 시간 (시간)',
        _barChart(
          monthlyRecords.map((m) => m.avgSleepHours).toList(),
          labels,
          AppColors.accent,
          maxY: 10,
        ),
      ),
      const SizedBox(height: 16),
      _chartCard(
        '월평균 소음 (dB)',
        _lineChart(
          monthlyRecords.map((m) => m.avgNoiseDb).toList(),
          labels,
          AppColors.pink,
          maxY: 60,
        ),
      ),
      const SizedBox(height: 16),
      _chartCard(
        '월평균 부족 수면 (시간)',
        _barChart(
          monthlyRecords.map((m) => m.avgDeficitHours).toList(),
          labels,
          AppColors.orange,
          maxY: 3,
        ),
      ),
    ];
  }

  // ---------- 차트 빌더 ----------
  Widget _chartCard(String title, Widget chart, {List<Widget>? legend}) {
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
                    for (final l in legend) ...[l, const SizedBox(width: 10)]
                  ],
                ),
            ],
          ),
          SizedBox(height: 180, child: chart),
        ],
      ),
    );
  }

  Widget _scoreBarChart(List<int> scores, List<String> labels) {
    return BarChart(
      BarChartData(
        maxY: 100,
        gridData: _grid(20),
        titlesData: _titles(labels, 20),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var i = 0; i < scores.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: scores[i].toDouble(),
                color: ScoreGrade.of(scores[i]).color,
                width: 14,
                borderRadius: BorderRadius.circular(4),
              ),
            ]),
        ],
      ),
    );
  }

  Widget _barChart(List<double> vals, List<String> labels, Color color,
      {required double maxY}) {
    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: _grid(maxY / 5),
        titlesData: _titles(labels, maxY / 5),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var i = 0; i < vals.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: vals[i],
                color: color,
                width: 14,
                borderRadius: BorderRadius.circular(4),
              ),
            ]),
        ],
      ),
    );
  }

  Widget _lineChart(List<double> vals, List<String> labels, Color color,
      {required double maxY}) {
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: _grid(maxY / 5),
        titlesData: _titles(labels, maxY / 5),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < vals.length; i++) FlSpot(i.toDouble(), vals[i])
            ],
            isCurved: true,
            color: color,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                  radius: 3, color: color, strokeWidth: 0),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: color.withOpacity(0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bedWakeChart(List<SleepRecord> recs, List<String> labels) {
    // 취침(전날 밤 기준 음수 시프트) 및 기상 시간을 시(hour) 단위로 표시
    double bedHour(String t) {
      final p = t.split(':');
      var h = int.parse(p[0]) + int.parse(p[1]) / 60;
      if (h > 12) h -= 24; // 자정 넘김 표현 (예: 23:40 -> -0.33)
      return h;
    }

    double wakeHour(String t) {
      final p = t.split(':');
      return int.parse(p[0]) + int.parse(p[1]) / 60;
    }

    return LineChart(
      LineChartData(
        minY: -3,
        maxY: 9,
        gridData: _grid(3),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: 3,
              getTitlesWidget: (v, _) {
                final h = v.toInt();
                final label = h < 0 ? '${24 + h}시' : '$h시';
                return Text(label,
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 9));
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
                FlSpot(i.toDouble(), bedHour(recs[i].bedtimeActual))
            ],
            isCurved: true,
            color: AppColors.primary,
            barWidth: 3,
            dotData: const FlDotData(show: true),
          ),
          LineChartBarData(
            spots: [
              for (var i = 0; i < recs.length; i++)
                FlSpot(i.toDouble(), wakeHour(recs[i].wakeActual))
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

  FlGridData _grid(double interval) => FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: interval <= 0 ? 1 : interval,
        getDrawingHorizontalLine: (v) =>
            const FlLine(color: AppColors.border, strokeWidth: 1),
      );

  FlTitlesData _titles(List<String> labels, double interval) => FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: interval <= 0 ? 1 : interval,
            getTitlesWidget: (v, _) => Text(
              v % 1 == 0 ? '${v.toInt()}' : v.toStringAsFixed(0),
              style: const TextStyle(color: AppColors.muted, fontSize: 9),
            ),
          ),
        ),
        bottomTitles: _bottom(labels),
      );

  AxisTitles _bottom(List<String> labels) => AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          interval: 1,
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= labels.length) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(labels[i],
                  style: const TextStyle(color: AppColors.muted, fontSize: 10)),
            );
          },
        ),
      );
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
          decoration:
              BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(color: AppColors.muted, fontSize: 11)),
      ],
    );
  }
}
