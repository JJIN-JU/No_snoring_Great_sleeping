import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../models/sleep_tag_result.dart';
import '../services/sleep_report_pdf_service.dart';
import '../theme.dart';

class SleepReportPreviewScreen extends StatefulWidget {
  final String userName;
  final SleepTagAnalysis analysis;

  const SleepReportPreviewScreen({
    super.key,
    required this.userName,
    required this.analysis,
  });

  @override
  State<SleepReportPreviewScreen> createState() =>
      _SleepReportPreviewScreenState();
}

class _SleepReportPreviewScreenState
    extends State<SleepReportPreviewScreen> {
  late final Future<Uint8List> _pdfFuture;

  @override
  void initState() {
    super.initState();

    _pdfFuture = SleepReportPdfService.build(
      userName: widget.userName,
      analysis: widget.analysis,
    );
  }

  String get _fileName {
    final start = widget.analysis.periodStart;
    final end = widget.analysis.periodEnd;

    if (start != null && end != null) {
      return 'sleep_report_'
          '${start.year}'
          '${start.month.toString().padLeft(2, '0')}'
          '${start.day.toString().padLeft(2, '0')}_'
          '${end.year}'
          '${end.month.toString().padLeft(2, '0')}'
          '${end.day.toString().padLeft(2, '0')}.pdf';
    }

    final now = DateTime.now();

    return 'sleep_report_'
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}.pdf';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.foreground,
        elevation: 0,
        title: const Text(
          '개인 수면 분석 결과서',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: PdfPreview(
          build: (_) => _pdfFuture,
          initialPageFormat: PdfPageFormat.a4,
          pdfFileName: _fileName,

          // 용지 방향 변경 버튼 제거
          canChangeOrientation: false,

          // 용지 크기 변경 버튼 제거
          canChangePageFormat: false,

          // 오른쪽 아래 디버그 스위치 제거
          canDebug: false,

          // 인쇄와 공유 버튼은 유지
          allowPrinting: true,
          allowSharing: true,

          loadingWidget: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: AppColors.primary,
                ),
                SizedBox(height: 14),
                Text(
                  '결과서를 정리하고 있습니다.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          onError: (context, error) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.pink,
                      size: 46,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'PDF 결과서를 만들 수 없습니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}