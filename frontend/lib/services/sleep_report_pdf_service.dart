import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/sleep_tag_result.dart';

class SleepReportPdfService {
  const SleepReportPdfService._();

  // =========================================================
  // 색상
  // =========================================================

  static final PdfColor _navy =
      PdfColor.fromInt(0xFF183153);

  static final PdfColor _blue =
      PdfColor.fromInt(0xFF4D75D9);

  static final PdfColor _lightBlue =
      PdfColor.fromInt(0xFFF1F5FF);

  static final PdfColor _border =
      PdfColor.fromInt(0xFFD7DFEA);

  static final PdfColor _muted =
      PdfColor.fromInt(0xFF65758B);

  static final PdfColor _text =
      PdfColor.fromInt(0xFF24344D);

  static final PdfColor _softGray =
      PdfColor.fromInt(0xFFF7F9FC);

  static final PdfColor _pink =
      PdfColor.fromInt(0xFFD44364);

  static final PdfColor _softPink =
      PdfColor.fromInt(0xFFFFF1F5);

  static final PdfColor _orange =
      PdfColor.fromInt(0xFFD97A08);

  static final PdfColor _softOrange =
      PdfColor.fromInt(0xFFFFF7E8);

  static final PdfColor _green =
      PdfColor.fromInt(0xFF168A72);

  static final PdfColor _softGreen =
      PdfColor.fromInt(0xFFEEF9F5);

  static final PdfColor _gold =
      PdfColor.fromInt(0xFFB7791F);

  static final PdfColor _softGold =
      PdfColor.fromInt(0xFFFFF8E8);

  // =========================================================
  // PDF 생성
  // =========================================================

  static Future<Uint8List> build({
    required String userName,
    required SleepTagAnalysis analysis,
  }) async {
    final regular =
        await PdfGoogleFonts.notoSansKRRegular();

    final bold =
        await PdfGoogleFonts.notoSansKRBold();

    final document = pw.Document(
      title: '개인 수면 분석 결과서',
      author: 'ZZCare',
      subject: '수면 및 코골이 기록 기반 AI 생활 패턴 분석',
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: bold,
      ),
    );

    final generatedAt = DateTime.now();

    final reportNumber = _reportNumber(
      analysis: analysis,
      generatedAt: generatedAt,
    );

    final tags = analysis.tags.toList();

    // 2페이지에는 첫 번째와 두 번째 태그를 배치한다.
    final secondPageTags =
        tags.take(2).toList();

    // 세 번째 태그부터는 3페이지에 배치한다.
    final thirdPageTags =
        tags.skip(2).toList();

    final hasTagPage = tags.isNotEmpty;

    final hasThirdPage =
        thirdPageTags.isNotEmpty;

    final totalPages = !hasTagPage
        ? 1
        : hasThirdPage
            ? 3
            : 2;

    // =======================================================
    // 1페이지
    // =======================================================

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          38,
          34,
          38,
          34,
        ),
        build: (context) {
          return _pageLayout(
            context: context,
            analysis: analysis,
            generatedAt: generatedAt,
            totalPages: totalPages,
            showRunningHeader: false,
            body: _firstPageBody(
              userName: userName,
              analysis: analysis,
              reportNumber: reportNumber,
            ),
          );
        },
      ),
    );

    // =======================================================
    // 2페이지
    // =======================================================

    if (hasTagPage) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(
            38,
            34,
            38,
            34,
          ),
          build: (context) {
            return _pageLayout(
              context: context,
              analysis: analysis,
              generatedAt: generatedAt,
              totalPages: totalPages,
              showRunningHeader: false,
              body: _detailPageBody(
                analysis: analysis,
                tags: secondPageTags,
                startIndex: 0,

                // 3페이지가 없다면 마지막 내용도
                // 2페이지에 표시한다.
                showFinalSection: !hasThirdPage,
              ),
            );
          },
        ),
      );
    }

    // =======================================================
    // 3페이지
    // =======================================================

    if (hasThirdPage) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(
            38,
            34,
            38,
            34,
          ),
          build: (context) {
            return _pageLayout(
              context: context,
              analysis: analysis,
              generatedAt: generatedAt,
              totalPages: totalPages,
              showRunningHeader: false,
              body: _detailPageBody(
                analysis: analysis,
                tags: thirdPageTags,
                startIndex: 2,
                showFinalSection: true,
              ),
            );
          },
        ),
      );
    }

    return document.save();
  }

  // =========================================================
  // 공통 페이지 구조
  // =========================================================

  static pw.Widget _pageLayout({
    required pw.Context context,
    required SleepTagAnalysis analysis,
    required DateTime generatedAt,
    required int totalPages,
    required pw.Widget body,
    required bool showRunningHeader,
  }) {
    return pw.Column(
      children: [
        if (showRunningHeader) ...[
          _runningHeader(analysis),
          pw.SizedBox(height: 10),
        ],

        pw.Expanded(
          child: pw.FittedBox(
            fit: pw.BoxFit.scaleDown,
            alignment: pw.Alignment.topLeft,
            child: pw.SizedBox(
              // A4 가로 길이에서 좌우 여백을 제외한 크기
              width: 519,
              child: body,
            ),
          ),
        ),

        pw.SizedBox(height: 8),

        _footer(
          pageNumber: context.pageNumber,
          totalPages: totalPages,
          generatedAt: generatedAt,
        ),
      ],
    );
  }

  // =========================================================
  // 1페이지 내용
  // =========================================================

  static pw.Widget _firstPageBody({
    required String userName,
    required SleepTagAnalysis analysis,
    required String reportNumber,
  }) {
    return pw.Column(
      crossAxisAlignment:
          pw.CrossAxisAlignment.start,
      children: [
        _coverHeader(),

        pw.SizedBox(height: 16),

        _profileCard(
          userName: userName,
          analysis: analysis,
          reportNumber: reportNumber,
        ),

        pw.SizedBox(height: 14),

        _summaryCard(analysis),

        pw.SizedBox(height: 17),

        _sectionTitle(
          title: '핵심 수면 지표',
          color: _blue,
        ),

        pw.SizedBox(height: 9),

        _metricGrid(analysis),

        pw.SizedBox(height: 16),

        _sectionTitle(
          title: '주요 수면 태그',
          color: _blue,
        ),

        pw.SizedBox(height: 9),

        _tagChips(analysis.tags),

        if (analysis.tags.isEmpty) ...[
          pw.SizedBox(height: 16),
          _cautionBox(analysis.cautionNote),
        ],
      ],
    );
  }

  // =========================================================
  // 태그 상세 페이지
  // =========================================================

  static pw.Widget _detailPageBody({
    required SleepTagAnalysis analysis,
    required List<SleepTagResult> tags,
    required int startIndex,
    required bool showFinalSection,
  }) {
    return pw.Column(
      crossAxisAlignment:
          pw.CrossAxisAlignment.start,
      children: [
        _detailHeader(),

        pw.SizedBox(height: 12),

        pw.Row(
          children: [
            pw.Container(
              width: 4,
              height: 18,
              color: _blue,
            ),
            pw.SizedBox(width: 8),
            pw.Text(
              '태그별 상세 분석',
              style: pw.TextStyle(
                color: _navy,
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Spacer(),
            pw.Text(
              '분석 태그 ${analysis.tags.length}개 전체 표시',
              style: pw.TextStyle(
                color: _muted,
                fontSize: 7.5,
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 10),

        _tagGrid(
          tags: tags,
          startIndex: startIndex,
          totalCount: analysis.tags.length,
        ),

        if (showFinalSection) ...[
          if (analysis.weeklyGoals.isNotEmpty) ...[
            pw.SizedBox(height: 13),
            _weeklyGoals(
              analysis.weeklyGoals,
            ),
          ],

          pw.SizedBox(height: 12),

          _cautionBox(
            analysis.cautionNote,
          ),
        ],
      ],
    );
  }

  // =========================================================
  // 헤더
  // =========================================================

  static pw.Widget _coverHeader() {
    return pw.Column(
      crossAxisAlignment:
          pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment:
              pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment:
                    pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '개인 수면 분석 결과서',
                    style: pw.TextStyle(
                      color: _navy,
                      fontSize: 24,
                      fontWeight:
                          pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    '수면 및 코골이 기록 기반 AI 생활 패턴 분석',
                    style: pw.TextStyle(
                      color: _muted,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            pw.Text(
              'SLEEP CARE REPORT',
              style: pw.TextStyle(
                color: _blue,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 11),

        pw.Container(
          width: double.infinity,
          height: 2,
          color: _navy,
        ),
      ],
    );
  }

  static pw.Widget _detailHeader() {
    return pw.Column(
      crossAxisAlignment:
          pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment:
              pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment:
                    pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '개인 수면 분석 결과서',
                    style: pw.TextStyle(
                      color: _navy,
                      fontSize: 20,
                      fontWeight:
                          pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    '태그별 분석 근거와 AI 맞춤 실천 계획',
                    style: pw.TextStyle(
                      color: _muted,
                      fontSize: 8,
                    ),
                  ),
                ],
              ),
            ),
            pw.Text(
              'SLEEP CARE REPORT',
              style: pw.TextStyle(
                color: _blue,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 10),

        pw.Container(
          width: double.infinity,
          height: 2,
          color: _navy,
        ),
      ],
    );
  }

  static pw.Widget _runningHeader(
    SleepTagAnalysis analysis,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(
        bottom: 7,
      ),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(
            color: _border,
            width: 0.8,
          ),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            '개인 수면 분석 결과서',
            style: pw.TextStyle(
              color: _navy,
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Spacer(),
          pw.Text(
            analysis.periodText,
            style: pw.TextStyle(
              color: _muted,
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // 사용자 정보
  // =========================================================

  static pw.Widget _profileCard({
    required String userName,
    required SleepTagAnalysis analysis,
    required String reportNumber,
  }) {
    final normalizedName =
        userName.trim().isEmpty
            ? '사용자'
            : userName.trim();

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(13),
      decoration: pw.BoxDecoration(
        color: _softGray,
        borderRadius:
            pw.BorderRadius.circular(9),
        border: pw.Border.all(
          color: _border,
          width: 0.8,
        ),
      ),
      child: pw.Column(
        children: [
          _infoRow(
            label: '성명',
            value: normalizedName,
          ),
          _thinDivider(),
          _infoRow(
            label: '분석 기간',
            value: analysis.periodText,
          ),
          _thinDivider(),
          _infoRow(
            label: '분석 기록',
            value:
                '수면 ${analysis.sleepRecordCount}일 / '
                '코골이 ${analysis.snoreRecordCount}일',
          ),
          _thinDivider(),
          _infoRow(
            label: '보고서 번호',
            value: reportNumber,
          ),
        ],
      ),
    );
  }

  static pw.Widget _infoRow({
    required String label,
    required String value,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(
        vertical: 4.5,
      ),
      child: pw.Row(
        crossAxisAlignment:
            pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 74,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                color: _muted,
                fontSize: 8.5,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                color: _text,
                fontSize: 9,
                fontWeight:
                    pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _thinDivider() {
    return pw.Container(
      width: double.infinity,
      height: 0.6,
      color: _border,
    );
  }

  // =========================================================
  // 종합 분석
  // =========================================================

  static pw.Widget _summaryCard(
    SleepTagAnalysis analysis,
  ) {
    final color =
        _severityColor(analysis.overallSeverity);

    final background =
        _severityBackground(
      analysis.overallSeverity,
    );

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius:
            pw.BorderRadius.circular(9),
        border: pw.Border.all(
          color: color,
          width: 0.9,
        ),
      ),
      child: pw.Row(
        crossAxisAlignment:
            pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 68,
            height: 68,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: color,
              borderRadius:
                  pw.BorderRadius.circular(8),
            ),
            child: pw.Text(
              analysis.overallStatus,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 10,
                fontWeight:
                    pw.FontWeight.bold,
              ),
            ),
          ),

          pw.SizedBox(width: 13),

          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment:
                  pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'AI 종합 분석',
                  style: pw.TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight:
                        pw.FontWeight.bold,
                  ),
                ),

                pw.SizedBox(height: 6),

                pw.Text(
                  analysis.summary,
                  style: pw.TextStyle(
                    color: _text,
                    fontSize: 9.2,
                    lineSpacing: 2.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // 공통 섹션 제목
  // =========================================================

  static pw.Widget _sectionTitle({
    required String title,
    required PdfColor color,
  }) {
    return pw.Row(
      children: [
        pw.Container(
          width: 4,
          height: 17,
          color: color,
        ),
        pw.SizedBox(width: 7),
        pw.Text(
          title,
          style: pw.TextStyle(
            color: _navy,
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // =========================================================
  // 핵심 지표
  // =========================================================

  static pw.Widget _metricGrid(
    SleepTagAnalysis analysis,
  ) {
    final metrics = <Map<String, String>>[
      {
        'label': '평균 수면',
        'value': _formatHours(
          analysis.averageSleepHours,
        ),
      },
      {
        'label': '목표 수면',
        'value': _formatHours(
          analysis.averageTargetSleepHours,
        ),
      },
      {
        'label': '평균 취침',
        'value': analysis.averageBedtime,
      },
      {
        'label': '평균 기상',
        'value': analysis.averageWakeTime,
      },
      {
        'label': '코골이 감지',
        'value': '${analysis.snoreDays}일',
      },
      {
        'label': '코골이 횟수',
        'value':
            '${analysis.totalSnoreCount}회',
      },
    ];

    return pw.Column(
      children: [
        for (var row = 0; row < 3; row++) ...[
          pw.Row(
            children: [
              pw.Expanded(
                child: _metricCard(
                  label:
                      metrics[row * 2]['label']!,
                  value:
                      metrics[row * 2]['value']!,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _metricCard(
                  label: metrics[
                      row * 2 + 1]['label']!,
                  value: metrics[
                      row * 2 + 1]['value']!,
                ),
              ),
            ],
          ),
          if (row < 2)
            pw.SizedBox(height: 7),
        ],
      ],
    );
  }

  static pw.Widget _metricCard({
    required String label,
    required String value,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(
        11,
        9,
        11,
        10,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius:
            pw.BorderRadius.circular(7),
        border: pw.Border.all(
          color: _border,
          width: 0.8,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment:
            pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              color: _muted,
              fontSize: 7.7,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            style: pw.TextStyle(
              color: _navy,
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // 태그 목록
  // =========================================================

  static pw.Widget _tagChips(
    List<SleepTagResult> tags,
  ) {
    if (tags.isEmpty) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(11),
        decoration: pw.BoxDecoration(
          color: _softGray,
          borderRadius:
              pw.BorderRadius.circular(7),
          border: pw.Border.all(
            color: _border,
          ),
        ),
        child: pw.Text(
          '표시할 수면 태그가 없습니다.',
          style: pw.TextStyle(
            color: _muted,
            fontSize: 9,
          ),
        ),
      );
    }

    return pw.Wrap(
      spacing: 7,
      runSpacing: 7,
      children: tags.map((tag) {
        final color =
            _severityColor(tag.severity);

        final background =
            _severityBackground(tag.severity);

        return pw.Container(
          padding: const pw.EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 5,
          ),
          decoration: pw.BoxDecoration(
            color: background,
            borderRadius:
                pw.BorderRadius.circular(6),
            border: pw.Border.all(
              color: color,
              width: 0.8,
            ),
          ),
          child: pw.Text(
            tag.name,
            style: pw.TextStyle(
              color: color,
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        );
      }).toList(),
    );
  }

  // =========================================================
  // 태그 상세 그리드
  // =========================================================

  static pw.Widget _tagGrid({
    required List<SleepTagResult> tags,
    required int startIndex,
    required int totalCount,
  }) {
    if (tags.isEmpty) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          color: _softGray,
          borderRadius:
              pw.BorderRadius.circular(8),
          border: pw.Border.all(
            color: _border,
          ),
        ),
        child: pw.Text(
          '표시할 상세 태그가 없습니다.',
          style: pw.TextStyle(
            color: _muted,
            fontSize: 9,
          ),
        ),
      );
    }

    final rows = <pw.Widget>[];

    for (var index = 0;
        index < tags.length;
        index += 2) {
      final leftTag = tags[index];

      final hasRightTag =
          index + 1 < tags.length;

      rows.add(
        pw.Row(
          crossAxisAlignment:
              pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _tagDetailCard(
                tag: leftTag,
                index: startIndex + index,
                total: totalCount,
              ),
            ),

            pw.SizedBox(width: 9),

            pw.Expanded(
              child: hasRightTag
                  ? _tagDetailCard(
                      tag: tags[index + 1],
                      index:
                          startIndex + index + 1,
                      total: totalCount,
                    )
                  : pw.SizedBox(),
            ),
          ],
        ),
      );

      if (index + 2 < tags.length) {
        rows.add(
          pw.SizedBox(height: 9),
        );
      }
    }

    return pw.Column(
      children: rows,
    );
  }

  // =========================================================
  // 태그 상세 카드
  // =========================================================

  static pw.Widget _tagDetailCard({
    required SleepTagResult tag,
    required int index,
    required int total,
  }) {
    final color =
        _severityColor(tag.severity);

    final background =
        _severityBackground(tag.severity);

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius:
            pw.BorderRadius.circular(7),
        border: pw.Border.all(
          color: color,
          width: 0.9,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment:
            pw.CrossAxisAlignment.start,
        children: [
          // 태그 제목
          pw.Row(
            crossAxisAlignment:
                pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                width: 4,
                height: 22,
                color: color,
              ),

              pw.SizedBox(width: 7),

              pw.Expanded(
                child: pw.Text(
                  tag.name,
                  style: pw.TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight:
                        pw.FontWeight.bold,
                  ),
                ),
              ),

              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                decoration: pw.BoxDecoration(
                  color: background,
                  borderRadius:
                      pw.BorderRadius.circular(4),
                  border: pw.Border.all(
                    color: color,
                    width: 0.7,
                  ),
                ),
                child: pw.Text(
                  _severityLabel(tag.severity),
                  style: pw.TextStyle(
                    color: color,
                    fontSize: 6.5,
                    fontWeight:
                        pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 6),

          pw.Text(
            tag.displayDescription,
            style: pw.TextStyle(
              color: _text,
              fontSize: 7.7,
              lineSpacing: 2,
            ),
          ),

          pw.SizedBox(height: 8),

          // 분석 근거
          _miniSectionTitle(
            title: '분석 근거',
            color: _blue,
          ),

          pw.SizedBox(height: 5),

          if (tag.evidence.isEmpty)
            _emptyDetailText(
              '분석 근거가 없습니다.',
            )
          else
            ...tag.evidence.map(
              (evidence) => _bulletItem(
                text: evidence,
                color: _blue,
              ),
            ),

          pw.SizedBox(height: 8),

          // AI 개선 방법
          _miniSectionTitle(
            title: 'AI 개선 방법',
            color: _green,
          ),

          pw.SizedBox(height: 5),

          if (tag.recommendations.isEmpty)
            _emptyDetailText(
              '생성된 개선 방법이 없습니다.',
            )
          else
            ...tag.recommendations
                .asMap()
                .entries
                .map(
                  (entry) =>
                      _recommendationItem(
                    number: entry.key + 1,
                    text: entry.value,
                  ),
                ),

          if (tag.weeklyGoal.trim().isNotEmpty) ...[
            pw.SizedBox(height: 7),

            _goalBox(
              text: tag.weeklyGoal,
            ),
          ],

          pw.SizedBox(height: 5),

          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '${index + 1} / $total',
              style: pw.TextStyle(
                color: _muted,
                fontSize: 6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _miniSectionTitle({
    required String title,
    required PdfColor color,
  }) {
    return pw.Row(
      children: [
        pw.Container(
          width: 3,
          height: 11,
          color: color,
        ),
        pw.SizedBox(width: 5),
        pw.Text(
          title,
          style: pw.TextStyle(
            color: color,
            fontSize: 7.8,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static pw.Widget _bulletItem({
    required String text,
    required PdfColor color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(
        bottom: 3.5,
      ),
      child: pw.Row(
        crossAxisAlignment:
            pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 4,
            height: 4,
            margin: const pw.EdgeInsets.only(
              top: 4,
              right: 5,
            ),
            decoration: pw.BoxDecoration(
              color: color,
              borderRadius:
                  pw.BorderRadius.circular(1),
            ),
          ),

          pw.Expanded(
            child: pw.Text(
              text,
              style: pw.TextStyle(
                color: _text,
                fontSize: 7,
                lineSpacing: 1.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _recommendationItem({
    required int number,
    required String text,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(
        bottom: 4,
      ),
      child: pw.Row(
        crossAxisAlignment:
            pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 15,
            height: 15,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: _softGreen,
              borderRadius:
                  pw.BorderRadius.circular(3),
              border: pw.Border.all(
                color: _green,
                width: 0.7,
              ),
            ),
            child: pw.Text(
              '$number',
              style: pw.TextStyle(
                color: _green,
                fontSize: 6.5,
                fontWeight:
                    pw.FontWeight.bold,
              ),
            ),
          ),

          pw.SizedBox(width: 5),

          pw.Expanded(
            child: pw.Text(
              text,
              style: pw.TextStyle(
                color: _text,
                fontSize: 7,
                lineSpacing: 1.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _emptyDetailText(
    String text,
  ) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        color: _muted,
        fontSize: 7,
      ),
    );
  }

  static pw.Widget _goalBox({
    required String text,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: _softGold,
        borderRadius:
            pw.BorderRadius.circular(4),
        border: pw.Border.all(
          color: _gold,
          width: 0.7,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment:
            pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '이번 주 목표',
            style: pw.TextStyle(
              color: _gold,
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            text,
            style: pw.TextStyle(
              color: _text,
              fontSize: 6.8,
              lineSpacing: 1.8,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // 이번 주 권장 목표
  // =========================================================

  static pw.Widget _weeklyGoals(
    List<String> goals,
  ) {
    return pw.Column(
      crossAxisAlignment:
          pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          title: '이번 주 권장 실천 항목',
          color: _blue,
        ),

        pw.SizedBox(height: 7),

        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(9),
          decoration: pw.BoxDecoration(
            color: _lightBlue,
            borderRadius:
                pw.BorderRadius.circular(6),
            border: pw.Border.all(
              color: _blue,
              width: 0.8,
            ),
          ),
          child: pw.Column(
            crossAxisAlignment:
                pw.CrossAxisAlignment.start,
            children:
                goals.asMap().entries.map((entry) {
              return pw.Padding(
                padding: const pw.EdgeInsets.only(
                  bottom: 5,
                ),
                child: pw.Row(
                  crossAxisAlignment:
                      pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 16,
                      height: 16,
                      alignment:
                          pw.Alignment.center,
                      decoration:
                          pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius:
                            pw.BorderRadius.circular(
                          3,
                        ),
                        border: pw.Border.all(
                          color: _blue,
                          width: 0.8,
                        ),
                      ),
                      child: pw.Text(
                        '${entry.key + 1}',
                        style: pw.TextStyle(
                          color: _blue,
                          fontSize: 6.5,
                          fontWeight:
                              pw.FontWeight.bold,
                        ),
                      ),
                    ),

                    pw.SizedBox(width: 7),

                    pw.Expanded(
                      child: pw.Text(
                        entry.value,
                        style: pw.TextStyle(
                          color: _text,
                          fontSize: 7.5,
                          lineSpacing: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // =========================================================
  // 주의 문구
  // =========================================================

  static pw.Widget _cautionBox(
    String text,
  ) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: _softGray,
        borderRadius:
            pw.BorderRadius.circular(5),
        border: pw.Border.all(
          color: _border,
          width: 0.7,
        ),
      ),
      child: pw.Text(
        '※ $text',
        style: pw.TextStyle(
          color: _muted,
          fontSize: 6.9,
          lineSpacing: 1.8,
        ),
      ),
    );
  }

  // =========================================================
  // 하단 페이지 번호
  // =========================================================

  static pw.Widget _footer({
    required int pageNumber,
    required int totalPages,
    required DateTime generatedAt,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.only(
        top: 6,
      ),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(
            color: _border,
            width: 0.6,
          ),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            'ZZCare · AI 기반 개인 맞춤형 수면 관리',
            style: pw.TextStyle(
              color: _muted,
              fontSize: 6.5,
            ),
          ),

          pw.Spacer(),

          pw.Text(
            '${_dateText(generatedAt)} 생성 · '
            '$pageNumber / $totalPages',
            style: pw.TextStyle(
              color: _muted,
              fontSize: 6.5,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // 색상 및 상태
  // =========================================================

  static PdfColor _severityColor(
    SleepTagSeverity severity,
  ) {
    switch (severity) {
      case SleepTagSeverity.good:
        return _green;

      case SleepTagSeverity.caution:
        return _orange;

      case SleepTagSeverity.attention:
        return _pink;
    }
  }

  static PdfColor _severityBackground(
    SleepTagSeverity severity,
  ) {
    switch (severity) {
      case SleepTagSeverity.good:
        return _softGreen;

      case SleepTagSeverity.caution:
        return _softOrange;

      case SleepTagSeverity.attention:
        return _softPink;
    }
  }

  static String _severityLabel(
    SleepTagSeverity severity,
  ) {
    switch (severity) {
      case SleepTagSeverity.good:
        return '양호';

      case SleepTagSeverity.caution:
        return '관리 권장';

      case SleepTagSeverity.attention:
        return '집중 관리';
    }
  }

  // =========================================================
  // 보고서 번호와 날짜
  // =========================================================

  static String _reportNumber({
    required SleepTagAnalysis analysis,
    required DateTime generatedAt,
  }) {
    final end =
        analysis.periodEnd ?? generatedAt;

    return 'SLEEP-'
        '${end.year}'
        '${end.month.toString().padLeft(2, '0')}'
        '${end.day.toString().padLeft(2, '0')}-'
        '${generatedAt.hour.toString().padLeft(2, '0')}'
        '${generatedAt.minute.toString().padLeft(2, '0')}';
  }

  static String _dateText(
    DateTime date,
  ) {
    return '${date.year}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // =========================================================
  // 시간 표시
  // =========================================================

  static String _formatHours(
    double hours,
  ) {
    if (hours <= 0 ||
        hours.isNaN ||
        hours.isInfinite) {
      return '0분';
    }

    final totalMinutes =
        (hours * 60).round();

    final displayHours =
        totalMinutes ~/ 60;

    final minutes =
        totalMinutes % 60;

    if (displayHours <= 0) {
      return '$minutes분';
    }

    if (minutes == 0) {
      return '$displayHours시간';
    }

    return '$displayHours시간 $minutes분';
  }
}