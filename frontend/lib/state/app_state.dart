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
import '../services/snore_history_service.dart';
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
  final SnoreHistoryService _snoreHistoryService = SnoreHistoryService();

  String? snoreError;
  String? snoreAiDebugText;

  DateTime? _lastSnoreNotificationAt;

  // 측정 중 이미 완료된 AI 판별 결과를 보관한다.
  // 측정 종료 시 모든 녹음 조각을 서버에 다시 보내지 않기 위해 사용한다.
  final Map<String, _LiveAiClipResult> _liveAiResults = {};
  final Set<Future<void>> _pendingLiveAiTasks = {};

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

  bool snoreHistoryLoading = false;
  String? snoreHistoryError;

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

  /// 오늘 날짜에 이미 코골이 리포트가 저장되어 있는지 확인한다.
  /// 수면 데이터만 있고 코골이 결과가 없는 경우에는 false이다.
  bool get hasTodaySnoreReport {
    final todayRecord = _findRecordByDate(DateTime.now());

    if (todayRecord == null) {
      return false;
    }

    return todayRecord.snoreCount > 0 ||
        todayRecord.snoreHours > 0 ||
        todayRecord.avgSnoreDb > 0 ||
        todayRecord.maxSnoreDb > 0 ||
        todayRecord.noiseDb > 0 ||
        todayRecord.snoreTimeline.isNotEmpty ||
        todayRecord.snoreAudioClips.isNotEmpty;
  }

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
      final Map<String, HealthSleepSummary> longestPerDate = {};

      for (final result in rawHistory) {
        final key = _dateKey(result.date);
        final existing = longestPerDate[key];

        if (existing == null ||
            result.totalSleepMinutes > existing.totalSleepMinutes) {
          longestPerDate[key] = result;
        }
      }

      final List<HealthSleepSummary> history =
          longestPerDate.values.toList();

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

        final List<SleepStage> stages = result.stages.isNotEmpty
            ? result.stages.map<SleepStage>((stage) {
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

      // Health Connect에 수면 기록이 없는 날짜라도
      // 기존 코골이 측정 결과는 지우지 않고 유지한다.
      final newDateKeys = newRecords
          .map((record) => _dateKey(record.date))
          .toSet();

      final snoreOnlyRecords = oldByDate.values.where((record) {
        final key = _dateKey(record.date);

        final hasSnoreData = record.snoreCount > 0 ||
            record.snoreHours > 0 ||
            record.avgSnoreDb > 0 ||
            record.maxSnoreDb > 0 ||
            record.noiseDb > 0 ||
            record.snoreTimeline.isNotEmpty ||
            record.snoreAudioClips.isNotEmpty;

        return !newDateKeys.contains(key) && hasSnoreData;
      }).toList();

      _records
        ..clear()
        ..addAll(newRecords)
        ..addAll(snoreOnlyRecords);

      _sortRecordsNewestFirst();
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
    await loadSnoreHistory(days: 90);
    await loadApneaRiskHistory(nights: nights);
  }

  Future<void> loadSnoreHistory({int days = 90}) async {
    final currentUserId = userId;

    if (currentUserId == null || currentUserId.isEmpty || snoreHistoryLoading) {
      return;
    }

    snoreHistoryLoading = true;
    snoreHistoryError = null;
    notifyListeners();

    try {
      final summaries = await _snoreHistoryService.fetchSummaries(
        userId: currentUserId,
        days: days,
      );

      for (final summary in summaries) {
        _mergeSnoreSummary(summary);
      }

      _sortRecordsNewestFirst();
      selectedIndex = 0;
    } catch (e) {
      snoreHistoryError = e.toString();
    } finally {
      snoreHistoryLoading = false;
      notifyListeners();
    }
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
      _liveAiResults.clear();
      _pendingLiveAiTasks.clear();

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
          late final Future<void> task;

          task = _classifyClipAndNotifyDuringMeasurement(
            clip,
            token,
          ).whenComplete(() {
            _pendingLiveAiTasks.remove(task);
          });

          _pendingLiveAiTasks.add(task);
          return task;
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

    // 새 측정은 _stoppingMeasurement로 막혀 있으므로,
    // 측정 중 이미 시작된 AI 요청은 잠시 기다려 결과를 재사용한다.
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
      // 측정 중 진행된 AI 요청이 끝날 시간을 잠깐 준다.
      // 오래 걸리거나 끊긴 요청은 15초 후 포기하고,
      // 아직 판별되지 않은 마지막 조각만 종료 단계에서 추가 판별한다.
      if (_pendingLiveAiTasks.isNotEmpty) {
        try {
          await Future.wait(
            List<Future<void>>.from(_pendingLiveAiTasks),
          ).timeout(const Duration(seconds: 15));
        } catch (_) {}
      }

      _measureSessionToken++;

      final snoreResult = await _classifyTop5SnoreClips(rawSnoreResult);

      updateTodaySnoreData(
        snoreResult,
        startedAtOverride: stoppedStartedAt,
      );

      _ensureTodayRecordExists();
      _sortRecordsNewestFirst();
      selectedIndex = 0;

      final currentUserId = userId;
      if (currentUserId != null && currentUserId.isNotEmpty) {
        final todayRecord = _findRecordByDate(DateTime.now());

        if (todayRecord != null) {
          try {
            await _snoreHistoryService.saveDailySummary(
              userId: currentUserId,
              record: todayRecord,
            );
          } catch (e) {
            // 화면의 오늘 기록은 유지하고 서버 저장 실패만 안내한다.
            snoreHistoryError = e.toString();
            snoreError = '측정 결과는 기기에 반영됐지만 서버 저장에 실패했습니다.';
          }
        }
      } else {
        snoreError = '측정 결과는 기기에 반영됐지만 로그인하지 않아 서버에 저장되지 않았습니다.';
      }

      measuredElapsed = Duration.zero;
      _measureStartedAt = null;
    } catch (e) {
      final previousDebug = snoreAiDebugText?.trim();

      snoreAiDebugText = previousDebug == null || previousDebug.isEmpty
          ? 'AI 판별 오류\n$e'
          : '$previousDebug\n\nAI 판별 오류\n$e';

      snoreError = null;
    } finally {
      _stoppingMeasurement = false;
      notifyListeners();
    }
  }

  Future<void> _classifyClipAndNotifyDuringMeasurement(
    SnoreAudioClip clip,
    int token,
  ) async {
    if (token != _measureSessionToken) {
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

      final result = await AIService().predict(
        userId: userId!,
        wavFile: file,
        save: false,
      );

      if (token != _measureSessionToken) {
        return;
      }

      final snoringProbability = _snoringDisplayProbability(result);
      final isSnoring = _isAiSnoringResult(result);
      final votesText = _votesText(result);
      final noiseText = _noiseLabelsText(result['noise']);
      final aiWindowSeconds = _aiDisplayDurationSeconds(clip);

      final debugLine =
          '${clip.time} / AI ${aiWindowSeconds}초 / '
          '평균 ${clip.avgDb.toStringAsFixed(1)}dB / '
          '최대 ${clip.maxDb.toStringAsFixed(1)}dB / '
          'AI확률 ${snoringProbability.toStringAsFixed(4)} '
          '$votesText / '
          '판정 ${isSnoring ? '코골이 O' : '코골이 X'} / '
          'noise: $noiseText';

      _liveAiResults[clip.path] = _LiveAiClipResult(
        clip: clip,
        probability: snoringProbability,
        isSnoring: isSnoring,
        debugLine: debugLine,
      );

      debugPrint('실시간 AI 판별 완료: $debugLine');

      // 저장 중에는 진동 알림을 울리지 않고 결과만 보관한다.
      if (isSnoring && measuring && !_stoppingMeasurement) {
        await _notifySnoringIfNeeded(result);
      }
    } catch (e) {
      if (token != _measureSessionToken) {
        return;
      }

      _liveAiResults[clip.path] = _LiveAiClipResult(
        clip: clip,
        probability: 0,
        isSnoring: false,
        debugLine:
            '${clip.time} / AI ${_aiDisplayDurationSeconds(clip)}초 / AI 호출 실패: $e',
        error: e,
      );

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
      snoreError = null;
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
      final cached = _liveAiResults[clip.path];

      if (cached != null) {
        debugLines.add('${i + 1}. ${cached.debugLine}');

        if (cached.error != null) {
          lastError = cached.error;
        }

        if (cached.isSnoring) {
          detected.add(
            _ClassifiedSnoreClip(
              index: i,
              clip: clip,
              probability: cached.probability,
            ),
          );
        }

        continue;
      }

      // 측정 종료 직전에 만들어진 마지막 조각처럼
      // 실시간 판별이 없었던 파일만 여기서 한 번 추가 판별한다.
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

        final snoringProbability = _snoringDisplayProbability(result);
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

      // AI 연결 실패나 판별 상세 오류는 일반 화면에 표시하지 않는다.
      // 상세 내용은 숨겨진 AI 버튼에서 확인한다.
      if (lastError != null) {
        snoreAiDebugText = '$snoreAiDebugText\n\n'
            '연결 오류 상세\n$lastError';
      }

      snoreError = null;

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

    // 측정 중 이미 AI 판별을 완료했으므로 TOP 5 파일을 /predict로
    // 다시 업로드하지 않는다. 일일 요약은 /snore-summaries에 한 번만 저장한다.
    if (lastError != null) {
      debugPrint('일부 실시간 AI 판별 실패: $lastError');
    }

    snoreError = null;

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
      // 5초처럼 짧은 코골이도 0시간으로 반올림되지 않도록
      // 소수점 넷째 자리까지 보존한다.
      snoreHours: double.parse((totalSeconds / 3600).toStringAsFixed(4)),
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
        (_snoringDisplayProbability(result) * 100).toStringAsFixed(1);
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

  /*bool _isAiSnoringResult(Map<String, dynamic> result) {
    return result["snoring"] == true;
  }*/
  bool _isAiSnoringResult(Map<String, dynamic> result) {
    if (result.containsKey('snoring_detected')) {
      return result['snoring_detected'] == true;
    }

    return result['snoring'] == true;
  }

  double _snoringDisplayProbability(Map<String, dynamic> result) {
    if (result.containsKey('avg_snoring_probability')) {
      return _toDouble(result['avg_snoring_probability']);
    }

    return _toDouble(result['snoring_probability']);
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

  void updateTodaySnoreData(
    SnoreMeasureResult snoreResult, {
    DateTime? startedAtOverride,
  }) {
    final today = DateTime.now();
    var index = _records.indexWhere(
      (record) => _dateKey(record.date) == _dateKey(today),
    );

    if (index < 0) {
      _records.insert(0, _emptyRecordForDate(today));
      index = 0;
    }

    final old = _records[index];
    final startedAt = startedAtOverride ?? _measureStartedAt;
    final endedAt = DateTime.now();

    _records[index] = SleepRecord(
      date: old.date,
      score: old.score,
      bedtimeTarget: old.bedtimeTarget,
      wakeTarget: old.wakeTarget,
      bedtimeActual: old.bedtimeActual == '--:--' && startedAt != null
          ? _formatTime(startedAt)
          : old.bedtimeActual,
      wakeActual: old.wakeActual == '--:--'
          ? _formatTime(endedAt)
          : old.wakeActual,
      totalSleepHours: old.totalSleepHours,
      targetSleepHours: old.targetSleepHours,
      avgSnoreDb: snoreResult.avgSnoreDb,
      maxSnoreDb: snoreResult.maxSnoreDb,
      snoreHours: snoreResult.snoreHours,
      snoreFreqHz: snoreResult.snoreFreqHz,
      snoreCount: snoreResult.snoreCount,
      noiseDb: snoreResult.noiseDb,
      // 재측정 결과는 비어 있더라도 오늘의 기존 결과를 완전히 교체한다.
      // 새 측정에서 코골이가 0건이면 이전 타임라인/녹음도 남기지 않는다.
      snoreTimeline: snoreResult.snoreTimeline,
      snoreAudioClips: snoreResult.audioClips,
      stages: old.stages,
    );

    notifyListeners();
  }

  void _mergeSnoreSummary(SnoreDailySummary summary) {
    final index = _records.indexWhere(
      (record) => _dateKey(record.date) == _dateKey(summary.date),
    );

    final old = index >= 0 ? _records[index] : _emptyRecordForDate(summary.date);

    final merged = SleepRecord(
      date: old.date,
      score: old.score,
      bedtimeTarget: old.bedtimeTarget,
      wakeTarget: old.wakeTarget,
      bedtimeActual: old.bedtimeActual,
      wakeActual: old.wakeActual,
      totalSleepHours: old.totalSleepHours,
      targetSleepHours: old.targetSleepHours,
      avgSnoreDb: summary.avgSnoreDb,
      maxSnoreDb: summary.maxSnoreDb,
      snoreHours: summary.snoreHours,
      snoreFreqHz: summary.snoreFreqHz,
      snoreCount: summary.snoreCount,
      noiseDb: summary.noiseDb,
      snoreTimeline: summary.snoreTimeline,
      snoreAudioClips: summary.snoreAudioClips,
      stages: old.stages,
    );

    if (index >= 0) {
      _records[index] = merged;
    } else {
      _records.add(merged);
    }
  }

  SleepRecord? _findRecordByDate(DateTime date) {
    for (final record in _records) {
      if (_dateKey(record.date) == _dateKey(date)) {
        return record;
      }
    }
    return null;
  }

  void _sortRecordsNewestFirst() {
    _records.sort((a, b) => b.date.compareTo(a.date));
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

  List<MonthlyRecord> get monthlyRecords {
    final now = DateTime.now();

    final months = List<DateTime>.generate(3, (index) {
      final monthsAgo = 2 - index;

      return DateTime(
        now.year,
        now.month - monthsAgo,
        1,
      );
    });

    const fallbackScores = [72, 78, 84];
    const fallbackSleepHours = [6.4, 6.9, 7.3];
    const fallbackNoiseDb = [41.2, 38.7, 35.4];
    const fallbackDeficitHours = [1.6, 1.1, 0.7];

    return List<MonthlyRecord>.generate(
      months.length,
      (index) {
        final month = months[index];

        final actualRecords = _records.where((record) {
          return record.date.year == month.year &&
              record.date.month == month.month &&
              record.totalSleepHours > 0;
        }).toList();

        if (actualRecords.isEmpty) {
          return MonthlyRecord(
            '${month.month}월',
            fallbackScores[index],
            fallbackSleepHours[index],
            fallbackNoiseDb[index],
            fallbackDeficitHours[index],
          );
        }

        final avgScore = actualRecords.fold<double>(
              0,
              (sum, record) => sum + record.score,
            ) /
            actualRecords.length;

        final avgSleepHours = actualRecords.fold<double>(
              0,
              (sum, record) => sum + record.totalSleepHours,
            ) /
            actualRecords.length;

        final avgNoiseDb = actualRecords.fold<double>(
              0,
              (sum, record) => sum + record.noiseDb,
            ) /
            actualRecords.length;

        final avgDeficitHours = actualRecords.fold<double>(
              0,
              (sum, record) {
                final deficit = record.sleepDeficitHours;
                return sum + (deficit > 0 ? deficit : 0);
              },
            ) /
            actualRecords.length;

        return MonthlyRecord(
          '${month.month}월',
          avgScore.round().clamp(0, 100),
          double.parse(avgSleepHours.toStringAsFixed(1)),
          double.parse(avgNoiseDb.toStringAsFixed(1)),
          double.parse(avgDeficitHours.toStringAsFixed(1)),
        );
      },
    );
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

class _LiveAiClipResult {
  final SnoreAudioClip clip;
  final double probability;
  final bool isSnoring;
  final String debugLine;
  final Object? error;

  const _LiveAiClipResult({
    required this.clip,
    required this.probability,
    required this.isSnoring,
    required this.debugLine,
    this.error,
  });
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
