import 'dart:math' as math;

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

  String _formatElapsed(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  String _formatSnoreTime(double snoreHours) {
    final totalMinutes = (snoreHours * 60).round();

    if (totalMinutes <= 0) {
      return '0분';
    }

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (hours <= 0) {
      return '$minutes분';
    }

    return '$hours시간 $minutes분';
  }

  Future<void> _toggleMeasure(BuildContext context) async {
    if (state.measuring) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) {
          return AlertDialog(
            backgroundColor: AppColors.card,
            title: const Text(
              '측정을 종료할까요?',
              style: TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: const Text(
              '측정을 종료하면 현재까지 측정된 코골이와 소음 기록이 리포트에 반영됩니다.',
              style: TextStyle(
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  '종료',
                  style: TextStyle(
                    color: AppColors.pink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      );

      if (confirm == true) {
        await state.stopMeasuring();
      }

      return;
    }

    await state.startMeasuring();
  }

  @override
  Widget build(BuildContext context) {
    final r = state.current;
    final timeline = r.snoreTimeline;
    final isMeasuring = state.measuring;

    final snorePercent = _safeSnorePercent(
      r.snoreHours,
      r.totalSleepHours,
    );

    final countPerHour = _safeCountPerHour(
      r.snoreCount,
      r.totalSleepHours,
    );

    final hasReport = r.snoreCount > 0 ||
        r.snoreHours > 0 ||
        r.avgSnoreDb > 0 ||
        r.maxSnoreDb > 0 ||
        timeline.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 16),
          child: Center(
            child: Text(
              '코골이 측정',
              style: TextStyle(
                color: AppColors.foreground,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        // =========================
        // 수면 측정 시작 카드
        // =========================
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    isMeasuring
                        ? Icons.mic_rounded
                        : Icons.bedtime_rounded,
                    color: isMeasuring ? AppColors.pink : AppColors.primary,
                    size: 30,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMeasuring ? '수면 측정 중' : '수면 측정 준비',
                          style: const TextStyle(
                            color: AppColors.foreground,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isMeasuring
                              ? '마이크로 코골이와 주변 소음을 측정하고 있습니다.'
                              : '취침 전 버튼을 누르면 코골이 감지가 시작됩니다.',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              Center(
                child: SizedBox(
                  width: 250,
                  height: 250,
                  child: CustomPaint(
                    painter: _SleepClockPainter(
                      measuring: isMeasuring,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Positioned(
                          top: 35,
                          child: Text(
                            '12 AM',
                            style: TextStyle(
                              color: AppColors.foreground,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Positioned(
                          right: 31,
                          child: Text(
                            '6 AM',
                            style: TextStyle(
                              color: AppColors.foreground,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Positioned(
                          bottom: 35,
                          child: Text(
                            '12 PM',
                            style: TextStyle(
                              color: AppColors.foreground,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Positioned(
                          left: 31,
                          child: Text(
                            '6 PM',
                            style: TextStyle(
                              color: AppColors.foreground,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 31,
                          right: 48,
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor:
                                isMeasuring ? AppColors.pink : AppColors.primary,
                            child: Icon(
                              isMeasuring
                                  ? Icons.mic_rounded
                                  : Icons.nights_stay_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 40,
                          right: 30,
                          child: CircleAvatar(
                            radius: 19,
                            backgroundColor: AppColors.gold,
                            child: const Icon(
                              Icons.notifications_rounded,
                              color: Colors.white,
                              size: 21,
                            ),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isMeasuring
                                  ? Icons.graphic_eq_rounded
                                  : Icons.hotel_rounded,
                              color:
                                  isMeasuring ? AppColors.pink : AppColors.primary,
                              size: 36,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              isMeasuring ? '측정 중' : '취침 준비',
                              style: const TextStyle(
                                color: AppColors.foreground,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isMeasuring
                                  ? _formatElapsed(state.measuredElapsed)
                                  : '버튼을 누르면 시작됩니다',
                              style: TextStyle(
                                color: isMeasuring
                                    ? AppColors.pink
                                    : AppColors.muted,
                                fontSize: isMeasuring ? 24 : 13,
                                fontWeight: isMeasuring
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              _TimeRow(
                icon: Icons.nights_stay_rounded,
                iconColor: AppColors.primary,
                label: '취침 목표',
                value: state.bedtimeTarget,
              ),
              const Divider(
                height: 28,
                color: AppColors.border,
              ),
              _TimeRow(
                icon: Icons.notifications_rounded,
                iconColor: AppColors.gold,
                label: '기상 목표',
                value: state.wakeTarget,
              ),

              const SizedBox(height: 24),

              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: () => _toggleMeasure(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isMeasuring ? AppColors.pink : AppColors.foreground,
                    foregroundColor:
                        isMeasuring ? Colors.white : AppColors.background,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: Text(
                    isMeasuring ? '측정 종료' : '수면 측정 시작',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // =========================
        // 에러 표시
        // =========================
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

        // =========================
        // 측정 전 안내
        // =========================
        if (!hasReport && !isMeasuring)
          AppCard(
            child: Column(
              children: [
                Icon(
                  Icons.mic_none_rounded,
                  color: AppColors.muted.withValues(alpha: 0.8),
                  size: 38,
                ),
                const SizedBox(height: 12),
                const Text(
                  '아직 코골이 측정 기록이 없습니다.',
                  style: TextStyle(
                    color: AppColors.foreground,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '수면 측정 시작 버튼을 누르고\n측정 종료 후 리포트를 확인해보세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.muted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

        if (!hasReport && !isMeasuring) const SizedBox(height: 16),

        // =========================
        // 코골이 리포트
        // =========================
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
                _formatSnoreTime(r.snoreHours),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                r.totalSleepHours <= 0
                    ? '수면 데이터 연동 전'
                    : '전체 수면의 $snorePercent% 차지',
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
                icon: Icons.noise_control_off_rounded,
                label: '평균 소음',
                value: '${r.noiseDb.round()} dB',
                sub: '마이크 측정',
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
                sub: r.totalSleepHours <= 0
                    ? '수면 연동 전'
                    : '시간당 $countPerHour회',
                color: AppColors.gold,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                icon: Icons.waves,
                label: '주파수',
                value: r.snoreFreqHz <= 0 ? '분석 전' : '${r.snoreFreqHz} Hz',
                sub: 'FFT 추가 예정',
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
              const SectionTitle('시간대별 코골이/소음 강도'),
              const SizedBox(height: 8),
              if (timeline.isEmpty)
                const SizedBox(
                  height: 180,
                  child: Center(
                    child: Text(
                      '측정된 소음 기록이 없습니다.',
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
                  '측정 중에는 휴대폰을 침대 가까이에 두세요.\n옆으로 누워 자면 코골이가 줄어드는 데 도움이 됩니다.',
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

class _TimeRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _TimeRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          color: iconColor,
          size: 28,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.foreground,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.foreground,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _SleepClockPainter extends CustomPainter {
  final bool measuring;

  const _SleepClockPainter({
    required this.measuring,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 18;

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 34
      ..strokeCap = StrokeCap.round
      ..color = AppColors.border.withValues(alpha: 0.55);

    canvas.drawCircle(center, radius, basePaint);

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 34
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [
          AppColors.primary,
          AppColors.pink,
          AppColors.gold,
          AppColors.primary,
        ],
      ).createShader(
        Rect.fromCircle(
          center: center,
          radius: radius,
        ),
      );

    canvas.drawArc(
      Rect.fromCircle(
        center: center,
        radius: radius,
      ),
      -math.pi / 3,
      measuring ? math.pi * 1.55 : math.pi * 0.75,
      false,
      progressPaint,
    );

    final tickPaint = Paint()
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..color = AppColors.muted.withValues(alpha: 0.6);

    final longTickPaint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = AppColors.foreground.withValues(alpha: 0.85);

    final innerRadius = radius - 54;
    final outerRadius = radius - 39;

    for (var i = 0; i < 96; i++) {
      final angle = -math.pi / 2 + (math.pi * 2 * i / 96);
      final isLong = i % 24 == 0;

      final startRadius = isLong ? innerRadius - 8 : innerRadius;

      final start = Offset(
        center.dx + math.cos(angle) * startRadius,
        center.dy + math.sin(angle) * startRadius,
      );

      final end = Offset(
        center.dx + math.cos(angle) * outerRadius,
        center.dy + math.sin(angle) * outerRadius,
      );

      canvas.drawLine(
        start,
        end,
        isLong ? longTickPaint : tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SleepClockPainter oldDelegate) {
    return oldDelegate.measuring != measuring;
  }
}