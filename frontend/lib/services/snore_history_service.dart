import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/sleep_data.dart';

class SnoreDailySummary {
  final DateTime date;
  final double avgSnoreDb;
  final double maxSnoreDb;
  final double snoreHours;
  final int snoreFreqHz;
  final int snoreCount;
  final double noiseDb;
  final List<SnorePoint> snoreTimeline;
  final List<SnoreAudioClip> snoreAudioClips;

  const SnoreDailySummary({
    required this.date,
    required this.avgSnoreDb,
    required this.maxSnoreDb,
    required this.snoreHours,
    required this.snoreFreqHz,
    required this.snoreCount,
    required this.noiseDb,
    required this.snoreTimeline,
    required this.snoreAudioClips,
  });

  factory SnoreDailySummary.fromJson(Map<String, dynamic> json) {
    final timelineRaw = json['snore_timeline'];
    final clipsRaw = json['snore_audio_clips'];

    return SnoreDailySummary(
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      avgSnoreDb: _toDouble(json['avg_snore_db']),
      maxSnoreDb: _toDouble(json['max_snore_db']),
      snoreHours: _toDouble(json['snore_hours']),
      snoreFreqHz: _toInt(json['snore_freq_hz']),
      snoreCount: _toInt(json['snore_count']),
      noiseDb: _toDouble(json['noise_db']),
      snoreTimeline: timelineRaw is List
          ? timelineRaw
              .whereType<Map>()
              .map(
                (item) => SnorePoint(
                  item['time']?.toString() ?? '--:--',
                  _toDouble(item['db']),
                ),
              )
              .toList()
          : const [],
      snoreAudioClips: clipsRaw is List
          ? clipsRaw
              .whereType<Map>()
              .map(
                (item) => SnoreAudioClip(
                  path: item['path']?.toString() ?? '',
                  time: item['time']?.toString() ?? '--:--',
                  avgDb: _toDouble(item['avg_db']),
                  maxDb: _toDouble(item['max_db']),
                  durationSeconds: _toInt(item['duration_seconds']),
                ),
              )
              // 서버에는 휴대폰 내부 경로가 저장되므로,
              // 현재 기기에 실제 파일이 남아 있는 항목만 재생 목록에 노출한다.
              .where(
                (clip) =>
                    clip.path.isNotEmpty &&
                    File(clip.path).existsSync(),
              )
              .toList()
          : const [],
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class SnoreHistoryService {
  Future<void> saveDailySummary({
    required String userId,
    required SleepRecord record,
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/snore-summaries');

    final response = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'date': DateTime(
              record.date.year,
              record.date.month,
              record.date.day,
            ).toIso8601String(),
            'avg_snore_db': record.avgSnoreDb,
            'max_snore_db': record.maxSnoreDb,
            'snore_hours': record.snoreHours,
            'snore_freq_hz': record.snoreFreqHz,
            'snore_count': record.snoreCount,
            'noise_db': record.noiseDb,
            'snore_timeline': record.snoreTimeline
                .map((point) => {'time': point.time, 'db': point.db})
                .toList(),
            'snore_audio_clips': record.snoreAudioClips
                .map(
                  (clip) => {
                    'path': clip.path,
                    'time': clip.time,
                    'avg_db': clip.avgDb,
                    'max_db': clip.maxDb,
                    'duration_seconds': clip.durationSeconds,
                  },
                )
                .toList(),
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('코골이 기록 저장 실패 (${response.statusCode})\n${response.body}');
    }
  }

  Future<List<SnoreDailySummary>> fetchSummaries({
    required String userId,
    int days = 90,
  }) async {
    final uri = Uri.parse(
      '${AppConfig.baseUrl}/snore-summaries/$userId?days=$days',
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('코골이 기록 조회 실패 (${response.statusCode})\n${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return const [];

    final items = decoded['items'];
    if (items is! List) return const [];

    return items
        .whereType<Map>()
        .map((item) => SnoreDailySummary.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }
}
