import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/sleep_data.dart';

class SnoreMeasureResult {
  final double avgSnoreDb;
  final double maxSnoreDb;
  final double snoreHours;
  final int snoreFreqHz;
  final int snoreCount;
  final double noiseDb;
  final List<SnorePoint> snoreTimeline;
  final List<SnoreAudioClip> audioClips;

  const SnoreMeasureResult({
    required this.avgSnoreDb,
    required this.maxSnoreDb,
    required this.snoreHours,
    required this.snoreFreqHz,
    required this.snoreCount,
    required this.noiseDb,
    required this.snoreTimeline,
    required this.audioClips,
  });

  factory SnoreMeasureResult.empty() {
    return const SnoreMeasureResult(
      avgSnoreDb: 0,
      maxSnoreDb: 0,
      snoreHours: 0,
      snoreFreqHz: 0,
      snoreCount: 0,
      noiseDb: 0,
      snoreTimeline: [],
      audioClips: [],
    );
  }
}

class _RecorderConfigWithExtension {
  final RecordConfig config;
  final String extension;

  const _RecorderConfigWithExtension({
    required this.config,
    required this.extension,
  });
}

class SnoreMeasureService {
  final AudioRecorder _recorder = AudioRecorder();

  StreamSubscription<Amplitude>? _amplitudeSubscription;
  Timer? _segmentTimer;

  final List<double> _meanDbValues = [];
  final List<SnorePoint> _timeline = [];
  final List<SnoreAudioClip> _audioClips = [];
  final List<double> _segmentDbValues = [];

  DateTime? _lastReadingAt;
  DateTime? _lastTimelineAt;
  DateTime? _segmentStartedAt;

  String? _currentPath;

  double _maxDb = 0;
  double _segmentMaxDb = 0;
  double _snoreSeconds = 0;

  int _snoreCount = 0;
  int _clipIndex = 0;

  bool _running = false;
  bool _rotating = false;
  bool _inSnoreSection = false;

  /// record 패키지의 amplitude는 실제 생활소음 dB가 아니라 dBFS에 가까움.
  /// 앱 표시용으로 0~100 범위로 보정해서 사용.
  static const double snoreThresholdDb = 45.0;
  static const double snoreEndThresholdDb = 42.0;

  /// 10초 단위로 녹음.
  static const Duration segmentDuration = Duration(seconds: 10);

  /// 표시/저장용: 10분 구간에서 대표 클립만 남김.
  static const Duration clipBucketDuration = Duration(minutes: 10);

  /// 화면 표시 + DB 업로드용 최대 클립 수.
  static const int maxResultClips = 5;

  /// 그래프 점 저장 간격.
  static const Duration timelineInterval = Duration(seconds: 30);

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;

    try {
      final hasPermission = await _recorder.hasPermission();

      if (!hasPermission) {
        throw Exception('마이크 권한이 허용되지 않았습니다.');
      }

      _reset();

      await _startNewSegment();

      _running = true;

      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 500))
          .listen(
        _onAmplitudeData,
        onError: (_) {
          // 측정 중 amplitude 스트림 오류가 나도 앱 전체가 죽지 않게 방어
        },
      );

      _segmentTimer = Timer.periodic(segmentDuration, (_) {
        _rotateSegment();
      });
    } catch (e) {
      _running = false;
      _rotating = false;

      await _safeCancelRecorder();

      _reset();

      throw Exception('코골이 측정을 시작할 수 없습니다: $e');
    }
  }

  Future<SnoreMeasureResult> stop() async {
    if (!_running && !_rotating) {
      await _keepOnlyTopClips();
      return _buildResult();
    }

    _running = false;

    _segmentTimer?.cancel();
    _segmentTimer = null;

    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    // 10초 단위 파일 회전 중에 종료 버튼을 누른 경우 대기
    while (_rotating) {
      await Future.delayed(const Duration(milliseconds: 80));
    }

    if (_currentPath != null || _segmentStartedAt != null) {
      await _finishCurrentSegment();
    }

    // 핵심 추가:
    // 10분 구간별 대표 클립만 남기고, 그중 max dB 기준 TOP 5만 유지
    await _keepOnlyTopClips();

    return _buildResult();
  }

  Future<void> cancel() async {
    _running = false;

    _segmentTimer?.cancel();
    _segmentTimer = null;

    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    await _safeCancelRecorder();

    _reset();
  }

  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }

  Future<void> _startNewSegment() async {
    final selectedConfig = await _resolveRecordConfig();

    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/snore_clips');

    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    final now = DateTime.now();

    final fileName =
        'snore_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}_'
        '$_clipIndex.${selectedConfig.extension}';

    final path = '${folder.path}/$fileName';

    _clipIndex++;
    _currentPath = path;
    _segmentStartedAt = now;
    _segmentDbValues.clear();
    _segmentMaxDb = 0;

    await _recorder.start(
      selectedConfig.config,
      path: path,
    );
  }

  Future<_RecorderConfigWithExtension> _resolveRecordConfig() async {
    // AI 서버 분석에는 wav가 더 안정적이라 wav를 우선 사용
    final wavSupported = await _safeIsEncoderSupported(AudioEncoder.wav);

    if (wavSupported) {
      return const _RecorderConfigWithExtension(
        extension: 'wav',
        config: RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
    }

    // wav가 안 되는 기기에서는 m4a로 fallback
    final aacSupported = await _safeIsEncoderSupported(AudioEncoder.aacLc);

    if (aacSupported) {
      return const _RecorderConfigWithExtension(
        extension: 'm4a',
        config: RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
    }

    throw Exception('현재 기기에서 지원되는 녹음 인코더를 찾을 수 없습니다.');
  }

  Future<bool> _safeIsEncoderSupported(AudioEncoder encoder) async {
    try {
      return await _recorder.isEncoderSupported(encoder);
    } catch (_) {
      return false;
    }
  }

  Future<void> _rotateSegment() async {
    if (!_running || _rotating) return;

    _rotating = true;

    try {
      await _finishCurrentSegment();

      if (_running) {
        await _startNewSegment();
      }
    } catch (_) {
      // 회전 실패 시 녹음 상태 꼬임 방지
      _running = false;
      await _safeCancelRecorder();
      _clearSegment();
    } finally {
      _rotating = false;
    }
  }

  Future<void> _finishCurrentSegment() async {
    String? path;

    try {
      final isRecording = await _recorder.isRecording();

      if (isRecording) {
        path = await _recorder.stop();
      } else {
        path = _currentPath;
      }
    } catch (_) {
      path = _currentPath;
    }

    final startedAt = _segmentStartedAt;
    final now = DateTime.now();

    if (path == null || startedAt == null) {
      _clearSegment();
      return;
    }

    final durationSeconds = math.max(
      1,
      now.difference(startedAt).inSeconds,
    );

    final avgDb = _segmentDbValues.isEmpty
        ? 0.0
        : _segmentDbValues.reduce((a, b) => a + b) / _segmentDbValues.length;

    final shouldKeep = _segmentMaxDb >= snoreThresholdDb;

    if (shouldKeep) {
      _audioClips.add(
        SnoreAudioClip(
          path: path,
          time: _formatTime(startedAt),
          avgDb: double.parse(avgDb.toStringAsFixed(1)),
          maxDb: double.parse(_segmentMaxDb.toStringAsFixed(1)),
          durationSeconds: durationSeconds,
        ),
      );
    } else {
      await _deleteFileIfExists(path);
    }

    _clearSegment();
  }

  /// 10분 단위로 묶어서 각 구간의 대표 클립 1개만 남긴 뒤,
  /// 전체 max dB 기준 TOP 5만 최종 유지.
  Future<void> _keepOnlyTopClips() async {
    if (_audioClips.isEmpty) return;

    final selected = _selectTopClipsByBucket(_audioClips);
    final selectedPaths = selected.map((clip) => clip.path).toSet();

    // 선택되지 않은 녹음 파일은 휴대폰 저장소에서 삭제
    for (final clip in _audioClips) {
      if (!selectedPaths.contains(clip.path)) {
        await _deleteFileIfExists(clip.path);
      }
    }

    _audioClips
      ..clear()
      ..addAll(selected);
  }

  List<SnoreAudioClip> _selectTopClipsByBucket(
    List<SnoreAudioClip> clips,
  ) {
    final bucketBest = <int, SnoreAudioClip>{};

    for (final clip in clips) {
      final bucketKey = _bucketKeyFromTime(clip.time);

      final old = bucketBest[bucketKey];

      if (old == null || clip.maxDb > old.maxDb) {
        bucketBest[bucketKey] = clip;
      }
    }

    final selected = bucketBest.values.toList()
      ..sort((a, b) => b.maxDb.compareTo(a.maxDb));

    return selected.take(maxResultClips).toList();
  }

  int _bucketKeyFromTime(String hhmm) {
    final parts = hhmm.split(':');

    if (parts.length != 2) {
      return 0;
    }

    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;

    final totalMinutes = hour * 60 + minute;

    return totalMinutes ~/ clipBucketDuration.inMinutes;
  }

  void _onAmplitudeData(Amplitude amplitude) {
    final now = DateTime.now();

    final meanDb = _dbfsToDisplayDb(amplitude.current);
    final maxDb = _dbfsToDisplayDb(amplitude.max);

    if (meanDb <= 0) return;

    _meanDbValues.add(meanDb);
    _segmentDbValues.add(meanDb);

    _maxDb = math.max(_maxDb, maxDb);
    _segmentMaxDb = math.max(_segmentMaxDb, maxDb);

    if (_lastReadingAt != null) {
      final diffSeconds =
          now.difference(_lastReadingAt!).inMilliseconds / 1000.0;

      final safeSeconds = diffSeconds.clamp(0.0, 5.0).toDouble();

      if (meanDb >= snoreThresholdDb) {
        _snoreSeconds += safeSeconds;
      }
    }

    if (meanDb >= snoreThresholdDb && !_inSnoreSection) {
      _snoreCount++;
      _inSnoreSection = true;
    }

    if (meanDb < snoreEndThresholdDb) {
      _inSnoreSection = false;
    }

    if (_lastTimelineAt == null ||
        now.difference(_lastTimelineAt!) >= timelineInterval) {
      _timeline.add(
        SnorePoint(
          _formatTime(now),
          double.parse(meanDb.toStringAsFixed(1)),
        ),
      );

      _lastTimelineAt = now;
    }

    _lastReadingAt = now;
  }

  SnoreMeasureResult _buildResult() {
    if (_meanDbValues.isEmpty) {
      return SnoreMeasureResult(
        avgSnoreDb: 0,
        maxSnoreDb: 0,
        snoreHours: 0,
        snoreFreqHz: 0,
        snoreCount: 0,
        noiseDb: 0,
        snoreTimeline: List.unmodifiable(_timeline),
        audioClips: List.unmodifiable(_audioClips),
      );
    }

    final avgDb = _meanDbValues.reduce((a, b) => a + b) / _meanDbValues.length;

    final avgSnoreDbValues = _meanDbValues
        .where((db) => db >= snoreThresholdDb)
        .toList();

    final avgSnoreDb = avgSnoreDbValues.isEmpty
        ? avgDb
        : avgSnoreDbValues.reduce((a, b) => a + b) / avgSnoreDbValues.length;

    return SnoreMeasureResult(
      avgSnoreDb: double.parse(avgSnoreDb.toStringAsFixed(1)),
      maxSnoreDb: double.parse(_maxDb.toStringAsFixed(1)),
      snoreHours: double.parse((_snoreSeconds / 3600).toStringAsFixed(2)),
      snoreFreqHz: 0,
      snoreCount: _snoreCount,
      noiseDb: double.parse(avgDb.toStringAsFixed(1)),
      snoreTimeline: List.unmodifiable(_timeline),
      audioClips: List.unmodifiable(_audioClips),
    );
  }

  double _dbfsToDisplayDb(double dbfs) {
    if (dbfs.isNaN || dbfs.isInfinite) {
      return 0;
    }

    final value = dbfs + 90;

    return value.clamp(0.0, 100.0).toDouble();
  }

  Future<void> _safeCancelRecorder() async {
    try {
      await _recorder.cancel();
    } catch (_) {}
  }

  Future<void> _deleteFileIfExists(String path) async {
    try {
      final file = File(path);

      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // 삭제 실패해도 측정 결과 생성에는 영향 없게 무시
    }
  }

  void _clearSegment() {
    _currentPath = null;
    _segmentStartedAt = null;
    _segmentDbValues.clear();
    _segmentMaxDb = 0;
  }

  void _reset() {
    _meanDbValues.clear();
    _timeline.clear();
    _audioClips.clear();
    _segmentDbValues.clear();

    _lastReadingAt = null;
    _lastTimelineAt = null;
    _segmentStartedAt = null;
    _currentPath = null;

    _maxDb = 0;
    _segmentMaxDb = 0;
    _snoreSeconds = 0;
    _snoreCount = 0;
    _clipIndex = 0;

    _inSnoreSection = false;
    _rotating = false;
  }

  static String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}