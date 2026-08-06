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
  // 必须先挂载 Flutter 界面再初始化数据库与密钥。Windows 原生窗口默认等待
  // Flutter 首帧才显示，若初始化抛错或磁盘访问变慢，旧逻辑会只留下后台进程。
  runApp(EasyPasswordApp(appState: appState));
}

class EasyPasswordApp extends StatefulWidget {
  final AppState appState;
  const EasyPasswordApp({
    super.key,
    required this.appState,
  });

  @override
  State<EasyPasswordApp> createState() => _EasyPasswordAppState();
}

class _EasyPasswordAppState extends State<EasyPasswordApp> {
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = widget.appState.init();
  }

  /// 初始化失败后复用同一个状态容器重试，避免重新创建服务导致数据库连接泄漏。
  void _retryInitialization() {
    setState(() => _initialization = widget.appState.init());
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.appState,
      child: _Root(
        initialization: _initialization,
        onRetryInitialization: _retryInitialization,
      ),
    );
  }
}

class _Root extends StatelessWidget {
  final Future<void> initialization;
  final VoidCallback onRetryInitialization;

  const _Root({
    required this.initialization,
    required this.onRetryInitialization,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'EasyPassword',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(
        fontFamily: state.fontFamily,
      ),
      // “跟随系统”保留系统无障碍字号；其余选项使用固定倍率。把缩放放在
      // MediaQuery 层可覆盖所有文本，也不会修改 fontSize 为空的 TextStyle。
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final fixedScale = state.fontSizeMode.fixedScale;
        return MediaQuery(
          data: media.copyWith(
            textScaler: fixedScale == null
                ? media.textScaler
                : TextScaler.linear(fixedScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: FutureBuilder<void>(
        future: initialization,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StartupErrorPage(
              error: snapshot.error!,
              onRetry: onRetryInitialization,
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const _StartupLoadingPage();
          }
          return state.locked ? const LockPage() : const HomePage();
        },
      ),
    );
  }
}

/// 启动加载页必须尽早产出首帧，让数据库迁移期间 Windows 窗口保持可见。
class _StartupLoadingPage extends StatelessWidget {
  const _StartupLoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2.5),
            SizedBox(height: 16),
            Text('正在启动 EasyPassword...'),
          ],
        ),
      ),
    );
  }
}

/// 启动异常不能只写入后台日志；直接展示错误与重试入口，方便安装版自恢复和排障。
class _StartupErrorPage extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _StartupErrorPage({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final detail = error.toString().replaceFirst('Exception: ', '');
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 42),
                const SizedBox(height: 16),
                const Text(
                  '应用启动失败',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                const Text('初始化本地数据时出现问题，请重试。'),
                const SizedBox(height: 12),
                SelectableText(
                  detail,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重新启动'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
