import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/sleep_data.dart';
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
    if (state.stoppingMeasurement) {
      return;
    }

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
    final isStopping = state.stoppingMeasurement;
    final isMeasureActive = isMeasuring || isStopping;

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
        timeline.isNotEmpty ||
        r.snoreAudioClips.isNotEmpty;

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
              if (isMeasureActive)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.mic_rounded,
                          color: AppColors.pink,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '수면 측정 중',
                          style: TextStyle(
                            color: AppColors.foreground,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '코골이와 주변 소음을 측정하고 있어요',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              if (isMeasureActive) const SizedBox(height: 24),
              if (!isMeasureActive)
                // 측정 시작 전: 안내 이미지 (제목 없이 바로 표시)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/sleep.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                )
              else
                // 측정 중: 간단한 타이머 표시
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.pink.withValues(alpha: 0.15),
                          border: Border.all(color: AppColors.pink, width: 3),
                        ),
                        child: const Icon(
                          Icons.mic_rounded,
                          color: AppColors.pink,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        isStopping ? '저장 중' : '측정 중',
                        style: const TextStyle(
                          color: AppColors.foreground,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatElapsed(state.measuredElapsed),
                        style: const TextStyle(
                          color: AppColors.pink,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
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
                  onPressed: isStopping ? null : () => _toggleMeasure(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isMeasureActive ? AppColors.pink : AppColors.foreground,
                    foregroundColor:
                        isMeasureActive ? Colors.white : AppColors.background,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: Text(
                    isStopping
                        ? '저장 중...'
                        : isMeasuring
                            ? '측정 종료'
                            : '수면 측정 시작',
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
        // AI 판별 결과 디버그 표시
        // =========================
        if (state.snoreAiDebugText != null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('AI 판별 결과'),
                const SizedBox(height: 10),
                SelectableText(
                  state.snoreAiDebugText!,
                  style: const TextStyle(
                    color: AppColors.muted,
                    height: 1.45,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

        if (state.snoreAiDebugText != null) const SizedBox(height: 16),

        // =========================
        // 측정 전 안내
        // =========================
        if (!hasReport && !isMeasureActive)
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

        if (!hasReport && !isMeasureActive) const SizedBox(height: 16),

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
                sub: r.totalSleepHours <= 0 ? '수면 연동 전' : '시간당 $countPerHour회',
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

                              if (i < 0 || i >= timeline.length || i % 3 != 0) {
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

        // =========================
        // 감지된 코골이 녹음 재생 카드
        // =========================
        _SnoreAudioClipCard(
          clips: r.snoreAudioClips,
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

class _SnoreAudioClipCard extends StatefulWidget {
  final List<SnoreAudioClip> clips;

  const _SnoreAudioClipCard({
    required this.clips,
  });

  @override
  State<_SnoreAudioClipCard> createState() => _SnoreAudioClipCardState();
}

class _SnoreAudioClipCardState extends State<_SnoreAudioClipCard> {
  final AudioPlayer _player = AudioPlayer();

  String? _playingPath;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();

    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;

      setState(() {
        _playingPath = null;
        _isPlaying = false;
      });
    });

    _player.onPlayerStateChanged.listen((playerState) {
      if (!mounted) return;

      setState(() {
        _isPlaying = playerState == PlayerState.playing;
      });
    });
  }

  Future<void> _togglePlay(SnoreAudioClip clip) async {
    try {
      if (_playingPath == clip.path && _isPlaying) {
        await _player.pause();
        return;
      }

      await _player.stop();

      setState(() {
        _playingPath = clip.path;
        _isPlaying = false;
      });

      await _player.play(
        DeviceFileSource(clip.path),
      );

      if (!mounted) return;

      setState(() {
        _isPlaying = true;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _playingPath = null;
        _isPlaying = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('녹음 파일을 재생할 수 없습니다: $e'),
        ),
      );
    }
  }

  String _durationText(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;

    if (min <= 0) {
      return '$sec초';
    }

    return '$min분 $sec초';
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('감지된 코골이 녹음'),
          const SizedBox(height: 8),
          if (widget.clips.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  '아직 저장된 코골이 녹음이 없습니다.',
                  style: TextStyle(
                    color: AppColors.muted,
                  ),
                ),
              ),
            )
          else
            ...widget.clips.asMap().entries.map((entry) {
              final index = entry.key;
              final clip = entry.value;
              final playingThis = _playingPath == clip.path && _isPlaying;

              return Container(
                margin: EdgeInsets.only(
                  bottom: index == widget.clips.length - 1 ? 0 : 10,
                ),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.border,
                  ),
                ),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => _togglePlay(clip),
                      borderRadius: BorderRadius.circular(999),
                      child: CircleAvatar(
                        radius: 23,
                        backgroundColor:
                            playingThis ? AppColors.pink : AppColors.primary,
                        child: Icon(
                          playingThis
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${clip.time} 감지',
                            style: const TextStyle(
                              color: AppColors.foreground,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_durationText(math.min(clip.durationSeconds, 5))} · 평균 ${clip.avgDb.round()}dB · 최대 ${clip.maxDb.round()}dB',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.graphic_eq_rounded,
                      color: AppColors.pink,
                      size: 22,
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _player.stop();
    _player.dispose();
    super.dispose();
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
