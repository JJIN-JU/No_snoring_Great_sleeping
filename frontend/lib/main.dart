import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'state/app_state.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko');
  runApp(const SleepCareApp());
}

class SleepCareApp extends StatefulWidget {
  const SleepCareApp({super.key});

  @override
  State<SleepCareApp> createState() => _SleepCareAppState();
}

class _SleepCareAppState extends State<SleepCareApp> {
  final AppState _state = AppState();

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
      home: ListenableBuilder(
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
