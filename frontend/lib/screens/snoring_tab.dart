import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SnoringTab extends StatelessWidget {
  final AppState state;

  const SnoringTab({
    super.key,
    required this.state,
  });

  int _safeSnorePercent(double snoreHours, double totalSleepHours) {
    if (totalSleepHours <= 0 || snoreHours.isNaN || totalSleepHours.isNaN) {
      return 0;
    }

    final value = snoreHours / totalSleepHours * 100;

    if (value.isNaN || value.isInfinite) {
      return 0;
    }

    return value.round();
  }

  int _safeCountPerHour(int count, double totalSleepHours) {
    if (totalSleepHours <= 0 || totalSleepHours.isNaN) {
      return 0;
    }

    final value = count / totalSleepHours;

    if (value.isNaN || value.isInfinite) {
      return 0;
    }

    return value.round();
  }

  @override
  Widget build(BuildContext context) {
    final r = state.current;
    final timeline = r.snoreTimeline;

    final snoreMinutes =
        ((r.snoreHours - r.snoreHours.floor()) * 60).round();

    final snorePercent = _safeSnorePercent(
      r.snoreHours,
      r.totalSleepHours,
    );

    final countPerHour = _safeCountPerHour(
      r.snoreCount,
      r.totalSleepHours,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 16),
          child: Center(
            child: Text(
              '코골이 리포트',
              style: TextStyle(
                color: AppColors.foreground,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        if (state.measuring)
          AppCard(
            child: Row(
              children: [
                const Icon(
                  Icons.mic,
                  color: AppColors.pink,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '현재 마이크로 코골이/소음 측정 중입니다.\n측정 종료 후 이 화면에 실제 값이 반영됩니다.',
                    style: const TextStyle(
                      color: AppColors.foreground,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

        if (state.measuring) const SizedBox(height: 16),

        if (state.snoreError != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.pink.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.pink.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              state.snoreError!,
              style: const TextStyle(
                color: AppColors.pink,
                height: 1.4,
              ),
            ),
          ),

        if (state.snoreError != null) const SizedBox(height: 16),

        AppCard(
          child: Column(
            children: [
              const Icon(
                Icons.graphic_eq,
                color: AppColors.pink,
                size: 32,
              ),
              const SizedBox(height: 10),
              const Text(
                '총 코골이 시간',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${r.snoreHours.floor()}시간 $snoreMinutes분',
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '전체 수면의 $snorePercent% 차지',
                style: const TextStyle(
                  color: AppColors.pink,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.volume_up,
                label: '평균 코골이',
                value: '${r.avgSnoreDb.round()} dB',
                sub: '최대 ${r.maxSnoreDb.round()} dB',
                color: AppColors.pink,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                icon: Icons.waves,
                label: '평균 주파수',
                value: r.snoreFreqHz <= 0 ? '분석 전' : '${r.snoreFreqHz} Hz',
                sub: 'FFT 분석 필요',
                color: AppColors.primary,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.repeat,
                label: '발생 횟수',
                value: '${r.snoreCount}회',
                sub: '시간당 $countPerHour회',
                color: AppColors.gold,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                icon: Icons.timer,
                label: '지속 시간',
                value: '${r.snoreHours.toStringAsFixed(2)}h',
                sub: '누적',
                color: AppColors.accent,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('시간대별 코골이 강도 (dB)'),
              const SizedBox(height: 8),

              if (timeline.isEmpty)
                const SizedBox(
                  height: 180,
                  child: Center(
                    child: Text(
                      '코골이 기록이 없습니다.',
                      style: TextStyle(
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 200,
                  child: LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: 100,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 20,
                        getDrawingHorizontalLine: (v) {
                          return const FlLine(
                            color: AppColors.border,
                            strokeWidth: 1,
                          );
                        },
                      ),
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
                            reservedSize: 30,
                            interval: 20,
                            getTitlesWidget: (v, _) {
                              if (v.isNaN || v.isInfinite) {
                                return const SizedBox.shrink();
                              }

                              return Text(
                                '${v.toInt()}',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 10,
                                ),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            interval: 1,
                            getTitlesWidget: (v, _) {
                              if (v.isNaN || v.isInfinite) {
                                return const SizedBox.shrink();
                              }

                              final i = v.toInt();

                              if (i < 0 ||
                                  i >= timeline.length ||
                                  i % 3 != 0) {
                                return const SizedBox.shrink();
                              }

                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  timeline[i].time,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 9,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (var i = 0; i < timeline.length; i++)
                              FlSpot(
                                i.toDouble(),
                                timeline[i].db,
                              ),
                          ],
                          isCurved: true,
                          color: AppColors.pink,
                          barWidth: 3,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppColors.pink.withValues(alpha: 0.35),
                                AppColors.pink.withValues(alpha: 0.02),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
            ),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: AppColors.primary,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '옆으로 누워 자면 코골이가 줄어듭니다. 취침 전 음주와 과식을 피해보세요.',
                  style: TextStyle(
                    color: AppColors.foreground,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}