/// 应用锁设置页：开启时设置密码 + 安全问题；已开启时修改/恢复
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../state/app_state.dart';
import '../common/masked_text_controller.dart';
import '../common/secret_text_field.dart';

class AppLockSetupPage extends StatefulWidget {
  const AppLockSetupPage({super.key});

  @override
  State<AppLockSetupPage> createState() => _AppLockSetupPageState();
}

class _AppLockSetupPageState extends State<AppLockSetupPage> {
  final _pinCtrl = MaskedTextEditingController();
  final _pin2Ctrl = MaskedTextEditingController();
  final _questionCtrl = TextEditingController();
  final _answerCtrl = TextEditingController();
  bool _busy = false;

  // 恢复模式：先验证原密码
  bool _verified = false;

  @override
  void dispose() {
    _pinCtrl.dispose();
    _pin2Ctrl.dispose();
    _questionCtrl.dispose();
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _pinCtrl.text;
    final pin2 = _pin2Ctrl.text;
    final question = _questionCtrl.text.trim();
    final answer = _answerCtrl.text.trim();

    if (pin.length < 4) {
      _toast('密码至少 4 位');
      return;
    }
    if (pin != pin2) {
      _toast('两次输入的密码不一致');
      return;
    }
    if (question.isEmpty || answer.isEmpty) {
      _toast('请设置安全问题与答案（用于恢复密码）');
      return;
    }

    setState(() => _busy = true);
    final state = context.read<AppState>();
    await state.appLock.enable(pin, question, answer);
    await state.refreshAppLock();
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('应用锁已开启')),
    );
  }

  Future<void> _verifyCurrent() async {
    final ctrl = MaskedTextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('验证当前密码'),
          content: SecretTextField(
            controller: ctrl,
            copyLabel: '当前应用锁密码',
            autofocus: true,
            decoration: const InputDecoration(labelText: '当前应用锁密码'),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(88, 44)),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
              onPressed: () async {
                final state = context.read<AppState>();
                final verified = await state.appLock.verify(ctrl.text);
                if (!ctx.mounted) return;
                Navigator.pop(ctx, verified);
              },
              child: const Text('验证'),
            ),
          ],
        ),
      );
      if (ok == true && mounted) {
        setState(() => _verified = true);
      }
    } finally {
      ctrl.dispose();
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isEnabled = state.appLockEnabled;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEnabled ? '修改应用锁' : '开启应用锁'),
      ),
      body: isEnabled && !_verified ? _buildVerifyView() : _buildFormView(),
    );
  }

  /// 已开启且未验证时：要求先验证当前密码
  Widget _buildVerifyView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.lock_outline, size: 48, color: AppColors.primary),
        const SizedBox(height: 8),
        const Text('已开启应用锁，修改前需验证当前密码',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textWeak)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _verifyCurrent,
          child: const Text('验证当前密码'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _recoverViaQuestion,
          child: const Text('忘记密码？用安全问题恢复'),
        ),
      ],
    );
  }

  /// 设置新密码 + 安全问题表单
  Widget _buildFormView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SecretTextField(
          controller: _pinCtrl,
          copyLabel: '应用锁密码',
          decoration: const InputDecoration(
            labelText: '应用锁密码',
            hintText: '至少 4 位',
          ),
        ),
        const SizedBox(height: 12),
        SecretTextField(
          controller: _pin2Ctrl,
          copyLabel: '确认密码',
          decoration: const InputDecoration(labelText: '确认密码'),
        ),
        const SizedBox(height: 20),
        const Text('安全问题（用于忘记密码时恢复）',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textWeak)),
        const SizedBox(height: 8),
        TextField(
          controller: _questionCtrl,
          decoration: const InputDecoration(
            labelText: '问题',
            hintText: '例如：你最喜欢的城市是？',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _answerCtrl,
          decoration: const InputDecoration(labelText: '答案'),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_isEnabled ? '保存修改' : '开启应用锁'),
        ),
      ],
    );
  }

  bool get _isEnabled => context.watch<AppState>().appLockEnabled;

  Future<void> _recoverViaQuestion() async {
    final state = context.read<AppState>();
    final question = await state.appLock.getSecurityQuestion();
    if (question == null || question.isEmpty) {
      _toast('未设置安全问题，无法恢复');
      return;
    }
    if (!mounted) return;
    final answer = await _askAnswer(question);
    if (answer == null) return;
    final ok = await state.appLock.verifySecurityAnswer(answer);
    if (!mounted) return;
    if (ok) {
      setState(() => _verified = true);
    } else {
      _toast('安全问题答案错误');
    }
  }

  Future<String?> _askAnswer(String question) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('安全问题验证'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: question),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('验证'),
          ),
        ],
      ),
    );
  }
}
