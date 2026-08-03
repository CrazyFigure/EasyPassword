/// 账号编辑底部弹窗：用户名 / 密码 / 用户级备注（新增与编辑共用）
library;

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../models/account.dart';

class AccountEditSheet extends StatefulWidget {
  final Account? account; // null 为新增
  const AccountEditSheet({super.key, this.account});

  @override
  State<AccountEditSheet> createState() => _AccountEditSheetState();
}

class _AccountEditSheetState extends State<AccountEditSheet> {
  late final TextEditingController _userCtrl;
  late final TextEditingController _pwdCtrl;
  late final TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    _userCtrl = TextEditingController(text: widget.account?.username ?? '');
    _pwdCtrl = TextEditingController();
    _noteCtrl = TextEditingController(text: widget.account?.note ?? '');
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.account == null ? '添加账号' : '编辑账号',
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textMain),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _userCtrl,
            decoration: const InputDecoration(
              labelText: '用户名',
              hintText: '例如：user@example.com',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pwdCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: '密码',
              hintText: widget.account == null ? '请输入密码' : '留空则不修改',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '用户级备注',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_userCtrl.text.trim().isEmpty &&
                  widget.account == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('用户名不能为空')),
                );
                return;
              }
              Navigator.pop(context, {
                'username': _userCtrl.text.trim(),
                'password': _pwdCtrl.text,
                'note': _noteCtrl.text.trim(),
              });
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
