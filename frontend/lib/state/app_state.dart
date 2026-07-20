import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/snore_notification_service.dart';
import '../models/sleep_data.dart';
import '../services/auth_api_service.dart';
import '../services/health_connect_service.dart';
import '../services/kakao_auth_service.dart';
import '../services/snore_classification_service.dart';
import '../services/snore_measure_service.dart';
import '../theme.dart';

class AppState extends ChangeNotifier {
  static const int snoreNotificationCooldownSeconds = 5;

  AppState() {
    _ensureTodayRecordExists();
  }

  // =========================
  // 로그인 상태
  // =========================

  bool loggedIn = false;
  String userName = '홍길동';

  bool loginLoading = false;
  String? loginError;

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
  bool _stoppingMeasurement = false;
  Duration measuredElapsed = Duration.zero;

  DateTime? _measureStartedAt;
  Timer? _timer;

  /// 측정 종료/저장 중에 늦게 도착하는 타이머·AI 응답을 버리기 위한 토큰.
  int _measureSessionToken = 0;

  final SnoreMeasureService _snoreMeasureService = SnoreMeasureService();

  String? snoreError;
  String? snoreAiDebugText;

  DateTime? _lastSnoreNotificationAt;

  bool get stoppingMeasurement => _stoppingMeasurement;
  bool get snoreRecording => _snoreMeasureService.isRunning;

  // =========================
  // Health Connect 상태
  // =========================

  bool healthLoading = false;
  String? healthError;
  DateTime? lastHealthSyncAt;

  bool apneaLoading = false;
  String? apneaError;
  List<ApneaRiskSummary> apneaHistory = [];

  // 샘플 데이터 없음
  // Health Connect 수면 데이터 또는 폰 마이크 측정 데이터가 들어올 때만 records에 추가됨
  final List<SleepRecord> _records = [];

  List<SleepRecord> get records => _records;

  SleepRecord get current {
    if (_records.isEmpty) {
      return _emptyRecordForDate(DateTime.now());
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
      final kakaoResult = await KakaoAuthService().login();

      final savedUser = await AuthApiService().saveKakaoUser(kakaoResult);

      loggedIn = true;

      userId = savedUser.userId;
      kakaoId = savedUser.kakaoId;
      kakaoEmail = savedUser.email;
      profileImageUrl = savedUser.profileImageUrl;
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

    if (loggedIn) {
      await refreshAllHealthData();
    }
  }

  Future<void> logout() async {
    try {
      await KakaoAuthService().logout();
    } catch (_) {}

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

      await AuthApiService().deleteKakaoUser(currentKakaoId);
      await KakaoAuthService().unlink();

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
      final rawHistory = await service.fetchSleepHistory(nights: nights);

      // 같은 날짜에 여러 수면 세션(낮잠 + 밤잠 등)이 있으면
      // 가장 긴 세션만 그 날짜의 대표 수면 기록으로 사용한다.
      final Map<String, dynamic> longestPerDate = {};

      for (final result in rawHistory) {
        final key = _dateKey(result.date);
        final existing = longestPerDate[key];

        if (existing == null ||
            result.totalSleepMinutes > existing.totalSleepMinutes) {
          longestPerDate[key] = result;
        }
      }

      final history = longestPerDate.values.toList();

      final targetHours = _parseHours(bedtimeTarget, wakeTarget);

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
          avgSnoreDb: old?.avgSnoreDb ?? 0,
          maxSnoreDb: old?.maxSnoreDb ?? 0,
          snoreHours: old?.snoreHours ?? 0,
          snoreFreqHz: old?.snoreFreqHz ?? 0,
          snoreCount: old?.snoreCount ?? 0,
          noiseDb: old?.noiseDb ?? 0,
          snoreTimeline: old?.snoreTimeline ?? const [],
          snoreAudioClips: old?.snoreAudioClips ?? const [],
          stages: stages,
        );
      }).toList();

      _records
        ..clear()
        ..addAll(newRecords);

      _ensureTodayRecordExists();

      selectedIndex = 0;
      lastHealthSyncAt = DateTime.now();
    } catch (e) {
      healthError = e.toString();
    } finally {
      healthLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadApneaRiskHistory({int nights = 7}) async {
    if (apneaLoading) return;

    apneaLoading = true;
    apneaError = null;
    notifyListeners();

    try {
      final service = HealthConnectService();
      apneaHistory = await service.fetchApneaRiskHistory(nights: nights);
    } catch (e) {
      apneaError = e.toString();
      apneaHistory = [];
    } finally {
      apneaLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshAllHealthData({int nights = 7}) async {
    await loadHealthConnectSleep(nights: nights);
    await loadApneaRiskHistory(nights: nights);
  }

  // =========================
  // 실제 마이크 기반 코골이/소음 측정
  // =========================

  Future<void> startMeasuring() async {
    if (measuring || _stoppingMeasurement) return;

    final int token = ++_measureSessionToken;

    try {
      snoreError = null;
      snoreAiDebugText = null;
      _lastSnoreNotificationAt = null;

      measuring = true;
      _stoppingMeasurement = false;
      measuredElapsed = Duration.zero;
      _measureStartedAt = DateTime.now();

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!measuring ||
            _stoppingMeasurement ||
            token != _measureSessionToken ||
            _measureStartedAt == null) {
          timer.cancel();
          return;
        }

        measuredElapsed = DateTime.now().difference(_measureStartedAt!);
        notifyListeners();
      });

      notifyListeners();

      await _snoreMeasureService.start(
        onClipReady: (clip) {
          return _classifyClipAndNotifyDuringMeasurement(
            clip,
            token,
          );
        },
      );

      // start()를 기다리는 사이 종료/새 측정이 발생했다면 현재 시작 요청은 폐기한다.
      if (token != _measureSessionToken || !measuring || _stoppingMeasurement) {
        return;
      }

      notifyListeners();
    } catch (e) {
      if (token == _measureSessionToken) {
        snoreError = e.toString();
        measuring = false;
        _stoppingMeasurement = false;
        measuredElapsed = Duration.zero;
        _measureStartedAt = null;

        _timer?.cancel();
        _timer = null;

        notifyListeners();
      }
    }
  }

  Future<void> stopMeasuring() async {
    if (_stoppingMeasurement) return;
    if (!measuring && !_snoreMeasureService.isRunning) return;

    final DateTime? stoppedStartedAt = _measureStartedAt;

    // 먼저 측정을 완전히 끊는다. 저장/AI 최종 판별은 그 다음에 한다.
    _stoppingMeasurement = true;
    measuring = false;

    // 이미 날아간 실시간 AI 요청이 늦게 돌아와도 결과/알림을 추가하지 못하게 무효화.
    _measureSessionToken++;

    _timer?.cancel();
    _timer = null;

    notifyListeners();

    SnoreMeasureResult rawSnoreResult;

    try {
      rawSnoreResult = await _snoreMeasureService.stop();
    } catch (e) {
      snoreError = '측정 종료 실패: $e';
      _stoppingMeasurement = false;
      measuredElapsed = Duration.zero;
      _measureStartedAt = null;
      notifyListeners();
      return;
    }

    try {
      final snoreResult = await _classifyTop5SnoreClips(rawSnoreResult);

      if (_records.isNotEmpty) {
        updateTodaySnoreData(snoreResult);
      } else {
        _addSnoreOnlyRecord(
          snoreResult,
          startedAtOverride: stoppedStartedAt,
        );
      }

      _ensureTodayRecordExists();

      selectedIndex = 0;
      measuredElapsed = Duration.zero;
      _measureStartedAt = null;
    } catch (e) {
      snoreError = '측정 결과 저장/AI 판별 실패: $e';
    } finally {
      _stoppingMeasurement = false;
      notifyListeners();
    }
  }

  Future<void> _classifyClipAndNotifyDuringMeasurement(
    SnoreAudioClip clip,
    int token,
  ) async {
    if (!measuring || _stoppingMeasurement || token != _measureSessionToken) {
      return;
    }

    if (userId == null || userId!.isEmpty) {
      debugPrint('실시간 코골이 AI 판별 생략: userId 없음');
      return;
    }

    try {
      final file = File(clip.path);

      if (!await file.exists()) {
        debugPrint('실시간 코골이 AI 판별 생략: 파일 없음 ${clip.path}');
        return;
      }

      if (!measuring || _stoppingMeasurement || token != _measureSessionToken) {
        return;
      }

      final result = await AIService().predict(
        userId: userId!,
        wavFile: file,
        save: false,
      );

      final snoringProbability = _toDouble(result['snoring_probability']);
      final isSnoring = _isAiSnoringResult(result);
      final votesText = _votesText(result);

      debugPrint(
        '실시간 5초 조각 AI 판별: ${clip.time} / '
        '최종확률 ${snoringProbability.toStringAsFixed(4)} '
        '$votesText / '
        '${isSnoring ? '코골이 O' : '코골이 X'}',
      );

      if (isSnoring) {
        await _notifySnoringIfNeeded(result);
      }
    } catch (e) {
      if (!measuring || _stoppingMeasurement || token != _measureSessionToken) {
        return;
      }

      debugPrint('실시간 코골이 AI 판별 실패: $e');
    }
  }

  Future<SnoreMeasureResult> _classifyTop5SnoreClips(
    SnoreMeasureResult rawResult,
  ) async {
    if (rawResult.audioClips.isEmpty) {
      snoreAiDebugText = 'AI 판별 결과: 분석할 5초 녹음 조각이 없습니다. 최소 6초 이상 측정해보세요.';
      return rawResult;
    }

    if (userId == null || userId!.isEmpty) {
      snoreError = '코골이 AI 판별을 하려면 카카오 로그인이 필요합니다.';
      snoreAiDebugText =
          'AI 판별 불가: userId가 없습니다. 카카오 로그인과 DB 사용자 저장을 먼저 확인하세요.';

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

        final snoringProbability = _toDouble(result['snoring_probability']);
        final isSnoring = _isAiSnoringResult(result);
        final votesText = _votesText(result);
        final noiseText = _noiseLabelsText(result['noise']);
        final judgmentText = isSnoring ? '코골이 O' : '코골이 X';
        final aiWindowSeconds = _aiDisplayDurationSeconds(clip);

        debugLines.add(
          '${i + 1}. ${clip.time} / AI ${aiWindowSeconds}초 / '
          '평균 ${clip.avgDb.toStringAsFixed(1)}dB / '
          '최대 ${clip.maxDb.toStringAsFixed(1)}dB / '
          'AI확률 ${snoringProbability.toStringAsFixed(4)} '
          '$votesText / '
          '판정 $judgmentText / '
          'noise: $noiseText',
        );

        if (isSnoring) {
          detected.add(
            _ClassifiedSnoreClip(
              index: i,
              clip: clip,
              probability: snoringProbability,
            ),
          );
        }
      } catch (e) {
        lastError = e;
        debugLines.add(
          '${i + 1}. ${clip.time} / AI ${_aiDisplayDurationSeconds(clip)}초 / AI 호출 실패: $e',
        );
      }
    }

    if (detected.isEmpty) {
      snoreAiDebugText = 'AI 판별 결과\n'
          '총 ${rawResult.audioClips.length}개 조각 분석 / 코골이 0개\n'
          '백엔드 AI 판정 결과\n\n'
          '${debugLines.join('\n')}';

      if (lastError != null) {
        snoreError = '코골이 AI 판별 실패: $lastError';
      } else {
        snoreError = 'AI가 코골이로 판단한 5초 녹음이 없습니다. 아래 AI 판별 결과를 확인해보세요.';
      }

      await _deleteLocalClipFiles(rawResult.audioClips);

      return _buildResultWithAiClips(
        rawResult: rawResult,
        aiDetectedClips: const [],
        top5Clips: const [],
      );
    }

    final top5 = detected.toList()
      ..sort((a, b) {
        final dbCompare = b.clip.maxDb.compareTo(a.clip.maxDb);
        if (dbCompare != 0) return dbCompare;

        return a.index.compareTo(b.index);
      });

    final selected = top5.take(5).toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    final selectedClips = selected.map((item) => item.clip).toList();

    snoreAiDebugText = 'AI 판별 결과\n'
        '총 ${rawResult.audioClips.length}개 조각 분석 / '
        '코골이 ${detected.length}개 / 화면 표시 TOP ${selected.length}개\n'
        '백엔드 AI 판정 결과\n\n'
        '${debugLines.join('\n')}';

    await _deleteUnselectedLocalClips(
      allClips: rawResult.audioClips,
      selectedClips: selectedClips,
    );

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

  int _aiDisplayDurationSeconds(SnoreAudioClip clip) {
    final seconds = clip.durationSeconds;

    if (seconds <= 0) {
      return 0;
    }

    // AI 모델은 5초 파일을 1초 단위 5개로 투표하므로,
    // 화면/통계에는 AI 판별 창 길이를 최대 5초로 표시한다.
    return seconds > 5 ? 5 : seconds;
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
      (sum, clip) => sum + _aiDisplayDurationSeconds(clip),
    );

    return SnoreMeasureResult(
      avgSnoreDb: double.parse(avgDb.toStringAsFixed(1)),
      maxSnoreDb: double.parse(maxDb.toStringAsFixed(1)),
      snoreHours: double.parse((totalSeconds / 3600).toStringAsFixed(2)),
      snoreFreqHz: rawResult.snoreFreqHz,
      snoreCount: aiDetectedClips.length,
      noiseDb: rawResult.noiseDb,
      snoreTimeline: rawResult.snoreTimeline,
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
      } catch (_) {}
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
      } catch (_) {}
    }
  }

  int _snoringVoteCount(Map<String, dynamic> result) {
    final rawVoteCount = result['snore_count'] ?? result['snoring_vote_count'];

    if (rawVoteCount is int) {
      return rawVoteCount;
    }

    return int.tryParse(rawVoteCount?.toString() ?? '') ?? 0;
  }

  int _snoringRequiredVotes(Map<String, dynamic> result) {
    final rawRequired =
        result['vote_required'] ?? result['snoring_required_votes'];

    if (rawRequired is int) {
      return rawRequired;
    }

    return int.tryParse(rawRequired?.toString() ?? '') ?? 3; // vote 기준
  }

  int _snoringTotalChunks(Map<String, dynamic> result) {
    final rawTotal = result['segment_count'] ?? result['snoring_total_chunks'];

    if (rawTotal is int) {
      return rawTotal;
    }

    return int.tryParse(rawTotal?.toString() ?? '') ?? 0;
  }

  String _votesText(Map<String, dynamic> result) {
    final total = _snoringTotalChunks(result);

    if (total <= 0) {
      return '투표 -';
    }

    return '투표 ${_snoringVoteCount(result)}/$total, 기준 ${_snoringRequiredVotes(result)}';
  }

  Future<void> _notifySnoringIfNeeded(Map<String, dynamic> result) async {
    final isSnoring = _isAiSnoringResult(result);

    if (!isSnoring) {
      return;
    }

    final now = DateTime.now();

    final canNotify = _lastSnoreNotificationAt == null ||
        now.difference(_lastSnoreNotificationAt!).inSeconds >=
            snoreNotificationCooldownSeconds;

    if (!canNotify) {
      debugPrint('코골이 감지됨 but ${snoreNotificationCooldownSeconds}초 알림 쿨다운 중');
      return;
    }

    _lastSnoreNotificationAt = now;

    final percentText =
        (_toDouble(result['snoring_probability']) * 100).toStringAsFixed(1);
    final votesText = _votesText(result);

    try {
      await SnoreNotificationService.showSnoreAlert(
        title: '코골이 감지',
        body: '코골이가 감지되었습니다. 자세를 바꿔보세요. 감지 확률 $percentText% ($votesText)',
      );

      debugPrint('코골이 감지 → 폰/워치 진동 알림 실행');
    } catch (e) {
      debugPrint('코골이 알림 실행 실패: $e');
    }
  }

  bool _isAiSnoringResult(Map<String, dynamic> result) {
    return result["snoring"] == true;
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

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  void _addSnoreOnlyRecord(
    SnoreMeasureResult snoreResult, {
    DateTime? startedAtOverride,
  }) {
    final start = startedAtOverride ?? _measureStartedAt ?? DateTime.now();
    final end = DateTime.now();

    final timeline = snoreResult.snoreTimeline.isEmpty
        ? const <SnorePoint>[]
        : snoreResult.snoreTimeline;

    _records.insert(
      0,
      SleepRecord(
        date: DateTime.now(),
        score: 0,
        bedtimeTarget: bedtimeTarget,
        wakeTarget: wakeTarget,
        bedtimeActual: _formatTime(start),
        wakeActual: _formatTime(end),
        totalSleepHours: 0,
        targetSleepHours: _parseHours(bedtimeTarget, wakeTarget),
        avgSnoreDb: snoreResult.avgSnoreDb,
        maxSnoreDb: snoreResult.maxSnoreDb,
        snoreHours: snoreResult.snoreHours,
        snoreFreqHz: snoreResult.snoreFreqHz,
        snoreCount: snoreResult.snoreCount,
        noiseDb: snoreResult.noiseDb,
        snoreTimeline: timeline,
        snoreAudioClips: snoreResult.audioClips,
        stages: const [],
      ),
    );
  }

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
      avgSnoreDb: snoreResult.avgSnoreDb,
      maxSnoreDb: snoreResult.maxSnoreDb,
      snoreHours: snoreResult.snoreHours,
      snoreFreqHz: snoreResult.snoreFreqHz,
      snoreCount: snoreResult.snoreCount,
      noiseDb: snoreResult.noiseDb,
      snoreTimeline: snoreResult.snoreTimeline.isEmpty
          ? old.snoreTimeline
          : snoreResult.snoreTimeline,
      snoreAudioClips: snoreResult.audioClips.isEmpty
          ? old.snoreAudioClips
          : snoreResult.audioClips,
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

  void _ensureTodayRecordExists() {
    final todayKey = _dateKey(DateTime.now());

    final hasToday = _records.any((r) => _dateKey(r.date) == todayKey);

    if (!hasToday) {
      _records.insert(0, _emptyRecordForDate(DateTime.now()));
      selectedIndex = 0;
    }
  }

  SleepRecord _emptyRecordForDate(DateTime date) {
    return SleepRecord(
      date: date,
      score: 0,
      bedtimeTarget: bedtimeTarget,
      wakeTarget: wakeTarget,
      bedtimeActual: '--:--',
      wakeActual: '--:--',
      totalSleepHours: 0,
      targetSleepHours: _parseHours(bedtimeTarget, wakeTarget),
      avgSnoreDb: 0,
      maxSnoreDb: 0,
      snoreHours: 0,
      snoreFreqHz: 0,
      snoreCount: 0,
      noiseDb: 0,
      stages: const [],
      snoreTimeline: const [],
      snoreAudioClips: const [],
    );
  }

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
    _measureSessionToken++;
    measuring = false;
    _stoppingMeasurement = false;

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
// 월별 통계
// =========================

const List<MonthlyRecord> monthlyRecords = [];
