enum SleepTagSeverity {
  good,
  caution,
  attention,
}

class SleepTagResult {
  final String name;

  /// 규칙 기반으로 만든 기본 설명
  final String description;

  final SleepTagSeverity severity;

  /// 실제 데이터로 계산한 분석 근거
  final List<String> evidence;

  /// LLM이 만든 개인화 해석
  final String aiInterpretation;

  /// LLM이 만든 개인화 개선 방법
  final List<String> recommendations;

  /// LLM이 만든 태그별 주간 목표
  final String weeklyGoal;

  const SleepTagResult({
    required this.name,
    required this.description,
    required this.severity,
    required this.evidence,
    this.aiInterpretation = '',
    this.recommendations = const [],
    this.weeklyGoal = '',
  });

  String get displayDescription {
    if (aiInterpretation.trim().isNotEmpty) {
      return aiInterpretation.trim();
    }

    return description;
  }

  bool get hasAiAdvice => recommendations.isNotEmpty;

  SleepTagResult copyWith({
    String? name,
    String? description,
    SleepTagSeverity? severity,
    List<String>? evidence,
    String? aiInterpretation,
    List<String>? recommendations,
    String? weeklyGoal,
  }) {
    return SleepTagResult(
      name: name ?? this.name,
      description: description ?? this.description,
      severity: severity ?? this.severity,
      evidence: evidence ?? this.evidence,
      aiInterpretation: aiInterpretation ?? this.aiInterpretation,
      recommendations: recommendations ?? this.recommendations,
      weeklyGoal: weeklyGoal ?? this.weeklyGoal,
    );
  }
}

class SleepTagAnalysis {
  final DateTime? periodStart;
  final DateTime? periodEnd;

  final int sourceRecordCount;
  final int sleepRecordCount;
  final int snoreRecordCount;

  final double averageSleepHours;
  final double averageTargetSleepHours;

  final String averageBedtime;
  final String averageWakeTime;

  final int snoreDays;
  final int totalSnoreCount;
  final double totalSnoreHours;
  final double averageSnoreRatio;

  final String overallStatus;
  final SleepTagSeverity overallSeverity;

  /// LLM 호출 전에는 안내 문구,
  /// 호출 후에는 LLM 종합 분석 내용
  final String summary;

  final List<SleepTagResult> tags;

  /// LLM이 생성한 실천 목표
  final List<String> weeklyGoals;

  /// 의료 진단이 아니라는 안내
  final String cautionNote;

  const SleepTagAnalysis({
    required this.periodStart,
    required this.periodEnd,
    required this.sourceRecordCount,
    required this.sleepRecordCount,
    required this.snoreRecordCount,
    required this.averageSleepHours,
    required this.averageTargetSleepHours,
    required this.averageBedtime,
    required this.averageWakeTime,
    required this.snoreDays,
    required this.totalSnoreCount,
    required this.totalSnoreHours,
    required this.averageSnoreRatio,
    required this.overallStatus,
    required this.overallSeverity,
    required this.summary,
    required this.tags,
    required this.weeklyGoals,
    required this.cautionNote,
  });

  bool get hasData => sourceRecordCount > 0;

  bool get hasAiAnalysis {
    return summary.trim().isNotEmpty &&
        weeklyGoals.isNotEmpty &&
        tags.any((tag) => tag.recommendations.isNotEmpty);
  }

  String get periodText {
    if (periodStart == null || periodEnd == null) {
      return '분석 기록 없음';
    }

    return '${_formatDate(periodStart!)} ~ ${_formatDate(periodEnd!)}';
  }

  Map<String, dynamic> toLlmRequestJson() {
    return {
      'metrics': {
        'analysis_period': periodText,
        'record_count': sourceRecordCount,
        'sleep_record_count': sleepRecordCount,
        'snore_record_count': snoreRecordCount,
        'average_sleep_hours': averageSleepHours,
        'target_sleep_hours': averageTargetSleepHours,
        'average_bedtime': averageBedtime,
        'average_wake_time': averageWakeTime,
        'snore_days': snoreDays,
        'total_snore_count': totalSnoreCount,
        'total_snore_hours': totalSnoreHours,
        'average_snore_ratio': averageSnoreRatio,
      },
      'tags': tags.map((tag) {
        return {
          'name': tag.name,
          'severity': _severityToApi(tag.severity),
          'description': tag.description,
          'evidence': tag.evidence,
        };
      }).toList(),
    };
  }

  SleepTagAnalysis copyWith({
    DateTime? periodStart,
    DateTime? periodEnd,
    int? sourceRecordCount,
    int? sleepRecordCount,
    int? snoreRecordCount,
    double? averageSleepHours,
    double? averageTargetSleepHours,
    String? averageBedtime,
    String? averageWakeTime,
    int? snoreDays,
    int? totalSnoreCount,
    double? totalSnoreHours,
    double? averageSnoreRatio,
    String? overallStatus,
    SleepTagSeverity? overallSeverity,
    String? summary,
    List<SleepTagResult>? tags,
    List<String>? weeklyGoals,
    String? cautionNote,
  }) {
    return SleepTagAnalysis(
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      sourceRecordCount: sourceRecordCount ?? this.sourceRecordCount,
      sleepRecordCount: sleepRecordCount ?? this.sleepRecordCount,
      snoreRecordCount: snoreRecordCount ?? this.snoreRecordCount,
      averageSleepHours: averageSleepHours ?? this.averageSleepHours,
      averageTargetSleepHours:
          averageTargetSleepHours ?? this.averageTargetSleepHours,
      averageBedtime: averageBedtime ?? this.averageBedtime,
      averageWakeTime: averageWakeTime ?? this.averageWakeTime,
      snoreDays: snoreDays ?? this.snoreDays,
      totalSnoreCount: totalSnoreCount ?? this.totalSnoreCount,
      totalSnoreHours: totalSnoreHours ?? this.totalSnoreHours,
      averageSnoreRatio: averageSnoreRatio ?? this.averageSnoreRatio,
      overallStatus: overallStatus ?? this.overallStatus,
      overallSeverity: overallSeverity ?? this.overallSeverity,
      summary: summary ?? this.summary,
      tags: tags ?? this.tags,
      weeklyGoals: weeklyGoals ?? this.weeklyGoals,
      cautionNote: cautionNote ?? this.cautionNote,
    );
  }

  static String _formatDate(DateTime date) {
    return '${date.year}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static String _severityToApi(SleepTagSeverity severity) {
    switch (severity) {
      case SleepTagSeverity.good:
        return 'good';

      case SleepTagSeverity.caution:
        return 'caution';

      case SleepTagSeverity.attention:
        return 'attention';
    }
  }
}

class SleepLlmTagAdvice {
  final String tagName;
  final String personalizedInterpretation;
  final List<String> recommendations;
  final String weeklyGoal;

  const SleepLlmTagAdvice({
    required this.tagName,
    required this.personalizedInterpretation,
    required this.recommendations,
    required this.weeklyGoal,
  });

  factory SleepLlmTagAdvice.fromJson(Map<String, dynamic> json) {
    return SleepLlmTagAdvice(
      tagName: json['tag_name']?.toString() ?? '',
      personalizedInterpretation:
          json['personalized_interpretation']?.toString() ?? '',
      recommendations: _stringList(json['recommendations']),
      weeklyGoal: json['weekly_goal']?.toString() ?? '',
    );
  }
}

class SleepLlmResult {
  final String overallSummary;
  final List<SleepLlmTagAdvice> tagAdvices;
  final List<String> weeklyGoals;
  final String cautionNote;

  const SleepLlmResult({
    required this.overallSummary,
    required this.tagAdvices,
    required this.weeklyGoals,
    required this.cautionNote,
  });

  factory SleepLlmResult.fromJson(Map<String, dynamic> json) {
    final rawAdvices = json['tag_advices'];

    final advices = <SleepLlmTagAdvice>[];

    if (rawAdvices is List) {
      for (final item in rawAdvices) {
        if (item is Map) {
          advices.add(
            SleepLlmTagAdvice.fromJson(
              Map<String, dynamic>.from(item),
            ),
          );
        }
      }
    }

    return SleepLlmResult(
      overallSummary: json['overall_summary']?.toString() ?? '',
      tagAdvices: advices,
      weeklyGoals: _stringList(json['weekly_goals']),
      cautionNote: json['caution_note']?.toString() ?? '',
    );
  }

  SleepTagAnalysis applyTo(SleepTagAnalysis baseAnalysis) {
    final adviceByTagName = <String, SleepLlmTagAdvice>{
      for (final advice in tagAdvices) advice.tagName: advice,
    };

    final mergedTags = baseAnalysis.tags.map((tag) {
      final advice = adviceByTagName[tag.name];

      if (advice == null) {
        return tag;
      }

      return tag.copyWith(
        aiInterpretation: advice.personalizedInterpretation,
        recommendations: advice.recommendations,
        weeklyGoal: advice.weeklyGoal,
      );
    }).toList();

    return baseAnalysis.copyWith(
      summary: overallSummary,
      tags: mergedTags,
      weeklyGoals: weeklyGoals,
      cautionNote: cautionNote.isNotEmpty
          ? cautionNote
          : baseAnalysis.cautionNote,
    );
  }
}

List<String> _stringList(dynamic value) {
  if (value is! List) {
    return const [];
  }

  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
}