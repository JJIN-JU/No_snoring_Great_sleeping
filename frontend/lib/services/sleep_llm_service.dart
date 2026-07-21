import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/sleep_tag_result.dart';
import 'api_server_manager.dart';

class SleepLlmException implements Exception {
  final String message;

  const SleepLlmException(this.message);

  @override
  String toString() => message;
}

class SleepLlmService {
  static final http.Client _sharedClient = http.Client();

  // 같은 분석 데이터에 대한 완료 결과를 앱 실행 중 보관한다.
  static final Map<String, SleepTagAnalysis> _resultCache = {};

  // 같은 요청이 동시에 두 번 전송되는 것을 막는다.
  static final Map<String, Future<SleepTagAnalysis>> _pendingRequests = {};

  final http.Client _client;
  final bool _usesSharedClient;

  SleepLlmService({
    http.Client? client,
  })  : _client = client ?? _sharedClient,
        _usesSharedClient = client == null;

  static String cacheKeyFor(
    SleepTagAnalysis analysis,
  ) {
    return jsonEncode(
      analysis.toLlmRequestJson(),
    );
  }

  static SleepTagAnalysis? peekCachedAnalysis(
    SleepTagAnalysis baseAnalysis,
  ) {
    return _resultCache[
      cacheKeyFor(baseAnalysis)
    ];
  }

  static bool hasCachedAnalysis(
    SleepTagAnalysis baseAnalysis,
  ) {
    return peekCachedAnalysis(baseAnalysis) != null;
  }

  Future<SleepTagAnalysis> generateAnalysis({
    required SleepTagAnalysis baseAnalysis,
    bool forceRefresh = false,
  }) async {
    if (!baseAnalysis.hasData) {
      throw const SleepLlmException(
        '분석할 수면 기록이 없습니다.',
      );
    }

    if (baseAnalysis.tags.isEmpty) {
      throw const SleepLlmException(
        'AI에 전달할 수면 태그가 없습니다.',
      );
    }

    final requestJson =
        baseAnalysis.toLlmRequestJson();

    final cacheKey = jsonEncode(requestJson);

    if (forceRefresh) {
      _resultCache.remove(cacheKey);
      _pendingRequests.remove(cacheKey);
    }

    final cached = _resultCache[cacheKey];

    if (cached != null) {
      debugPrint(
        '[SLEEP LLM] 기존 분석 결과 사용',
      );

      return cached;
    }

    final pending = _pendingRequests[cacheKey];

    if (pending != null) {
      debugPrint(
        '[SLEEP LLM] 진행 중인 요청 재사용',
      );

      return pending;
    }

    final future = _requestAnalysis(
      baseAnalysis: baseAnalysis,
      requestJson: requestJson,
    );

    _pendingRequests[cacheKey] = future;

    try {
      final result = await future;

      _resultCache[cacheKey] = result;

      return result;
    } finally {
      _pendingRequests.remove(cacheKey);
    }
  }

  Future<SleepTagAnalysis> _requestAnalysis({
    required SleepTagAnalysis baseAnalysis,
    required Map<String, dynamic> requestJson,
  }) async {
    try {
      final baseUrl =
          await ApiServerManager.findAvailableServer();

      final uri = Uri.parse(
        '$baseUrl/sleep-tags/llm-analysis',
      );

      debugPrint(
        '[SLEEP LLM] 요청 서버: $baseUrl',
      );

      final response = await _client
          .post(
            uri,
            headers: const {
              'Content-Type':
                  'application/json; charset=UTF-8',
              'Accept': 'application/json',
            },
            body: jsonEncode(requestJson),
          )
          .timeout(
            const Duration(seconds: 60),
          );

      final responseText = utf8.decode(
        response.bodyBytes,
      );

      debugPrint(
        '[SLEEP LLM] 응답 코드: '
        '${response.statusCode}',
      );

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        if (response.statusCode == 404 ||
            response.statusCode >= 500) {
          ApiServerManager.reset();
        }

        throw SleepLlmException(
          _extractErrorMessage(responseText),
        );
      }

      final decoded = jsonDecode(responseText);

      if (decoded is! Map) {
        throw const SleepLlmException(
          'AI 서버의 응답 형식이 올바르지 않습니다.',
        );
      }

      final llmResult = SleepLlmResult.fromJson(
        Map<String, dynamic>.from(decoded),
      );

      if (llmResult.overallSummary
          .trim()
          .isEmpty) {
        throw const SleepLlmException(
          'AI가 종합 분석 내용을 반환하지 않았습니다.',
        );
      }

      return llmResult.applyTo(baseAnalysis);
    } on TimeoutException {
      ApiServerManager.reset();

      throw const SleepLlmException(
        'AI 맞춤 분석 요청 시간이 초과되었습니다.',
      );
    } on SleepLlmException {
      rethrow;
    } on FormatException {
      throw const SleepLlmException(
        'AI 서버 응답을 읽을 수 없습니다.',
      );
    } catch (error) {
      ApiServerManager.reset();

      throw SleepLlmException(
        'AI 분석 서버에 연결할 수 없습니다.\n$error',
      );
    }
  }

  String _extractErrorMessage(
    String responseText,
  ) {
    try {
      final decoded = jsonDecode(responseText);

      if (decoded is Map) {
        final detail = decoded['detail'];

        if (detail != null) {
          return detail.toString();
        }
      }
    } catch (_) {
      // JSON이 아니면 아래 기본 메시지 사용
    }

    return 'AI 맞춤 수면 분석을 생성하지 못했습니다.';
  }

  static void clearCacheFor(
    SleepTagAnalysis analysis,
  ) {
    final key = cacheKeyFor(analysis);

    _resultCache.remove(key);
    _pendingRequests.remove(key);
  }

  static void clearAllCache() {
    _resultCache.clear();
    _pendingRequests.clear();
  }

  void dispose() {
    // 기본 생성자는 공유 클라이언트를 사용하므로 닫지 않는다.
    // 테스트 등에서 외부 클라이언트를 전달한 경우에만 닫는다.
    if (!_usesSharedClient) {
      _client.close();
    }
  }
}
