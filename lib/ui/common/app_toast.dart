/// 全局袖珍悬浮提示：所有按钮操作反馈（成功 / 失败 / 中性）统一走这里。
///
/// 相比 SnackBar 的两个关键差异：
/// 1. 位置锚定「调用方所在的 Overlay」而不是根 Scaffold。弹窗内触发的提示
///    会浮在弹窗自己上方，不会掉到弹窗背后的页面底部去（Windows 端尤其明显）。
/// 2. 体积袖珍：深色 pill + 单行文案，语义只由左侧 14px 图标承担，
///    不再用整块绿字/红字占据页面版面。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../state/app_state.dart';

/// 全局 WebDAV 同步结果 Toast 监听器：在 Windows 和移动端任意界面下均能弹出同步结果提示
class GlobalSyncToastListener extends StatefulWidget {
  final Widget child;

  const GlobalSyncToastListener({
    super.key,
    required this.child,
  });

  @override
  State<GlobalSyncToastListener> createState() =>
      _GlobalSyncToastListenerState();
}

class _GlobalSyncToastListenerState extends State<GlobalSyncToastListener> {
  AppState? _appState;
  bool _wasSyncing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = Provider.of<AppState>(context);
    if (_appState != appState) {
      _appState?.removeListener(_onAppStateChanged);
      _appState = appState;
      _wasSyncing = appState.syncing;
      _appState?.addListener(_onAppStateChanged);
    }
  }

  @override
  void dispose() {
    _appState?.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    final state = _appState;
    if (state == null) return;
    // 当同步状态从进行中切换到完成时，全局弹出 Toast 浮窗提示
    if (_wasSyncing && !state.syncing) {
      final msg = state.syncMessage;
      if (msg != null && msg.isNotEmpty && msg != '同步中...') {
        showAppToast(context, msg, kind: toastKindOf(msg));
      }
    }
    _wasSyncing = state.syncing;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// 提示语义。中性用于「同步中...」这类既非成功也非失败的状态。
enum ToastKind { success, error, neutral }

/// 悬浮提示的默认可见时长（不含淡出）。
const Duration _kToastDuration = Duration(seconds: 1);

/// 淡入 / 淡出时长。淡出略快于淡入，收得干脆一些。
const Duration _kFadeIn = Duration(milliseconds: 160);
const Duration _kFadeOut = Duration(milliseconds: 130);

/// 弹出袖珍悬浮提示，[duration] 后自动消失。
///
/// [context] 可为空；优先从当前 context 寻找最近 Overlay，未找到时回退到全局根 Overlay。
void showAppToast(
  BuildContext? context,
  String message, {
  ToastKind kind = ToastKind.neutral,
  Duration duration = _kToastDuration,
}) {
  if (message.isEmpty) return;
  // 优先取最近的 Overlay（弹窗内触发会浮在弹窗自身上方）；否则回退到全局根 Overlay
  final overlay = (context != null
          ? Overlay.maybeOf(context, rootOverlay: false)
          : null) ??
      rootNavigatorKey.currentState?.overlay;
  if (overlay == null) return;
  _ToastHost.show(overlay, message, kind, duration);
}

/// 依据文案推断成功或失败，供同步等「结果文案由服务层拼装」的场景使用。
///
/// 判定词表沿用 WebDAV 设置页原有的错误判定逻辑，保持行为一致。
ToastKind toastKindOf(String message) {
  const errorMarkers = ['失败', '拒', '无效', '不能', '不存在', '请先', '尚未', '错误'];
  for (final marker in errorMarkers) {
    if (message.contains(marker)) return ToastKind.error;
  }
  return ToastKind.success;
}

/// 管理单条提示的生命周期：同一 Overlay 内后来的提示会顶掉前一条，
/// 避免连续点击时提示排队堆积。
class _ToastHost {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(
    OverlayState overlay,
    String message,
    ToastKind kind,
    Duration duration,
  ) {
    _dismissNow();

    final controller = _ToastController();
    final entry = OverlayEntry(
      builder: (_) => _ToastLayer(
        message: message,
        kind: kind,
        controller: controller,
      ),
    );
    _entry = entry;
    overlay.insert(entry);

    _timer = Timer(duration, () async {
      // 淡出播完再移除，避免提示「啪」地闪断。
      await controller.fadeOut();
      _remove(entry);
    });
  }

  /// 立即撤下当前提示（新提示到来时调用），不播淡出动画。
  static void _dismissNow() {
    _timer?.cancel();
    _timer = null;
    final entry = _entry;
    if (entry != null) _remove(entry);
  }

  static void _remove(OverlayEntry entry) {
    if (!entry.mounted) return;
    entry.remove();
    if (identical(_entry, entry)) {
      _entry = null;
    }
  }
}

/// 供定时器驱动淡出的极简控制器
class _ToastController {
  VoidCallback? _onFadeOut;
  Completer<void>? _completer;

  Future<void> fadeOut() {
    final callback = _onFadeOut;
    if (callback == null) return Future<void>.value();
    final completer = Completer<void>();
    _completer = completer;
    callback();
    return completer.future;
  }

  void _finishFadeOut() {
    _completer?.complete();
    _completer = null;
  }
}

/// 提示在 Overlay 中的定位层。
///
/// 贴近所在界面的底部居中，同时避开键盘与安全区。宽度由内容撑开
/// （最多不超过界面宽度的 84%），保证短文案是一颗真正袖珍的 pill。
class _ToastLayer extends StatefulWidget {
  final String message;
  final ToastKind kind;
  final _ToastController controller;

  const _ToastLayer({
    required this.message,
    required this.kind,
    required this.controller,
  });

  @override
  State<_ToastLayer> createState() => _ToastLayerState();
}

class _ToastLayerState extends State<_ToastLayer>
    with TickerProviderStateMixin {
  late final AnimationController _fade;
  // 图标单独一条曲线：easeOutBack 造出「盖章」式的轻微回弹。
  late final AnimationController _stamp;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, duration: _kFadeIn)..forward();
    _stamp = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
    widget.controller._onFadeOut = _startFadeOut;
  }

  Future<void> _startFadeOut() async {
    if (!mounted) {
      widget.controller._finishFadeOut();
      return;
    }
    _fade.duration = _kFadeOut;
    await _fade.reverse();
    widget.controller._finishFadeOut();
  }

  @override
  void dispose() {
    _fade.dispose();
    _stamp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // 键盘弹起时抬高，避免提示被输入法盖住。
    final bottomInset = media.viewInsets.bottom;
    final reduceMotion = media.disableAnimations;

    return Positioned.fill(
      // 提示只做展示，不能拦截下方按钮的点击。
      child: IgnorePointer(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: bottomInset + media.padding.bottom + 28,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: media.size.width * 0.84,
              ),
              child: _buildAnimated(reduceMotion),
            ),
          ),
        ),
      ),
    );
  }

  /// 系统开启「减弱动画」时只保留淡入淡出，去掉位移与盖章回弹。
  Widget _buildAnimated(bool reduceMotion) {
    final pill = _ToastPill(
      message: widget.message,
      kind: widget.kind,
      stamp: reduceMotion ? kAlwaysCompleteAnimation : _stamp,
    );
    final faded = FadeTransition(opacity: _fade, child: pill);
    if (reduceMotion) return faded;
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.35),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _fade, curve: Curves.easeOutCubic)),
      child: faded,
    );
  }
}

/// 提示本体：深色 pill + 语义图标 + 单行文案
class _ToastPill extends StatelessWidget {
  final String message;
  final ToastKind kind;
  final Animation<double> stamp;

  const _ToastPill({
    required this.message,
    required this.kind,
    required this.stamp,
  });

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      ToastKind.success => Icons.check_circle_rounded,
      ToastKind.error => Icons.error_rounded,
      ToastKind.neutral => null,
    };
    final iconColor = switch (kind) {
      ToastKind.success => AppColors.toastSuccess,
      ToastKind.error => AppColors.toastError,
      ToastKind.neutral => Colors.white,
    };

    return Semantics(
      liveRegion: true,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: EdgeInsets.only(
            left: icon == null ? 16 : 12,
            right: 16,
            top: 9,
            bottom: 9,
          ),
          decoration: BoxDecoration(
            color: AppColors.toastSurface.withValues(alpha: 0.94),
            // 全圆角让袖珍体积更明确，与页面上的 12 圆角卡片划清界限。
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                // 盖章动效：图标从 0.6 弹到 1.0，是整条提示唯一的强调点。
                ScaleTransition(
                  scale: Tween<double>(begin: 0.6, end: 1).animate(
                    CurvedAnimation(parent: stamp, curve: Curves.easeOutBack),
                  ),
                  child: Icon(icon, size: 14, color: iconColor),
                ),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
