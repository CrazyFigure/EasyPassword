/// AI 接入点配置读写：整存整取 settings 表的单个 JSON 键。
///
/// 沿用 SettingsService 处理 TabConfig 的模式——配置是用户手动维护、数据量小、
/// 整体读写的内容，没有按行查询需求，建独立表只会多出索引、触发器与迁移成本。
///
/// 保存后调 _notifyChanged()，由 AppState 防抖后推送到 WebDAV，
/// 让多台设备共用同一批接入点。
library;

import 'dart:async';
import 'dart:convert';

import '../core/constants.dart';
import '../models/ai_config.dart';
import 'database.dart';

class AiConfigService {
  /// 配置保存后的通知入口，由 AppState 防抖后触发 WebDAV 自动同步。
  Future<void> Function()? onChanged;

  void _notifyChanged() {
    final callback = onChanged;
    if (callback != null) unawaited(callback());
  }

  /// 读取全部接入点。存储内容损坏时返回空列表而不抛异常，
  /// 否则设置页会整个打不开，用户连重新配置的入口都没有。
  Future<List<AiProvider>> getProviders() async {
    final raw = await DatabaseService.getSetting(DbKeys.aiProviders);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      return AiProviderConfig.fromJson(Map<String, dynamic>.from(decoded))
          .providers;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveProviders(List<AiProvider> providers) async {
    final config = AiProviderConfig(providers: providers);
    await DatabaseService.setSetting(
      DbKeys.aiProviders,
      jsonEncode(config.toJson()),
    );
    _notifyChanged();
  }

  /// 按 id 查找接入点；找不到返回 null（配置可能已被其他设备删除）。
  Future<AiProvider?> findProvider(String id) async {
    for (final provider in await getProviders()) {
      if (provider.id == id) return provider;
    }
    return null;
  }

  /// 新增或按 id 覆盖一个接入点，其余保持原有顺序。
  Future<void> upsertProvider(AiProvider provider) async {
    final providers = List<AiProvider>.from(await getProviders());
    final index = providers.indexWhere((item) => item.id == provider.id);
    if (index < 0) {
      providers.add(provider);
    } else {
      providers[index] = provider;
    }
    await saveProviders(providers);
  }

  Future<void> deleteProvider(String id) async {
    final providers = await getProviders();
    await saveProviders([
      for (final provider in providers)
        if (provider.id != id) provider,
    ]);
  }

  /// 用户追加的识别提示词，拼在系统提示词末尾。默认空串。
  Future<String> getCustomPrompt() async {
    return await DatabaseService.getSetting(DbKeys.aiCustomPrompt) ?? '';
  }

  Future<void> setCustomPrompt(String text) async {
    await DatabaseService.setSetting(DbKeys.aiCustomPrompt, text.trim());
    _notifyChanged();
  }
}
