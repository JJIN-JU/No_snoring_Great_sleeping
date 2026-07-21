import 'package:flutter/material.dart';

import '../models/sleep_tag_result.dart';
import '../services/sleep_llm_service.dart';
import '../services/sleep_tag_analysis_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'sleep_report_preview_screen.dart';

class SleepTagScreen extends StatefulWidget {
  final AppState state;

  const SleepTagScreen({
    super.key,
    required this.state,
  });

  @override
  State<SleepTagScreen> createState() =>
      _SleepTagScreenState();
}

class _SleepTagScreenState extends State<SleepTagScreen> {
  final SleepLlmService _llmService = SleepLlmService();

  late SleepTagAnalysis _baseAnalysis;

  SleepTagAnalysis? _aiAnalysis;

  bool _isLoading = false;
  String? _errorMessage;

  SleepTagAnalysis get _displayAnalysis =>
      _aiAnalysis ?? _baseAnalysis;

  @override
  void initState() {
    super.initState();

    _baseAnalysis = SleepTagAnalysisService.analyze(
      widget.state.records,
    );

    // 같은 주간 데이터로 이미 분석한 결과가 있으면
    // 화면 진입 즉시 기존 결과를 사용한다.
    _aiAnalysis =
        SleepLlmService.peekCachedAnalysis(
      _baseAnalysis,
    );

    if (_aiAnalysis == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        if (_baseAnalysis.hasData &&
            _baseAnalysis.tags.isNotEmpty) {
          _loadAiAnalysis();
        }
      });
    }
  }

  Future<void> _refreshAnalysis() async {
    final refreshedBase =
        SleepTagAnalysisService.analyze(
      widget.state.records,
    );

    setState(() {
      _baseAnalysis = refreshedBase;
      _aiAnalysis = null;
      _errorMessage = null;
    });

    if (refreshedBase.hasData &&
        refreshedBase.tags.isNotEmpty) {
      await _loadAiAnalysis(
        forceRefresh: true,
      );
    }
  }

  Future<void> _loadAiAnalysis({
    bool forceRefresh = false,
  }) async {
    if (_isLoading) {
      return;
    }

    final cached =
        SleepLlmService.peekCachedAnalysis(
      _baseAnalysis,
    );

    if (!forceRefresh && cached != null) {
      setState(() {
        _aiAnalysis = cached;
        _errorMessage = null;
      });

      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;

      if (forceRefresh) {
        _aiAnalysis = null;
      }
    });

    try {
      final result = await _llmService.generateAnalysis(
        baseAnalysis: _baseAnalysis,
        forceRefresh: forceRefresh,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _aiAnalysis = result;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  void _openPdfPreview() {
    final analysis = _aiAnalysis;

    if (analysis == null) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) {
          return SleepReportPreviewScreen(
            userName: widget.state.userName,
            analysis: analysis,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _llmService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analysis = _displayAnalysis;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.foreground,
        elevation: 0,
        title: const Text(
          '내 수면 태그',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            onPressed:
                _isLoading ? null : _refreshAnalysis,
            tooltip: '다시 분석',
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAnalysis,
        color: AppColors.primary,
        child: ListView(
          physics:
              const AlwaysScrollableScrollPhysics(),
          padding:
              const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (!analysis.hasData)
              const _NoDataCard()
            else ...[
              _AnalysisSummaryCard(
                analysis: analysis,
                isAiComplete: _aiAnalysis != null,
              ),

              const SizedBox(height: 14),

              if (_isLoading)
                const _AiLoadingCard(),

              if (_errorMessage != null) ...[
                _AiErrorCard(
                  message: _errorMessage!,
                  onRetry: _loadAiAnalysis,
                ),
                const SizedBox(height: 14),
              ],

              _MetricGrid(
                analysis: analysis,
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '분석된 수면 태그',
                      style: TextStyle(
                        color: AppColors.foreground,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_aiAnalysis != null)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent
                            .withValues(alpha: 0.13),
                        borderRadius:
                            BorderRadius.circular(999),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 13,
                            color: AppColors.accent,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'AI 맞춤 분석',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 10,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 6),

              Text(
                _aiAnalysis != null
                    ? '태그를 누르면 실제 기록에 맞춰 생성된 해석과 개선 방법을 확인할 수 있습니다.'
                    : '실제 데이터로 계산한 태그와 분석 근거입니다.',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 12),

              ...analysis.tags.asMap().entries.map(
                (entry) {
                  return Padding(
                    padding:
                        const EdgeInsets.only(bottom: 12),
                    child: _SleepTagCard(
                      tag: entry.value,
                      initiallyExpanded:
                          entry.key == 0,
                      isAiLoading: _isLoading,
                    ),
                  );
                },
              ),

              if (analysis.weeklyGoals.isNotEmpty) ...[
                const SizedBox(height: 2),
                _WeeklyGoalCard(
                  goals: analysis.weeklyGoals,
                ),
                const SizedBox(height: 18),
              ],

              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed:
                      _aiAnalysis == null
                          ? null
                          : _openPdfPreview,
                  icon: const Icon(
                    Icons.picture_as_pdf_outlined,
                  ),
                  label: Text(
                    _isLoading
                        ? 'AI 분석 완료 후 PDF 생성 가능'
                        : _aiAnalysis == null
                            ? 'AI 맞춤 분석이 필요합니다'
                            : '개인 수면 분석 결과서 만들기',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        AppColors.primary,
                    foregroundColor:
                        const Color(0xFF10142A),
                    disabledBackgroundColor:
                        AppColors.cardAlt,
                    disabledForegroundColor:
                        AppColors.muted,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              _CautionCard(
                text: analysis.cautionNote,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnalysisSummaryCard extends StatelessWidget {
  final SleepTagAnalysis analysis;
  final bool isAiComplete;

  const _AnalysisSummaryCard({
    required this.analysis,
    required this.isAiComplete,
  });

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(
      analysis.overallSeverity,
    );

    return AppCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius:
                      BorderRadius.circular(13),
                ),
                child: Icon(
                  _severityIcon(
                    analysis.overallSeverity,
                  ),
                  color: color,
                  size: 25,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAiComplete
                          ? 'AI 종합 분석 상태'
                          : '수면 패턴 분석 상태',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      analysis.overallStatus,
                      style: TextStyle(
                        color: color,
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.cardAlt,
                  borderRadius:
                      BorderRadius.circular(999),
                ),
                child: Text(
                  '${analysis.sourceRecordCount}일 기록',
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          Text(
            analysis.periodText,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 9),

          Text(
            analysis.summary,
            style: const TextStyle(
              color: AppColors.foreground,
              fontSize: 13.5,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiLoadingCard extends StatelessWidget {
  const _AiLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: AppColors.primary
              .withValues(alpha: 0.28),
        ),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 23,
            height: 23,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.primary,
            ),
          ),
          SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 맞춤 수면 분석 중',
                  style: TextStyle(
                    color: AppColors.foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '실제 수면 시간과 코골이 기록에 맞는 개선 방법을 생성하고 있습니다.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _AiErrorCard({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color:
            AppColors.pink.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: AppColors.pink
              .withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.cloud_off_outlined,
                color: AppColors.pink,
                size: 21,
              ),
              SizedBox(width: 8),
              Text(
                'AI 맞춤 분석 실패',
                style: TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 9),

          Text(
            message,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 11),

          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(
              Icons.refresh,
              size: 18,
            ),
            label: const Text(
              '다시 시도',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final SleepTagAnalysis analysis;

  const _MetricGrid({
    required this.analysis,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics:
          const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: [
        _MetricCard(
          icon: Icons.bedtime_outlined,
          label: '평균 수면',
          value: _formatHours(
            analysis.averageSleepHours,
          ),
          color: AppColors.primary,
        ),
        _MetricCard(
          icon: Icons.flag_outlined,
          label: '목표 수면',
          value: _formatHours(
            analysis.averageTargetSleepHours,
          ),
          color: AppColors.accent,
        ),
        _MetricCard(
          icon: Icons.nightlight_round,
          label: '평균 취침',
          value: analysis.averageBedtime,
          color: AppColors.orange,
        ),
        _MetricCard(
          icon: Icons.graphic_eq_rounded,
          label: '코골이',
          value:
              '${analysis.snoreDays}일 · ${analysis.totalSnoreCount}회',
          color: AppColors.pink,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: color,
            size: 20,
          ),
          const Spacer(),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.foreground,
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _SleepTagCard extends StatelessWidget {
  final SleepTagResult tag;
  final bool initiallyExpanded;
  final bool isAiLoading;

  const _SleepTagCard({
    required this.tag,
    required this.initiallyExpanded,
    required this.isAiLoading,
  });

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(tag.severity);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withValues(alpha: 0.33),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding:
              const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 5,
          ),
          childrenPadding:
              const EdgeInsets.fromLTRB(
            15,
            0,
            15,
            17,
          ),
          iconColor: color,
          collapsedIconColor: AppColors.muted,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius:
                  BorderRadius.circular(11),
            ),
            child: Icon(
              _tagIcon(tag.name),
              color: color,
              size: 21,
            ),
          ),
          title: Text(
            tag.name,
            style: const TextStyle(
              color: AppColors.foreground,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              tag.displayDescription,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11.8,
                height: 1.45,
              ),
            ),
          ),
          children: [
            _DetailSection(
              title: '분석 근거',
              icon: Icons.analytics_outlined,
              color: AppColors.primary,
              items: tag.evidence,
            ),

            const SizedBox(height: 12),

            if (tag.recommendations.isNotEmpty)
              _DetailSection(
                title: 'AI 맞춤 개선 방법',
                icon: Icons.auto_awesome,
                color: AppColors.accent,
                items: tag.recommendations,
              )
            else
              _AiAdvicePlaceholder(
                loading: isAiLoading,
              ),

            if (tag.weeklyGoal.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppColors.gold
                      .withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(13),
                  border: Border.all(
                    color: AppColors.gold
                        .withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.flag_outlined,
                      color: AppColors.gold,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '이번 주 목표\n${tag.weeklyGoal}',
                        style: const TextStyle(
                          color:
                              AppColors.foreground,
                          fontSize: 12.5,
                          height: 1.5,
                          fontWeight:
                              FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  const _DetailSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.background
            .withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 9),

          ...items.map((item) {
            return Padding(
              padding:
                  const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    margin:
                        const EdgeInsets.only(
                      top: 7,
                      right: 8,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color:
                            AppColors.foreground,
                        fontSize: 12.3,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _AiAdvicePlaceholder extends StatelessWidget {
  final bool loading;

  const _AiAdvicePlaceholder({
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          if (loading)
            const SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            )
          else
            const Icon(
              Icons.auto_awesome_outlined,
              color: AppColors.muted,
              size: 18,
            ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              loading
                  ? '실제 기록에 맞는 개선 방법을 생성하고 있습니다.'
                  : 'AI 맞춤 분석을 다시 시도하면 개선 방법을 확인할 수 있습니다.',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11.8,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyGoalCard extends StatelessWidget {
  final List<String> goals;

  const _WeeklyGoalCard({
    required this.goals,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.checklist_rounded,
                color: AppColors.gold,
                size: 22,
              ),
              SizedBox(width: 9),
              Text(
                'AI가 정한 이번 주 실천 목표',
                style: TextStyle(
                  color: AppColors.foreground,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 13),

          ...goals.map((goal) {
            return Padding(
              padding:
                  const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 19,
                    height: 19,
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(5),
                      border: Border.all(
                        color: AppColors.gold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      goal,
                      style: const TextStyle(
                        color:
                            AppColors.foreground,
                        fontSize: 12.8,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _CautionCard extends StatelessWidget {
  final String text;

  const _CautionCard({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            color: AppColors.muted,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11.8,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoDataCard extends StatelessWidget {
  const _NoDataCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding:
            const EdgeInsets.symmetric(vertical: 26),
        child: Column(
          children: [
            const Icon(
              Icons.bedtime_outlined,
              color: AppColors.muted,
              size: 46,
            ),
            const SizedBox(height: 13),
            const Text(
              '분석할 수면 기록이 없습니다.',
              style: TextStyle(
                color: AppColors.foreground,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Health Connect 수면 기록을 불러오거나\n'
              '코골이 측정을 완료한 후 다시 확인해 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _severityColor(SleepTagSeverity severity) {
  switch (severity) {
    case SleepTagSeverity.good:
      return AppColors.accent;

    case SleepTagSeverity.caution:
      return AppColors.orange;

    case SleepTagSeverity.attention:
      return AppColors.pink;
  }
}

IconData _severityIcon(SleepTagSeverity severity) {
  switch (severity) {
    case SleepTagSeverity.good:
      return Icons.check_circle_outline_rounded;

    case SleepTagSeverity.caution:
      return Icons.tips_and_updates_outlined;

    case SleepTagSeverity.attention:
      return Icons.error_outline_rounded;
  }
}

IconData _tagIcon(String name) {
  switch (name) {
    case '수면 부족':
      return Icons.battery_2_bar_rounded;

    case '야행성':
      return Icons.dark_mode_rounded;

    case '주말 늦잠':
      return Icons.snooze_rounded;

    case '코골이 주의':
      return Icons.graphic_eq_rounded;

    case '안정적인 수면 패턴':
      return Icons.verified_outlined;

    case '분석 데이터 부족':
      return Icons.hourglass_empty_rounded;

    default:
      return Icons.sell_outlined;
  }
}

String _formatHours(double hours) {
  if (hours <= 0 ||
      hours.isNaN ||
      hours.isInfinite) {
    return '0분';
  }

  final totalMinutes = (hours * 60).round();
  final displayHours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;

  if (displayHours <= 0) {
    return '$minutes분';
  }

  if (minutes == 0) {
    return '$displayHours시간';
  }

  return '$displayHours시간 $minutes분';
}