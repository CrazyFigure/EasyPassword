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
  // 预加载系统字体（Windows 读注册表 / Android 加载系统字体文件）
  final systemFont = await getSystemFont();

  runApp(EasyPasswordApp(appState: appState, systemFont: systemFont));
}

class EasyPasswordApp extends StatelessWidget {
  final AppState appState;
  final String? systemFont;
  const EasyPasswordApp({
    super.key,
    required this.appState,
    required this.systemFont,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: appState,
      child: _Root(systemFont: systemFont),
    );
  }
}

class _Root extends StatelessWidget {
  final String? systemFont;
  const _Root({required this.systemFont});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'EasyPassword',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(
        fontScale: state.fontScale,
        systemFont: systemFont,
      ),
      home: state.locked ? const LockPage() : const HomePage(),
    );
  }
}
