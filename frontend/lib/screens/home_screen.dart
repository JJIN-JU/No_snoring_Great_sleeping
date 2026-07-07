import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/kakao_profile_sheet.dart';
import 'sleep_tab.dart';
import 'snoring_tab.dart';
import 'stats_tab.dart';

class HomeScreen extends StatefulWidget {
  final AppState state;

  const HomeScreen({
    super.key,
    required this.state,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  void _openProfileSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      builder: (_) {
        return KakaoProfileSheet(
          fallbackUserName: widget.state.userName,
          email: widget.state.kakaoEmail,
          profileImageUrl: widget.state.profileImageUrl,
          onLogout: widget.state.logout,
          onWithdrawComplete: widget.state.withdraw,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['수면', '코골이', '통계'];

    final tabs = [
      SleepTab(state: widget.state),
      SnoringTab(state: widget.state),
      StatsTab(state: widget.state),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: false,
        title: Text(
          titles[_tab],
          style: const TextStyle(
            color: AppColors.foreground,
            fontWeight: FontWeight.w800,
            fontSize: 26,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: GestureDetector(
              onTap: _openProfileSheet,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.cardAlt,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.22),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.person_rounded,
                  size: 24,
                  color: AppColors.foreground,
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: tabs,
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppColors.card,
          indicatorColor: AppColors.primary.withValues(alpha: 0.2),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(
              fontSize: 12,
              color: AppColors.muted,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) {
            setState(() {
              _tab = i;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(
                Icons.bedtime_outlined,
                color: AppColors.muted,
              ),
              selectedIcon: Icon(
                Icons.bedtime,
                color: AppColors.primary,
              ),
              label: '수면',
            ),
            NavigationDestination(
              icon: Icon(
                Icons.graphic_eq,
                color: AppColors.muted,
              ),
              selectedIcon: Icon(
                Icons.graphic_eq,
                color: AppColors.primary,
              ),
              label: '코골이',
            ),
            NavigationDestination(
              icon: Icon(
                Icons.bar_chart_outlined,
                color: AppColors.muted,
              ),
              selectedIcon: Icon(
                Icons.bar_chart,
                color: AppColors.primary,
              ),
              label: '통계',
            ),
          ],
        ),
      ),
    );
  }
}