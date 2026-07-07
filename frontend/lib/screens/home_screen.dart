import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'sleep_tab.dart';
import 'snoring_tab.dart';
import 'stats_tab.dart';

class HomeScreen extends StatefulWidget {
  final AppState state;
  const HomeScreen({super.key, required this.state});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final titles = ['수면', '코골이', '통계'];
    final tabs = [
      SleepTab(state: widget.state),
      SnoringTab(state: widget.state),
      StatsTab(state: widget.state),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(titles[_tab],
            style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<String>(
            icon: const CircleAvatar(
              radius: 15,
              backgroundColor: AppColors.cardAlt,
              child: Icon(Icons.person, size: 18, color: AppColors.foreground),
            ),
            color: AppColors.card,
            onSelected: (v) {
              if (v == 'logout') widget.state.logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text('${widget.state.userName} 님',
                    style: const TextStyle(color: AppColors.foreground)),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18, color: AppColors.pink),
                    SizedBox(width: 8),
                    Text('로그아웃', style: TextStyle(color: AppColors.foreground)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: widget.state.hasRecords
          ? IndexedStack(index: _tab, children: tabs)
          : _HealthConnectGate(state: widget.state),
      bottomNavigationBar: !widget.state.hasRecords
          ? null
          : NavigationBarTheme(
              data: NavigationBarThemeData(
                backgroundColor: AppColors.card,
                indicatorColor: AppColors.primary.withOpacity(0.2),
                labelTextStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
              child: NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.bedtime_outlined, color: AppColors.muted),
                    selectedIcon: Icon(Icons.bedtime, color: AppColors.primary),
                    label: '수면',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.graphic_eq, color: AppColors.muted),
                    selectedIcon:
                        Icon(Icons.graphic_eq, color: AppColors.primary),
                    label: '코골이',
                  ),
                  NavigationDestination(
                    icon:
                        Icon(Icons.bar_chart_outlined, color: AppColors.muted),
                    selectedIcon:
                        Icon(Icons.bar_chart, color: AppColors.primary),
                    label: '통계',
                  ),
                ],
              ),
            ),
    );
  }
}

/// 실제 Health Connect 동기화가 끝나기 전까지 보여주는 화면.
/// 로딩 중 / 실패 / (드문 경우) 아직 시도 전 상태를 처리한다.
class _HealthConnectGate extends StatelessWidget {
  final AppState state;
  const _HealthConnectGate({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.healthLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text(
              'Health Connect에서\n수면 데이터를 불러오는 중...',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
          ],
        ),
      );
    }

    if (state.healthError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.pink, size: 40),
              const SizedBox(height: 14),
              const Text(
                'Health Connect 데이터를\n불러오지 못했습니다',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                state.healthError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: state.loadHealthConnectSleep,
                  icon: const Icon(Icons.refresh),
                  label: const Text('다시 시도'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: const Color(0xFF10142A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 자동 동기화가 아직 실행되지 않은 경우를 위한 안전장치.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.health_and_safety,
                color: AppColors.primary, size: 40),
            const SizedBox(height: 14),
            const Text(
              'Health Connect 연동이 필요합니다',
              style: TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: state.loadHealthConnectSleep,
                icon: const Icon(Icons.health_and_safety),
                label: const Text('지금 불러오기'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: const Color(0xFF10142A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
