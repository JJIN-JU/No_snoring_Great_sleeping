import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import 'state/app_state.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'theme.dart';

import 'services/snore_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  KakaoSdk.init(
    nativeAppKey: '81002d08e4b40dd29d8b382f31f7158d',
  );

  await initializeDateFormatting('ko');

  // 폰/워치 알림 초기화
  await SnoreNotificationService.init();

  runApp(const SleepCareApp());
}

class SleepCareApp extends StatefulWidget {
  const SleepCareApp({super.key});

  @override
  State<SleepCareApp> createState() => _SleepCareAppState();
}

class _SleepCareAppState extends State<SleepCareApp> {
  final AppState _state = AppState();
  bool _showSplash = true;
  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '숙면 - 수면 헬스케어',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: _showSplash
          ? SplashScreen(
              onFinished: () {
                setState(() => _showSplash = false);
              },
            )
          : ListenableBuilder(
              listenable: _state,
              builder: (context, _) {
                return _state.loggedIn
                    ? HomeScreen(state: _state)
                    : LoginScreen(state: _state);
              },
            ),
    );
  }
}
