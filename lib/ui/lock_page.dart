/// 应用锁页面：输入密码解锁 / 通过安全问题恢复
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../state/app_state.dart';
import 'center_dialog.dart';
import 'common/app_toast.dart';
import 'common/masked_text_controller.dart';
import 'common/secret_text_field.dart';
import 'settings/app_lock_recover.dart';

class LockPage extends StatefulWidget {
  const LockPage({super.key});

  @override
  State<LockPage> createState() => _LockPageState();
}

class _LockPageState extends State<LockPage> {
  final _pinController = MaskedTextEditingController();
  bool _error = false;
  bool _busy = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_pinController.text.isEmpty) return;
    setState(() => _busy = true);
    final ok = await context.read<AppState>().unlock(_pinController.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = !ok;
    });
    if (!ok && mounted) {
      _pinController.clear();
    }
  }

  Future<void> _recover() async {
    final state = context.read<AppState>();
    final question = await state.appLock.getSecurityQuestion();
    if (question == null || question.isEmpty) {
      if (!mounted) return;
      showAppToast(context, '未设置安全问题，无法恢复', kind: ToastKind.error);
      return;
    }
    if (!mounted) return;
    // 通过安全问题重置密码（居中弹窗，重置后直接解锁）
    await showCenterDialog<void>(
      context: context,
      builder: (_) => AppLockRecoverSheet(question: question),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 品牌图标
                Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.lock_outline,
                      color: Colors.white, size: 36),
                ),
                const SizedBox(height: 16),
                const Text(
                  'EasyPassword',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '输入应用锁密码继续',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.textWeak),
                ),
                const SizedBox(height: 28),
                SecretTextField(
                  controller: _pinController,
                  copyLabel: '应用锁密码',
                  autofocus: true,
                  onSubmitted: (_) => _unlock(),
                  decoration: InputDecoration(
                    hintText: '应用锁密码',
                    errorText: _error ? '密码错误' : null,
                    prefixIcon:
                        const Icon(Icons.key, color: AppColors.textWeak),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _unlock,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('解锁'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _recover,
                  child: const Text(
                    '忘记密码？通过安全问题恢复',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
