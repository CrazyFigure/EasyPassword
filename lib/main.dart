/// EasyPassword 入口：浅粉主题 + Provider 装配
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'state/app_state.dart';
import 'ui/home_page.dart';
import 'ui/lock_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState();
  await appState.init();

  runApp(EasyPasswordApp(appState: appState));
}

class EasyPasswordApp extends StatelessWidget {
  final AppState appState;
  const EasyPasswordApp({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: appState,
      child: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'EasyPassword',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(fontScale: state.fontScale),
      home: state.locked ? const LockPage() : const HomePage(),
    );
  }
}
