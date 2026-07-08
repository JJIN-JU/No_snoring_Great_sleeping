import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/sleep_data.dart';
import '../services/auth_api_service.dart';
import '../services/health_connect_service.dart';
import '../services/kakao_auth_service.dart';
import '../services/snore_classification_service.dart';
import '../services/snore_measure_service.dart';
import '../theme.dart';

class AppState extends ChangeNotifier {
  // AI 판별 결과를 화면/DB에 반영할 최소 확률.
  // 모델이 snoring=false를 반환해도 확률이 이 값 이상이면 코골이 후보로 인정.
  static const double aiSnoringProbabilityThreshold = 0.50;

  // =========================
  // 로그인 상태
  // =========================

  bool loggedIn = false;
  String userName = '홍길동';

  bool loginLoading = false;
  String? loginError;

  // MongoDB users 컬렉션의 _id
  String? userId;

  String? kakaoId;
  String? kakaoEmail;
  String? profileImageUrl;
  String? kakaoAccessToken;

  // =========================
  // 화면 / 날짜 상태
  // =========================

  int selectedIndex = 0;

  String bedtimeTarget = '23:30';
  String wakeTarget = '07:00';

  // =========================
  // 수면 + 코골이 측정 상태
  // =========================

  bool measuring = false;
  Duration measuredElapsed = Duration.zero;

  DateTime? _measureStartedAt;
  Timer? _timer;

  final SnoreMeasureService _snoreMeasureService = SnoreMeasureService();

  String? snoreError;

  // AI 모델이 각 10초 녹음을 어떻게 판단했는지 화면에 보여주는 디버그 문구
  String? snoreAiDebugText;

  bool get snoreRecording => _snoreMeasureService.isRunning;

  // =========================
  // Health Connect 상태
  // =========================

  bool healthLoading = false;
  String? healthError;
  DateTime? lastHealthSyncAt;

  // 샘플 데이터 없음
  // Health Connect 수면 데이터 또는 폰 마이크 측정 데이터가 들어올 때만 records에 추가됨
  final List<SleepRecord> _records = [];

  List<SleepRecord> get records => _records;

  SleepRecord get current {
    if (_records.isEmpty) {
      return _emptyRecord();
    }

    if (selectedIndex < 0) {
      selectedIndex = 0;
    }

    if (selectedIndex >= _records.length) {
      selectedIndex = _records.length - 1;
    }

    return _records[selectedIndex];
  }

  bool get hasRecords => _records.isNotEmpty;

  bool get canGoPrev => selectedIndex < _records.length - 1;
  bool get canGoNext => selectedIndex > 0;

  // =========================
  // 카카오 로그인 + DB 저장
  // =========================

  Future<void> loginWithKakao() async {
    if (loginLoading) return;

    loginLoading = true;
    loginError = null;
    notifyListeners();

    try {
      // 1. 카카오 로그인
      final kakaoResult = await KakaoAuthService().login();

      // 2. 카카오 사용자 정보를 FastAPI 서버로 전송
      // 3. FastAPI가 MongoDB users 컬렉션에 저장 또는 업데이트
      // 4. 저장된 user_id 반환
      final savedUser = await AuthApiService().saveKakaoUser(kakaoResult);

      loggedIn = true;

      userId = savedUser.userId;
      kakaoId = savedUser.kakaoId;
      kakaoEmail = savedUser.email;
      profileImageUrl = savedUser.profileImageUrl;

      // 토큰은 앱 내부 로그인 상태 확인용으로만 보관
      // DB에는 저장하지 않음
      kakaoAccessToken = kakaoResult.accessToken;

      userName = savedUser.nickname?.isNotEmpty == true
          ? savedUser.nickname!
          : kakaoResult.nickname?.isNotEmpty == true
              ? kakaoResult.nickname!
              : '카카오 사용자';
    } catch (e) {
      loginError = e.toString();
      loggedIn = false;

      userId = null;
      kakaoId = null;
      kakaoEmail = null;
      profileImageUrl = null;
      kakaoAccessToken = null;
    } finally {
      loginLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      await KakaoAuthService().logout();
    } catch (_) {
      // 카카오 로그아웃 실패해도 앱 내부에서는 로그아웃 처리
    }

    _clearLoginState();
    notifyListeners();
  }

  Future<void> withdraw() async {
    if (loginLoading) return;

    loginLoading = true;
    loginError = null;
    notifyListeners();

    final currentKakaoId = kakaoId;

    try {
      if (currentKakaoId == null || currentKakaoId.isEmpty) {
        throw Exception('카카오 사용자 ID가 없어 DB 삭제를 진행할 수 없습니다.');
      }

      // 1. FastAPI 서버에 DB 사용자 삭제 요청
      await AuthApiService().deleteKakaoUser(currentKakaoId);

      // 2. 카카오 연결 해제
      await KakaoAuthService().unlink();

      // 3. 앱 내부 로그인 상태 초기화
      _clearLoginState();
    } catch (e) {
      loginError = e.toString();
    } finally {
      loginLoading = false;
      notifyListeners();
    }
  }

  void _clearLoginState() {
    loggedIn = false;
    loginLoading = false;
    loginError = null;

    userName = '홍길동';

    userId = null;
    kakaoId = null;
    kakaoEmail = null;
    profileImageUrl = null;
    kakaoAccessToken = null;
  }

  // =========================
  // 날짜 이동
  // =========================

  void goPrev() {
    if (canGoPrev) {
      selectedIndex++;
      notifyListeners();
    }
  }

  void goNext() {
    if (canGoNext) {
      selectedIndex--;
      notifyListeners();
    }
  }

  // =========================
  // 목표 시간 설정
  // =========================

  void setTargets(String bedtime, String wake) {
    bedtimeTarget = bedtime;
    wakeTarget = wake;

    if (_records.isNotEmpty) {
      final old = current;

      _records[selectedIndex] = SleepRecord(
        date: old.date,
        score: old.score,
        bedtimeTarget: bedtimeTarget,
        wakeTarget: wakeTarget,
        bedtimeActual: old.bedtimeActual,
        wakeActual: old.wakeActual,
        totalSleepHours: old.totalSleepHours,
        targetSleepHours: _parseHours(bedtimeTarget, wakeTarget),
        avgSnoreDb: old.avgSnoreDb,
        maxSnoreDb: old.maxSnoreDb,
        snoreHours: old.snoreHours,
        snoreFreqHz: old.snoreFreqHz,
        snoreCount: old.snoreCount,
        noiseDb: old.noiseDb,
        stages: old.stages,
        snoreTimeline: old.snoreTimeline,

        // 목표 시간 변경 시 기존 녹음 클립 유지
        snoreAudioClips: old.snoreAudioClips,
      );
    }

    notifyListeners();
  }

  // =========================
  // Health Connect 수면 데이터 불러오기
  // =========================

  Future<void> loadHealthConnectSleep({int nights = 7}) async {
    if (healthLoading) return;

    healthLoading = true;
    healthError = null;
    notifyListeners();

    try {
      final service = HealthConnectService();
      final history = await service.fetchSleepHistory(nights: nights);

      final targetHours = _parseHours(bedtimeTarget, wakeTarget);

      // 같은 날짜의 기존 레코드가 있다면(폰 마이크로 측정한 코골이 값 등)
      // 코골이 관련 필드는 최대한 유지한다.
      final oldByDate = <String, SleepRecord>{
        for (final r in _records) _dateKey(r.date): r,
      };

      final newRecords = history.map((result) {
        final old = oldByDate[_dateKey(result.date)];

        final totalSleepHours = double.parse(
          (result.totalSleepMinutes / 60).toStringAsFixed(1),
        );

        final bedtimeActual = result.bedtime == null
            ? (old?.bedtimeActual ?? bedtimeTarget)
            : _formatTime(result.bedtime!);

        final wakeActual = result.wakeTime == null
            ? (old?.wakeActual ?? wakeTarget)
            : _formatTime(result.wakeTime!);

        final stages = result.stages.isNotEmpty
            ? result.stages.map((stage) {
                return SleepStage(
                  stage.name,
                  stage.minutes,
                  _stageColor(stage.name),
                );
              }).toList()
            : (old?.stages ?? const <SleepStage>[]);

        final score = _calculateSleepScore(
          totalSleepHours: totalSleepHours,
          targetSleepHours: targetHours,
          stages: stages,
        );

        return SleepRecord(
          date: result.date,
          score: score,
          bedtimeTarget: bedtimeTarget,
          wakeTarget: wakeTarget,
          bedtimeActual: bedtimeActual,
          wakeActual: wakeActual,
          totalSleepHours: totalSleepHours,
          targetSleepHours: targetHours,

          // 코골이/소음 값은 Health Connect가 아니라 폰 마이크 측정값 유지
          avgSnoreDb: old?.avgSnoreDb ?? 0,
          maxSnoreDb: old?.maxSnoreDb ?? 0,
          snoreHours: old?.snoreHours ?? 0,
          snoreFreqHz: old?.snoreFreqHz ?? 0,
          snoreCount: old?.snoreCount ?? 0,
          noiseDb: old?.noiseDb ?? 0,
          snoreTimeline: old?.snoreTimeline ?? const [],

          // Health Connect 동기화 후에도 기존 녹음 클립 유지
          snoreAudioClips: old?.snoreAudioClips ?? const [],

          stages: stages,
        );
      }).toList();

      // history는 이미 최신 -> 과거 순으로 정렬돼 있으므로 그대로 교체한다.
      _records
        ..clear()
        ..addAll(newRecords);

      selectedIndex = 0;
      lastHealthSyncAt = DateTime.now();
    } catch (e) {
      healthError = e.toString();
    } finally {
      healthLoading = false;
      notifyListeners();
    }
  }

  // =========================
  // 실제 마이크 기반 코골이/소음 측정
  // =========================

  Future<void> startMeasuring() async {
    if (measuring) return;

    try {
      snoreError = null;
      snoreAiDebugText = null;

      await _snoreMeasureService.start();

      measuring = true;
      measuredElapsed = Duration.zero;
      _measureStartedAt = DateTime.now();

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_measureStartedAt == null) return;

        measuredElapsed = DateTime.now().difference(_measureStartedAt!);
        notifyListeners();
      });

      notifyListeners();
    } catch (e) {
      snoreError = e.toString();
      measuring = false;
      measuredElapsed = Duration.zero;
      _measureStartedAt = null;
      notifyListeners();
    }
  }

  Future<void> stopMeasuring() async {
    if (!measuring) return;

    _timer?.cancel();
    _timer = null;

    final rawSnoreResult = await _snoreMeasureService.stop();

    measuring = false;
    measuredElapsed = Duration.zero;

    // 핵심:
    // 10초 녹음 조각을 AI 모델로 판별하고,
    // snoring=true인 것 중 max dB 높은 TOP 5만 화면/DB에 남긴다.
    // TOP 5는 다시 과거순으로 정렬해서 보여준다.
    final snoreResult = await _classifyTop5SnoreClips(rawSnoreResult);

    if (_records.isNotEmpty) {
      // Health Connect 수면 기록이 있으면 그 기록에 코골이 측정값만 덮어씀
      updateTodaySnoreData(snoreResult);
    } else {
      // Health Connect 수면 기록이 아직 없으면 코골이 측정값만 들어간 기록 생성
      _addSnoreOnlyRecord(snoreResult);
    }

    selectedIndex = 0;
    _measureStartedAt = null;

    notifyListeners();
  }

  Future<SnoreMeasureResult> _classifyTop5SnoreClips(
    SnoreMeasureResult rawResult,
  ) async {
    if (rawResult.audioClips.isEmpty) {
      snoreAiDebugText = 'AI 판별 결과: 분석할 10초 녹음 조각이 없습니다. 최소 12초 이상 측정해보세요.';
      return rawResult;
    }

    if (userId == null || userId!.isEmpty) {
      snoreError = '코골이 AI 판별을 하려면 카카오 로그인이 필요합니다.';
      snoreAiDebugText = 'AI 판별 불가: userId가 없습니다. 카카오 로그인과 DB 사용자 저장을 먼저 확인하세요.';
      await _deleteLocalClipFiles(rawResult.audioClips);
      return _buildResultWithAiClips(
        rawResult: rawResult,
        aiDetectedClips: const [],
        top5Clips: const [],
      );
    }

    final aiService = AIService();
    final detected = <_ClassifiedSnoreClip>[];
    final debugLines = <String>[];

    Object? lastError;

    // 1. 모든 10초 조각을 AI로 판별만 한다. save=false라서 DB 저장 안 됨.
    for (var i = 0; i < rawResult.audioClips.length; i++) {
      final clip = rawResult.audioClips[i];

      try {
        final file = File(clip.path);

        if (!await file.exists()) {
          continue;
        }

        final result = await aiService.predict(
          userId: userId!,
          wavFile: file,
          save: false,
        );

        final probability = _toDouble(result['snoring_probability']);
        final isSnoring = _isAiSnoringResult(result);
        final noiseText = _noiseLabelsText(result['noise']);
        final judgmentText = isSnoring ? '코골이 O' : '코골이 X';

        debugLines.add(
          '${i + 1}. ${clip.time} / ${clip.durationSeconds}초 / '
          '평균 ${clip.avgDb.toStringAsFixed(1)}dB / '
          '최대 ${clip.maxDb.toStringAsFixed(1)}dB / '
          'AI확률 ${probability.toStringAsFixed(4)} / '
          '판정 $judgmentText / '
          'noise: $noiseText',
        );

        if (isSnoring) {
          detected.add(
            _ClassifiedSnoreClip(
              index: i,
              clip: clip,
              probability: probability,
            ),
          );
        }
      } catch (e) {
        lastError = e;
        debugLines.add(
          '${i + 1}. ${clip.time} / ${clip.durationSeconds}초 / AI 호출 실패: $e',
        );
      }
    }

    if (detected.isEmpty) {
      snoreAiDebugText = 'AI 판별 결과\n'
          '총 ${rawResult.audioClips.length}개 조각 분석 / 코골이 0개\n'
          '기준 확률: ${aiSnoringProbabilityThreshold.toStringAsFixed(2)}\n\n'
          '${debugLines.join('\n')}';

      if (lastError != null) {
        snoreError = '코골이 AI 판별 실패: $lastError';
      } else {
        snoreError = 'AI가 코골이로 판단한 10초 녹음이 없습니다. 아래 AI 판별 결과를 확인해보세요.';
      }

      await _deleteLocalClipFiles(rawResult.audioClips);

      return _buildResultWithAiClips(
        rawResult: rawResult,
        aiDetectedClips: const [],
        top5Clips: const [],
      );
    }

    // 2. AI가 코골이라고 본 것 중에서 max dB 높은 TOP 5를 고른다.
    final top5 = detected.toList()
      ..sort((a, b) {
        final dbCompare = b.clip.maxDb.compareTo(a.clip.maxDb);
        if (dbCompare != 0) return dbCompare;

        // dB가 같으면 더 과거 조각 우선
        return a.index.compareTo(b.index);
      });

    final selected = top5.take(5).toList()
      // 3. 화면에는 과거순으로 보여준다.
      ..sort((a, b) => a.index.compareTo(b.index));

    final selectedClips = selected.map((item) => item.clip).toList();

    snoreAiDebugText = 'AI 판별 결과\n'
        '총 ${rawResult.audioClips.length}개 조각 분석 / '
        '코골이 ${detected.length}개 / 화면 표시 TOP ${selected.length}개\n'
        '기준 확률: ${aiSnoringProbabilityThreshold.toStringAsFixed(2)}\n\n'
        '${debugLines.join('\n')}';

    // 4. 선택되지 않은 로컬 10초 파일은 삭제한다.
    await _deleteUnselectedLocalClips(
      allClips: rawResult.audioClips,
      selectedClips: selectedClips,
    );

    // 5. TOP 5만 save=true로 다시 보내서 DB에 저장한다.
    for (final item in selected) {
      try {
        final file = File(item.clip.path);

        if (!await file.exists()) {
          continue;
        }

        await aiService.predict(
          userId: userId!,
          wavFile: file,
          save: true,
        );
      } catch (e) {
        lastError = e;
      }
    }

    if (lastError != null) {
      snoreError = '일부 코골이 AI 판별 또는 DB 저장 실패: $lastError';
    } else {
      snoreError = null;
    }

    return _buildResultWithAiClips(
      rawResult: rawResult,
      aiDetectedClips: detected.map((item) => item.clip).toList(),
      top5Clips: selectedClips,
    );
  }

  SnoreMeasureResult _buildResultWithAiClips({
    required SnoreMeasureResult rawResult,
    required List<SnoreAudioClip> aiDetectedClips,
    required List<SnoreAudioClip> top5Clips,
  }) {
    if (aiDetectedClips.isEmpty) {
      return SnoreMeasureResult(
        avgSnoreDb: 0,
        maxSnoreDb: 0,
        snoreHours: 0,
        snoreFreqHz: 0,
        snoreCount: 0,
        noiseDb: rawResult.noiseDb,
        snoreTimeline: rawResult.snoreTimeline,
        audioClips: top5Clips,
      );
    }

    final avgDb = aiDetectedClips.fold<double>(
          0,
          (sum, clip) => sum + clip.avgDb,
        ) /
        aiDetectedClips.length;

    final maxDb = aiDetectedClips.fold<double>(
      0,
      (maxValue, clip) {
        if (clip.maxDb > maxValue) return clip.maxDb;
        return maxValue;
      },
    );

    final totalSeconds = aiDetectedClips.fold<int>(
      0,
      (sum, clip) => sum + clip.durationSeconds,
    );

    return SnoreMeasureResult(
      avgSnoreDb: double.parse(avgDb.toStringAsFixed(1)),
      maxSnoreDb: double.parse(maxDb.toStringAsFixed(1)),
      snoreHours: double.parse((totalSeconds / 3600).toStringAsFixed(2)),
      snoreFreqHz: rawResult.snoreFreqHz,
      // AI가 코골이로 감지한 10초 조각 수
      snoreCount: aiDetectedClips.length,
      noiseDb: rawResult.noiseDb,
      snoreTimeline: rawResult.snoreTimeline,
      // 화면에는 TOP 5만 표시
      audioClips: top5Clips,
    );
  }

  Future<void> _deleteUnselectedLocalClips({
    required List<SnoreAudioClip> allClips,
    required List<SnoreAudioClip> selectedClips,
  }) async {
    final selectedPaths = selectedClips.map((clip) => clip.path).toSet();

    for (final clip in allClips) {
      if (selectedPaths.contains(clip.path)) {
        continue;
      }

      try {
        final file = File(clip.path);

        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // 삭제 실패해도 앱 흐름에는 영향 없게 무시
      }
    }
  }

  Future<void> _deleteLocalClipFiles(
    List<SnoreAudioClip> clips,
  ) async {
    for (final clip in clips) {
      try {
        final file = File(clip.path);

        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // 삭제 실패해도 앱 흐름에는 영향 없게 무시
      }
    }
  }

  String _noiseLabelsText(dynamic noise) {
    if (noise is! List || noise.isEmpty) {
      return '-';
    }

    final labels = <String>[];

    for (final item in noise) {
      if (item is Map) {
        final label = item['label']?.toString();
        final probability = _toDouble(item['probability']);

        if (label != null && label.isNotEmpty) {
          labels.add('$label(${probability.toStringAsFixed(3)})');
        }
      }
    }

    if (labels.isEmpty) {
      return '-';
    }

    return labels.join(', ');
  }

  bool _isAiSnoringResult(Map<String, dynamic> result) {
    // 1. binary 모델 결과가 true면 코골이
    if (result['snoring'] == true) {
      return true;
    }

    // 2. multi-label 모델의 noise 목록에 Snoring이 있으면 코골이
    final noise = result['noise'];

    if (noise is List) {
      for (final item in noise) {
        if (item is Map) {
          final label = item['label']?.toString().toLowerCase();

          if (label == 'snoring') {
            return true;
          }
        }
      }
    }

    // 3. binary 확률값이 기준 이상이면 코골이 후보로 인정
    final probability = _toDouble(result['snoring_probability']);

    return probability >= aiSnoringProbabilityThreshold;
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  void _addSnoreOnlyRecord(SnoreMeasureResult snoreResult) {
    final start = _measureStartedAt ?? DateTime.now();
    final end = DateTime.now();

    final timeline = snoreResult.snoreTimeline.isEmpty
        ? const <SnorePoint>[]
        : snoreResult.snoreTimeline;

    _records.insert(
      0,
      SleepRecord(
        date: DateTime.now(),

        // Health Connect 수면 데이터가 없으므로 수면 점수는 0
        score: 0,
        bedtimeTarget: bedtimeTarget,
        wakeTarget: wakeTarget,

        // 실제 마이크 측정 시작/종료 시각
        bedtimeActual: _formatTime(start),
        wakeActual: _formatTime(end),

        // 수면 시간은 Health Connect 값이 아니므로 0으로 둠
        totalSleepHours: 0,
        targetSleepHours: _parseHours(bedtimeTarget, wakeTarget),

        // 실제 폰 마이크 측정 결과. AI 판별 후 재계산된 값이 들어옴.
        avgSnoreDb: snoreResult.avgSnoreDb,
        maxSnoreDb: snoreResult.maxSnoreDb,
        snoreHours: snoreResult.snoreHours,
        snoreFreqHz: snoreResult.snoreFreqHz,
        snoreCount: snoreResult.snoreCount,
        noiseDb: snoreResult.noiseDb,
        snoreTimeline: timeline,

        // AI가 코골이로 판별한 10초 조각 중 max dB TOP 5만 저장
        snoreAudioClips: snoreResult.audioClips,

        // 수면 단계는 Health Connect에서 받아오기 전까지 비워둠
        stages: const [],
      ),
    );
  }

  // Health Connect로 수면 기록을 먼저 가져온 뒤,
  // 마이크 측정 결과만 현재 기록에 덮어씌움
  void updateTodaySnoreData(SnoreMeasureResult snoreResult) {
    if (_records.isEmpty) return;

    final old = current;

    _records[selectedIndex] = SleepRecord(
      date: old.date,
      score: old.score,
      bedtimeTarget: old.bedtimeTarget,
      wakeTarget: old.wakeTarget,
      bedtimeActual: old.bedtimeActual,
      wakeActual: old.wakeActual,
      totalSleepHours: old.totalSleepHours,
      targetSleepHours: old.targetSleepHours,

      // 실제 폰 마이크 측정값. AI 판별 후 재계산된 값이 들어옴.
      avgSnoreDb: snoreResult.avgSnoreDb,
      maxSnoreDb: snoreResult.maxSnoreDb,
      snoreHours: snoreResult.snoreHours,
      snoreFreqHz: snoreResult.snoreFreqHz,
      snoreCount: snoreResult.snoreCount,
      noiseDb: snoreResult.noiseDb,
      snoreTimeline: snoreResult.snoreTimeline.isEmpty
          ? old.snoreTimeline
          : snoreResult.snoreTimeline,

      // 새 녹음이 있으면 AI 판별 TOP 5 사용, 없으면 기존 클립 유지
      snoreAudioClips: snoreResult.audioClips.isEmpty
          ? old.snoreAudioClips
          : snoreResult.audioClips,

      // 수면 단계는 Health Connect 값 유지
      stages: old.stages,
    );

    notifyListeners();
  }

  // =========================
  // 공통 유틸
  // =========================

  static String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  static String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  static Color _stageColor(String name) {
    if (name.contains('깊')) return AppColors.primary;
    if (name.contains('REM') || name.contains('렘')) return AppColors.accent;
    if (name.contains('얕')) return AppColors.gold;
    if (name.contains('깸') || name.contains('기상')) return AppColors.orange;
    return AppColors.muted;
  }

  static int _calculateSleepScore({
    required double totalSleepHours,
    required double targetSleepHours,
    required List<SleepStage> stages,
  }) {
    if (totalSleepHours <= 0) {
      return 0;
    }

    var score = 100.0;

    final diff = (targetSleepHours - totalSleepHours).abs();
    score -= diff * 8;

    final totalStageMinutes = stages.fold<double>(
      0,
      (sum, stage) => sum + stage.minutes,
    );

    if (totalStageMinutes > 0) {
      final deepMinutes = stages
          .where((s) => s.name.contains('깊'))
          .fold<double>(0, (sum, s) => sum + s.minutes);

      final remMinutes = stages
          .where((s) => s.name.contains('REM') || s.name.contains('렘'))
          .fold<double>(0, (sum, s) => sum + s.minutes);

      final awakeMinutes = stages
          .where((s) => s.name.contains('깸'))
          .fold<double>(0, (sum, s) => sum + s.minutes);

      final deepRatio = deepMinutes / totalStageMinutes;
      final remRatio = remMinutes / totalStageMinutes;
      final awakeRatio = awakeMinutes / totalStageMinutes;

      if (deepRatio < 0.12) score -= 8;
      if (remRatio < 0.15) score -= 6;
      if (awakeRatio > 0.12) score -= 10;
    }

    return score.clamp(0, 100).round();
  }

  static double _parseHours(String bed, String wake) {
    final b = _toMinutes(bed);
    var w = _toMinutes(wake);

    if (w <= b) {
      w += 24 * 60;
    }

    return double.parse(((w - b) / 60).toStringAsFixed(1));
  }

  static int _toMinutes(String hhmm) {
    final p = hhmm.split(':');

    if (p.length != 2) {
      return 0;
    }

    final hour = int.tryParse(p[0]) ?? 0;
    final minute = int.tryParse(p[1]) ?? 0;

    return hour * 60 + minute;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _snoreMeasureService.cancel();
    super.dispose();
  }
}

class _ClassifiedSnoreClip {
  final int index;
  final SnoreAudioClip clip;
  final double probability;

  const _ClassifiedSnoreClip({
    required this.index,
    required this.clip,
    required this.probability,
  });
}

// =========================
// 빈 기록
// =========================

SleepRecord _emptyRecord() {
  final now = DateTime.now();

  return SleepRecord(
    date: now,
    score: 0,
    bedtimeTarget: '23:30',
    wakeTarget: '07:00',
    bedtimeActual: '--:--',
    wakeActual: '--:--',
    totalSleepHours: 0,
    targetSleepHours: 7.5,
    avgSnoreDb: 0,
    maxSnoreDb: 0,
    snoreHours: 0,
    snoreFreqHz: 0,
    snoreCount: 0,
    noiseDb: 0,
    stages: const [],
    snoreTimeline: const [],

    // 빈 기록에서는 녹음 클립 없음
    snoreAudioClips: const [],
  );
}

// =========================
// 월별 통계
// =========================

// 임시 월별 샘플 제거.
// 월별 통계를 실제 값으로 만들려면 stats_tab.dart에서 state.records를 월별로 묶어 평균 내도록 수정해야 함.
const List<MonthlyRecord> monthlyRecords = [];
