import 'package:flutter/material.dart';

/// 수면 단계
class SleepStage {
  final String name;
  final double minutes;
  final Color color;

  const SleepStage(
    this.name,
    this.minutes,
    this.color,
  );
}

/// 시간대별 코골이 강도 (그래프용)
class SnorePoint {
  final String time; // "02:30"
  final double db; // 데시벨

  const SnorePoint(
    this.time,
    this.db,
  );
}

/// 감지된 코골이 녹음 클립
class SnoreAudioClip {
  final String path; // 기기 내부에 저장된 오디오 파일 경로
  final String time; // 감지 시간, 예: "02:30"
  final double avgDb; // 해당 클립 평균 dB
  final double maxDb; // 해당 클립 최대 dB
  final int durationSeconds; // 녹음 길이

  const SnoreAudioClip({
    required this.path,
    required this.time,
    required this.avgDb,
    required this.maxDb,
    required this.durationSeconds,
  });
}

/// 하루치 수면 기록
class SleepRecord {
  final DateTime date;
  final int score; // 수면 점수 0~100

  final String bedtimeTarget; // 목표 취침
  final String wakeTarget; // 목표 기상
  final String bedtimeActual; // 실제 취침
  final String wakeActual; // 실제 기상

  final double totalSleepHours; // 실제 잔 시간
  final double targetSleepHours; // 목표 수면 시간

  final double avgSnoreDb; // 평균 코골이 dB
  final double maxSnoreDb; // 최대 코골이 dB
  final double snoreHours; // 코골이 진행 시간
  final int snoreFreqHz; // 평균 주파수
  final int snoreCount; // 코골이 발생 횟수
  final double noiseDb; // 평균 소음

  final List<SleepStage> stages;
  final List<SnorePoint> snoreTimeline;

  /// 감지된 코골이 녹음 리스트
  final List<SnoreAudioClip> snoreAudioClips;

  const SleepRecord({
    required this.date,
    required this.score,
    required this.bedtimeTarget,
    required this.wakeTarget,
    required this.bedtimeActual,
    required this.wakeActual,
    required this.totalSleepHours,
    required this.targetSleepHours,
    required this.avgSnoreDb,
    required this.maxSnoreDb,
    required this.snoreHours,
    required this.snoreFreqHz,
    required this.snoreCount,
    required this.noiseDb,
    required this.stages,
    required this.snoreTimeline,
    this.snoreAudioClips = const [],
  });

  double get sleepDeficitHours => targetSleepHours - totalSleepHours;
}

/// 월별 요약
class MonthlyRecord {
  final String label; // "1월"
  final int avgScore;
  final double avgSleepHours;
  final double avgNoiseDb;
  final double avgDeficitHours;

  const MonthlyRecord(
    this.label,
    this.avgScore,
    this.avgSleepHours,
    this.avgNoiseDb,
    this.avgDeficitHours,
  );
}