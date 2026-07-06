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
                    Text('로그아웃',
                        style: TextStyle(color: AppColors.foreground)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(index: _tab, children: tabs),
      bottomNavigationBar: NavigationBarTheme(
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
              selectedIcon: Icon(Icons.graphic_eq, color: AppColors.primary),
              label: '코골이',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined, color: AppColors.muted),
              selectedIcon: Icon(Icons.bar_chart, color: AppColors.primary),
              label: '통계',
            ),
          ],
        ),
      ),
    );
  }
}
