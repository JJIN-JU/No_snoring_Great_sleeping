import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:noise_meter/noise_meter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:record/record.dart';
import 'snore_classification_service.dart';

import '../models/sleep_data.dart';

class SnoreMeasureResult {
  final double avgSnoreDb;
  final double maxSnoreDb;
  final double snoreHours;
  final int snoreFreqHz;
  final int snoreCount;
  final double noiseDb;
  final List<SnorePoint> snoreTimeline;

  const SnoreMeasureResult({
    required this.avgSnoreDb,
    required this.maxSnoreDb,
    required this.snoreHours,
    required this.snoreFreqHz,
    required this.snoreCount,
    required this.noiseDb,
    required this.snoreTimeline,
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
    );
  }
}

class SnoreMeasureService {
  final NoiseMeter _noiseMeter = NoiseMeter();
  final AudioRecorder _recorder = AudioRecorder();
  final AIService _aiService = AIService();
  bool _isRecording = false;

  StreamSubscription<NoiseReading>? _subscription;

  final List<double> _meanDbValues = [];
  final List<SnorePoint> _timeline = [];

  DateTime? _lastReadingAt;
  DateTime? _lastTimelineAt;

  double _maxDb = 0;
  double _snoreSeconds = 0;
  int _snoreCount = 0;

  bool _inSnoreSection = false;

  /// 이 값 이상이면 코골이 의심으로 볼 기준값.
  /// 발표용/프로젝트용 기준으로 45dB부터 잡음.
  static const double snoreThresholdDb = 45.0;

  /// 코골이가 끝났다고 판단하는 여유값.
  /// 45dB 이상에서 시작, 42dB 아래로 내려오면 종료.
  static const double snoreEndThresholdDb = 42.0;

  /// 그래프에 너무 많은 점이 찍히지 않게 30초마다 저장.
  static const Duration timelineInterval = Duration(seconds: 30);

  bool get isRunning => _subscription != null;

  Future<void> start() async {
    if (isRunning) return;

    final permission = await Permission.microphone.request();

    if (!permission.isGranted) {
      throw Exception('마이크 권한이 허용되지 않았습니다.');
    }

    _reset();

    _subscription = _noiseMeter.noise.listen(
      _onNoiseData,
      onError: (Object error) {
        throw Exception('소음 측정 중 오류가 발생했습니다: $error');
      },
      cancelOnError: true,
    );
  }

  Future<SnoreMeasureResult> stop() async {
    if (!isRunning) {
      return _buildResult();
    }

    await _subscription?.cancel();
    _subscription = null;

    return _buildResult();
  }

  Future<void> cancel() async {
    await _subscription?.cancel();
    _subscription = null;
    _reset();
  }

  void _onNoiseData(NoiseReading reading) {
    final now = DateTime.now();

    final meanDb = _cleanDb(reading.meanDecibel);
    final maxDb = _cleanDb(reading.maxDecibel);

    if (meanDb <= 0) return;

    _meanDbValues.add(meanDb);
    _maxDb = math.max(_maxDb, maxDb);

    if (_lastReadingAt != null) {
      final diffSeconds =
          now.difference(_lastReadingAt!).inMilliseconds / 1000.0;

      final safeSeconds = diffSeconds.clamp(0.0, 5.0);

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
      return SnoreMeasureResult.empty();
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

      /// noise_meter는 dB 측정용이라 실제 주파수 Hz는 계산하지 못함.
      /// FFT 분석 추가 전까지는 0으로 둔다.
      snoreFreqHz: 0,

      snoreCount: _snoreCount,
      noiseDb: double.parse(avgDb.toStringAsFixed(1)),
      snoreTimeline: List.unmodifiable(_timeline),
    );
  }

  double _cleanDb(double value) {
    if (value.isNaN || value.isInfinite || value < 0) {
      return 0;
    }

    return value;
  }

  void _reset() {
    _meanDbValues.clear();
    _timeline.clear();

    _lastReadingAt = null;
    _lastTimelineAt = null;

    _maxDb = 0;
    _snoreSeconds = 0;
    _snoreCount = 0;

    _inSnoreSection = false;
  }

  Future<void> _recordAndPredict(String userId) async {
    if (_isRecording) return;

    _isRecording = true;

    try {

      final filePath =
          "${Directory.systemTemp.path}/snore.wav";

      await _recorder.start(
       const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: filePath,
      );

      await Future.delayed(
        const Duration(seconds: 1),
      );

      final path = await _recorder.stop();

      if (path == null) return;

      final result = await _aiService.predict(
        userId: userId,
       wavFile: File(path),
      );

      print(result);

    } catch (e) {

      print(e);

    } finally {

      _isRecording = false;

    }

  }

  static String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}