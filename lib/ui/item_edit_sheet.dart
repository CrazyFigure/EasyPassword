/// 条目编辑底部弹窗：新增或编辑 网站/App、URL、网站级备注
library;

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../models/password_item.dart';

class ItemEditSheet extends StatefulWidget {
  final String type;
  final PasswordItem? item; // null 为新增

  const ItemEditSheet({super.key, required this.type, this.item});

  @override
  State<ItemEditSheet> createState() => _ItemEditSheetState();
}

class _ItemEditSheetState extends State<ItemEditSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _noteCtrl;

  bool get _isApi => widget.type == ItemType.apikey;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.item?.name ?? '');
    _urlCtrl = TextEditingController(text: widget.item?.url ?? '');
    _noteCtrl = TextEditingController(text: widget.item?.siteNote ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
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
            widget.item == null
                ? '新增${_isApi ? 'API Key' : '密码'}条目'
                : '编辑条目',
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textMain),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '网站 / App 名称',
              hintText: '例如：Google、OpenAI',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: '网站地址（可选）',
              hintText: 'https://...',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '网站级备注',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_nameCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('名称不能为空')),
                );
                return;
              }
              Navigator.pop(context, {
                'name': _nameCtrl.text.trim(),
                'url': _urlCtrl.text.trim(),
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
