import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/circular_score.dart';
import '../widgets/common.dart';

class SleepTab extends StatelessWidget {
  final AppState state;

  const SleepTab({
    super.key,
    required this.state,
  });

  String _fmt(double h) {
    final hours = h.floor();
    final mins = ((h - hours) * 60).round();
    return '$hours시간 $mins분';
  }

  @override
  Widget build(BuildContext context) {
    final r = state.current;
    final totalStage = r.stages.fold<double>(0, (s, e) => s + e.minutes);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _DateHeader(state: state),
        const SizedBox(height: 16),

        if (state.lastHealthSyncAt != null) ...[
          _HealthSyncInfo(state: state),
          const SizedBox(height: 16),
        ],

        AppCard(
          child: Column(
            children: [
              const SectionTitle('지난밤 수면'),
              CircularScore(score: r.score),
            ],
          ),
        ),
        const SizedBox(height: 16),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('수면 단계'),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: r.stages
                      .map(
                        (s) => Expanded(
                          flex: s.minutes.round().clamp(1, 100000),
                          child: Container(
                            height: 16,
                            color: s.color,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 14),
              ...r.stages.map(
                (s) {
                  final percent = totalStage <= 0
                      ? 0
                      : (s.minutes / totalStage * 100).round();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: s.color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          s.name,
                          style: const TextStyle(
                            color: AppColors.foreground,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_fmt(s.minutes / 60)}  ($percent%)',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SectionTitle('취침 · 기상 시간'),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _editTargets(context),
                    icon: const Icon(Icons.edit, size: 14),
                    label: const Text('목표 설정'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              _timeRow(
                '목표',
                state.bedtimeTarget,
                state.wakeTarget,
                AppColors.muted,
              ),
              const SizedBox(height: 10),
              _timeRow(
                '실제',
                r.bedtimeActual,
                r.wakeActual,
                AppColors.primary,
              ),
              const Divider(
                color: AppColors.border,
                height: 28,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _miniStat('실제 수면', _fmt(r.totalSleepHours)),
                  _miniStat('목표 수면', _fmt(r.targetSleepHours)),
                  _miniStat(
                    '부족',
                    r.sleepDeficitHours > 0
                        ? _fmt(r.sleepDeficitHours)
                        : '없음',
                    color: r.sleepDeficitHours > 0
                        ? AppColors.orange
                        : AppColors.accent,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.graphic_eq,
                label: '평균 코골이',
                value: '${r.avgSnoreDb.round()} dB',
                sub: '최대 ${r.maxSnoreDb.round()} dB',
                color: AppColors.pink,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                icon: Icons.volume_up,
                label: '평균 소음',
                value: '${r.noiseDb.round()} dB',
                sub: '조용한 편',
                color: AppColors.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        _MeasureButton(state: state),
        const SizedBox(height: 12),

        _LoadHealthConnectButton(state: state),
      ],
    );
  }

  Widget _timeRow(
    String label,
    String bed,
    String wake,
    Color color,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              const Icon(
                Icons.bedtime,
                size: 16,
                color: AppColors.muted,
              ),
              const SizedBox(width: 6),
              Text(
                bed,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: AppColors.muted,
                ),
              ),
              const Icon(
                Icons.wb_sunny,
                size: 16,
                color: AppColors.muted,
              ),
              const SizedBox(width: 6),
              Text(
                wake,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniStat(
    String label,
    String value, {
    Color? color,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color ?? AppColors.foreground,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Future<void> _editTargets(BuildContext context) async {
    var bed = state.bedtimeTarget;
    var wake = state.wakeTarget;

    Future<void> pick(
      bool isBed,
      StateSetter setSheet,
    ) async {
      final parts = (isBed ? bed : wake).split(':');

      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        ),
      );

      if (picked != null) {
        final v =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';

        setSheet(() {
          if (isBed) {
            bed = v;
          } else {
            wake = v;
          }
        });
      }
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('목표 시간 설정'),
              _targetTile(
                '취침 목표',
                bed,
                () => pick(true, setSheet),
                Icons.bedtime,
              ),
              const SizedBox(height: 12),
              _targetTile(
                '기상 목표',
                wake,
                () => pick(false, setSheet),
                Icons.wb_sunny,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    state.setTargets(bed, wake);
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: const Color(0xFF10142A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '저장',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _targetTile(
    String label,
    String value,
    VoidCallback onTap,
    IconData icon,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.foreground,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  final AppState state;

  const _DateHeader({
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final d = state.current.date;
    final label = DateFormat('M월 d일 (E)', 'ko').format(d);

    final rel = state.selectedIndex == 0
        ? '오늘'
        : state.selectedIndex == 1
            ? '어제'
            : '${state.selectedIndex}일 전';

    return Row(
      children: [
        IconButton(
          onPressed: state.canGoPrev ? state.goPrev : null,
          icon: const Icon(Icons.chevron_left),
          color: AppColors.foreground,
          disabledColor: AppColors.border,
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                rel,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: state.canGoNext ? state.goNext : null,
          icon: const Icon(Icons.chevron_right),
          color: AppColors.foreground,
          disabledColor: AppColors.border,
        ),
      ],
    );
  }
}

class _HealthSyncInfo extends StatelessWidget {
  final AppState state;

  const _HealthSyncInfo({
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final syncedAt = state.lastHealthSyncAt;

    final text = syncedAt == null
        ? 'Health Connect 미동기화'
        : 'Health Connect 동기화 완료 · ${DateFormat('HH:mm').format(syncedAt)}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.health_and_safety,
            color: AppColors.accent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.foreground,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MeasureButton extends StatelessWidget {
  final AppState state;

  const _MeasureButton({
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    if (state.measuring) {
      final e = state.measuredElapsed;
      final t =
          '${e.inHours}시간 ${(e.inMinutes % 60).toString().padLeft(2, '0')}분';

      return AppCard(
        child: Column(
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.fiber_manual_record,
                  color: AppColors.pink,
                  size: 12,
                ),
                SizedBox(width: 8),
                Text(
                  '수면 측정 중...',
                  style: TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              t,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: state.stopMeasuring,
                icon: const Icon(Icons.stop),
                label: const Text('측정 종료 및 저장'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.pink,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: state.startMeasuring,
        icon: const Icon(Icons.play_arrow),
        label: const Text(
          '수면 측정 시작',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: const Color(0xFF10142A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _LoadHealthConnectButton extends StatelessWidget {
  final AppState state;

  const _LoadHealthConnectButton({
    required this.state,
  });

  Future<void> _load(BuildContext context) async {
    await state.loadHealthConnectSleep();

    if (!context.mounted) return;

    if (state.healthError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Health Connect 오류: ${state.healthError}'),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Health Connect 수면 데이터가 화면에 반영되었습니다.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton.icon(
        onPressed: state.healthLoading ? null : () => _load(context),
        icon: state.healthLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.health_and_safety),
        label: Text(
          state.healthLoading
              ? 'Health Connect 불러오는 중...'
              : 'Health Connect 수면 데이터 불러오기',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(
            color: AppColors.primary,
          ),
          shape: RoundedRectangleBorder(
            // border
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}