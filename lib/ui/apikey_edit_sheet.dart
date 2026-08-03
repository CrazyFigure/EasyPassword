/// API Key 编辑底部弹窗：API Key 值 + API Key 级备注
library;

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../models/api_key.dart';

class ApiKeyEditSheet extends StatefulWidget {
  final ApiKey? apiKey; // null 为新增
  const ApiKeyEditSheet({super.key, this.apiKey});

  @override
  State<ApiKeyEditSheet> createState() => _ApiKeyEditSheetState();
}

class _ApiKeyEditSheetState extends State<ApiKeyEditSheet> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController();
    _noteCtrl = TextEditingController(text: widget.apiKey?.note ?? '');
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
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
            widget.apiKey == null ? '添加 API Key' : '编辑 API Key',
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textMain),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _keyCtrl,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: widget.apiKey == null ? 'sk-...' : '留空则不修改',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'API Key 级备注',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_keyCtrl.text.trim().isEmpty && widget.apiKey == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('API Key 不能为空')),
                );
                return;
              }
              Navigator.pop(context, {
                'key': _keyCtrl.text.trim(),
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
