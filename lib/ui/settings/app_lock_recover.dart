/// 应用锁恢复弹窗（通过安全问题重置密码，需求 3.5.1）
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../state/app_state.dart';
import '../common/app_toast.dart';
import '../common/masked_text_controller.dart';
import '../common/platform_input.dart';
import '../common/secret_text_field.dart';

class AppLockRecoverSheet extends StatefulWidget {
  final String question;
  const AppLockRecoverSheet({super.key, required this.question});

  @override
  State<AppLockRecoverSheet> createState() => _AppLockRecoverSheetState();
}

class _AppLockRecoverSheetState extends State<AppLockRecoverSheet> {
  final _answerCtrl = TextEditingController();
  final _newPinCtrl = MaskedTextEditingController();
  final _newPin2Ctrl = MaskedTextEditingController();
  bool _verified = false;
  bool _busy = false;

  @override
  void dispose() {
    _answerCtrl.dispose();
    _newPinCtrl.dispose();
    _newPin2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _verifyAnswer() async {
    final state = context.read<AppState>();
    final ok = await state.appLock.verifySecurityAnswer(_answerCtrl.text);
    if (!mounted) return;
    if (ok) {
      setState(() => _verified = true);
    } else {
      showAppToast(context, '答案错误', kind: ToastKind.error);
    }
  }

  Future<void> _reset() async {
    final pin = _newPinCtrl.text;
    if (pin.length < 4) {
      showAppToast(context, '密码至少 4 位', kind: ToastKind.error);
      return;
    }
    if (pin != _newPin2Ctrl.text) {
      showAppToast(context, '两次密码不一致', kind: ToastKind.error);
      return;
    }
    setState(() => _busy = true);
    final state = context.read<AppState>();
    // 用新密码 + 原安全问题重置
    await state.appLock.enable(pin, widget.question, _answerCtrl.text);
    // 直接解锁进入应用
    state.locked = false;
    await state.refreshAppLock();
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('恢复应用锁密码',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMain)),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppColors.textWeak),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_verified) ...[
              TextField(
                controller: _answerCtrl,
                autofocus: kAutoFocusOnOpen,
                decoration: InputDecoration(
                  labelText: '安全问题',
                  hintText: widget.question,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _verifyAnswer,
                child: const Text('验证答案'),
              ),
            ] else ...[
              const Text('验证通过，请设置新密码',
                  style: TextStyle(fontSize: 13, color: AppColors.textWeak)),
              const SizedBox(height: 12),
              SecretTextField(
                controller: _newPinCtrl,
                copyLabel: '新应用锁密码',
                decoration: const InputDecoration(labelText: '新密码'),
              ),
              const SizedBox(height: 12),
              SecretTextField(
                controller: _newPin2Ctrl,
                copyLabel: '确认密码',
                decoration: const InputDecoration(labelText: '确认新密码'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _reset,
                child: const Text('重置并解锁'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
