import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme.dart';

class AppInfoScreen extends StatefulWidget {
  const AppInfoScreen({
    super.key,
  });

  @override
  State<AppInfoScreen> createState() =>
      _AppInfoScreenState();
}

class _AppInfoScreenState
    extends State<AppInfoScreen> {
  late final Future<PackageInfo> _packageInfoFuture;

  @override
  void initState() {
    super.initState();

    _packageInfoFuture =
        PackageInfo.fromPlatform();
  }

  void _openDocument({
    required String title,
    required List<_DocumentSection> sections,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) {
          return _DocumentScreen(
            title: title,
            sections: sections,
          );
        },
      ),
    );
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
          '앱 정보',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(
          16,
          10,
          16,
          32,
        ),
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius:
                  BorderRadius.circular(22),
              border: Border.all(
                color: AppColors.border,
              ),
            ),
            child: const Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor:
                      Color(0x266C8BFF),
                  child: Icon(
                    Icons.nightlight_round,
                    color: AppColors.primary,
                    size: 36,
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  '숙면',
                  style: TextStyle(
                    color: AppColors.foreground,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'AI 기반 개인 맞춤형 수면 관리 서비스',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius:
                  BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.border,
              ),
            ),
            child: Column(
              children: [
                FutureBuilder<PackageInfo>(
                  future: _packageInfoFuture,
                  builder: (context, snapshot) {
                    var version = '확인 중';

                    if (snapshot.hasData) {
                      final info = snapshot.data!;

                      version =
                          '${info.version} (${info.buildNumber})';
                    } else if (snapshot.hasError) {
                      version = '확인 실패';
                    }

                    return _InfoRow(
                      icon:
                          Icons.info_outline_rounded,
                      title: '앱 버전',
                      trailingText: version,
                    );
                  },
                ),

                const _InfoDivider(),

                _InfoRow(
                  icon:
                      Icons.auto_stories_outlined,
                  title: '서비스 소개',
                  onTap: () {
                    _openDocument(
                      title: '서비스 소개',
                      sections:
                          _serviceIntroduction,
                    );
                  },
                ),

                const _InfoDivider(),

                _InfoRow(
                  icon:
                      Icons.description_outlined,
                  title: '이용약관',
                  onTap: () {
                    _openDocument(
                      title: '이용약관',
                      sections: _terms,
                    );
                  },
                ),

                const _InfoDivider(),

                _InfoRow(
                  icon:
                      Icons.privacy_tip_outlined,
                  title: '개인정보 처리방침',
                  onTap: () {
                    _openDocument(
                      title: '개인정보 처리방침',
                      sections: _privacyPolicy,
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius:
                  BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.border,
              ),
            ),
            child: const Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.health_and_safety_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '숙면의 분석 결과는 수면 습관 관리를 위한 참고 정보이며 '
                    '의료 진단이나 의료진의 진료를 대신하지 않습니다.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailingText;
  final VoidCallback? onTap;

  const _InfoRow({
    required this.icon,
    required this.title,
    this.trailingText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: AppColors.primary,
              size: 21,
            ),

            const SizedBox(width: 13),

            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            if (trailingText != null)
              Text(
                trailingText!,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                ),
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.muted,
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoDivider extends StatelessWidget {
  const _InfoDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      color: AppColors.border,
      height: 1,
      indent: 50,
    );
  }
}

class _DocumentScreen extends StatelessWidget {
  final String title;
  final List<_DocumentSection> sections;

  const _DocumentScreen({
    required this.title,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.foreground,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView.separated(
        padding:
            const EdgeInsets.fromLTRB(
          18,
          12,
          18,
          34,
        ),
        itemCount: sections.length,
        separatorBuilder: (_, __) {
          return const SizedBox(height: 20);
        },
        itemBuilder: (context, index) {
          final section = sections[index];

          return Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                section.body,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  height: 1.65,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DocumentSection {
  final String title;
  final String body;

  const _DocumentSection({
    required this.title,
    required this.body,
  });
}

const List<_DocumentSection>
    _serviceIntroduction = [
  _DocumentSection(
    title: '숙면 서비스',
    body:
        '숙면은 Health Connect의 수면 정보와 휴대폰 마이크로 측정한 '
        '코골이 데이터를 활용하여 사용자의 수면 패턴을 확인할 수 있도록 '
        '돕는 개인 맞춤형 수면 관리 서비스입니다.',
  ),
  _DocumentSection(
    title: '주요 기능',
    body:
        '• Health Connect 수면 기록 연동\n'
        '• 수면 시간 및 수면 단계 확인\n'
        '• 목표 취침·기상 시간 설정\n'
        '• 마이크 기반 코골이 측정\n'
        '• AI 기반 코골이 분석\n'
        '• 일별·월별 수면 통계\n'
        '• 개인 수면 태그 분석\n'
        '• AI 개인 수면 분석 결과서 생성',
  ),
  _DocumentSection(
    title: '분석 결과 안내',
    body:
        '수면 태그와 AI 개선 방법은 사용자가 기록한 수면 및 코골이 '
        '데이터를 바탕으로 제공됩니다. 측정 환경과 기기 상태에 따라 '
        '결과가 달라질 수 있으며 의료 진단으로 사용할 수 없습니다.',
  ),
];

const List<_DocumentSection> _terms = [
  _DocumentSection(
    title: '제1조 목적',
    body:
        '본 약관은 숙면 서비스가 제공하는 수면 기록, 코골이 분석 및 '
        '개인 맞춤형 수면 관리 기능의 이용 조건을 정하는 것을 목적으로 합니다.',
  ),
  _DocumentSection(
    title: '제2조 서비스 내용',
    body:
        '서비스는 카카오 로그인, 수면 데이터 연동, 코골이 측정, '
        'AI 수면 태그 분석, 통계 및 PDF 결과서 생성 기능을 제공합니다.',
  ),
  _DocumentSection(
    title: '제3조 사용자 책임',
    body:
        '사용자는 본인의 계정과 기기를 안전하게 관리해야 하며, '
        '마이크 및 건강 데이터 접근 권한을 직접 확인한 후 허용해야 합니다.',
  ),
  _DocumentSection(
    title: '제4조 분석 결과의 한계',
    body:
        '서비스의 결과는 센서, 마이크 환경, 기기 착용 상태와 데이터 '
        '수집 여부에 따라 달라질 수 있습니다. 서비스 결과는 의료 진단, '
        '치료 또는 의료진의 전문적인 판단을 대신하지 않습니다.',
  ),
  _DocumentSection(
    title: '제5조 서비스 제한',
    body:
        '네트워크 장애, 외부 서비스 장애, 서버 점검, 권한 차단 또는 '
        '데이터 미수집 등의 사유로 일부 기능이 제한될 수 있습니다.',
  ),
  _DocumentSection(
    title: '제6조 회원 탈퇴',
    body:
        '사용자는 프로필 메뉴에서 회원 탈퇴를 요청할 수 있습니다. '
        '탈퇴가 완료되면 서비스 계정과 복구할 수 없는 데이터가 삭제될 수 있습니다.',
  ),
  _DocumentSection(
    title: '제7조 시행일',
    body: '본 약관은 2026년 7월 13일부터 적용됩니다.',
  ),
];

const List<_DocumentSection> _privacyPolicy = [
  _DocumentSection(
    title: '1. 처리하는 정보',
    body:
        '• 카카오 사용자 식별값\n'
        '• 카카오 닉네임 및 프로필 이미지\n'
        '• Health Connect에서 사용자가 허용한 수면 정보\n'
        '• 목표 취침 시간과 목표 기상 시간\n'
        '• 코골이 측정 시각, 음량, 횟수 및 AI 분석 결과\n'
        '• AI 코골이 분석을 위해 전송되는 녹음 구간',
  ),
  _DocumentSection(
    title: '2. 정보 이용 목적',
    body:
        '정보는 로그인 및 계정 관리, 수면 기록 표시, 통계 생성, '
        '코골이 분석, 수면 태그 생성 및 개인 수면 분석 결과서 제공을 '
        '위해 사용합니다.',
  ),
  _DocumentSection(
    title: '3. Health Connect 정보',
    body:
        '서비스는 사용자가 허용한 범위의 수면 정보를 읽어 분석에 '
        '활용합니다. 앱에서 Health Connect의 원본 수면 기록을 '
        '임의로 수정하거나 삭제하지 않습니다.',
  ),
  _DocumentSection(
    title: '4. 마이크 및 녹음 정보',
    body:
        '마이크는 사용자가 코골이 측정을 시작한 동안 사용됩니다. '
        '녹음 구간은 코골이 여부를 분석하기 위해 서버로 전송될 수 있으며, '
        '서비스 목적과 관계없는 용도로 사용하지 않습니다.',
  ),
  _DocumentSection(
    title: '5. 외부 서비스',
    body:
        '서비스는 카카오 로그인과 Android Health Connect를 이용합니다. '
        '각 외부 서비스의 정보 처리는 해당 서비스의 정책을 따릅니다.',
  ),
  _DocumentSection(
    title: '6. 사용자의 권리',
    body:
        '사용자는 Android 설정에서 마이크 및 Health Connect 권한을 '
        '철회할 수 있으며, 프로필 메뉴의 회원 탈퇴를 통해 서비스 계정 '
        '삭제를 요청할 수 있습니다.',
  ),
  _DocumentSection(
    title: '7. 안전성 확보',
    body:
        '서비스는 기능 제공에 필요한 범위에서만 정보를 처리하며, '
        '인증 정보와 사용자 정보가 불필요하게 노출되지 않도록 관리합니다.',
  ),
  _DocumentSection(
    title: '8. 시행일',
    body:
        '본 개인정보 처리방침은 2026년 7월 13일부터 적용됩니다.',
  ),
];