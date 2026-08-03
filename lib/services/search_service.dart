/// 全局搜索：搜索 网站/App、各级备注、用户名、密码、API Key
/// 支持分区筛选（密码区 / API Key 区 / 全部，需求 3.3）
library;

import '../models/account.dart';
import '../models/api_key.dart';
import '../models/password_item.dart';
import 'crypto_service.dart';
import 'data_service.dart';

/// 搜索结果定位目标
enum SearchTargetType { item, account, apiKey }

class SearchResult {
  final SearchTargetType targetType;
  final String itemId;
  final String? accountId;
  final String? apiKeyId;
  final String title; // 条目名
  final String subtitle; // 命中摘要
  final String hitField; // 命中的字段名（展示用）
  final String itemType; // password / apikey

  const SearchResult({
    required this.targetType,
    required this.itemId,
    this.accountId,
    this.apiKeyId,
    required this.title,
    required this.subtitle,
    required this.hitField,
    required this.itemType,
  });
}

class SearchService {
  final DataService data;
  final CryptoService crypto;
  SearchService(this.data, this.crypto);

  /// 全局搜索。
  /// [scope] = 'all' | 'password' | 'apikey'；返回按类型排序的结果。
  Future<List<SearchResult>> search(String query, {String scope = 'all'}) async {
    if (query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    final results = <SearchResult>[];

    // 需要搜索的类型列表
    final types = <String>[];
    if (scope == 'all') {
      types.addAll([ItemType2.password, ItemType2.apikey]);
    } else {
      types.add(scope);
    }

    for (final type in types) {
      final items = await data.listItems(type);
      for (final item in items) {
        // 1) 条目名 / 网站级备注
        if (item.name.toLowerCase().contains(q)) {
          results.add(SearchResult(
            targetType: SearchTargetType.item,
            itemId: item.id,
            title: item.name,
            subtitle: item.siteNote.isEmpty ? item.url : item.siteNote,
            hitField: '名称',
            itemType: type,
          ));
        } else if (item.siteNote.toLowerCase().contains(q)) {
          results.add(SearchResult(
            targetType: SearchTargetType.item,
            itemId: item.id,
            title: item.name,
            subtitle: item.siteNote,
            hitField: '网站级备注',
            itemType: type,
          ));
        }

        // 2) 账号层：用户名 / 备注 / 密码（解密）
        final accounts = await data.listAccounts(item.id);
        for (final acc in accounts) {
          if (acc.username.toLowerCase().contains(q)) {
            results.add(_accResult(item, acc, '用户名'));
          } else if (acc.note.toLowerCase().contains(q)) {
            results.add(_accResult(item, acc, '用户级备注'));
          } else {
            final pwd = await crypto.decrypt(acc.passwordEnc);
            if (pwd.toLowerCase().contains(q)) {
              results.add(_accResult(item, acc, '密码'));
            }
          }

          // 3) API Key 层（仅 apikey 类型条目有）
          if (type == ItemType2.apikey) {
            final keys = await data.listApiKeys(acc.id);
            for (final k in keys) {
              if (k.note.toLowerCase().contains(q)) {
                results.add(_keyResult(item, acc, k, 'API Key 备注'));
              } else {
                final plain = await crypto.decrypt(k.keyEnc);
                if (plain.toLowerCase().contains(q)) {
                  results.add(_keyResult(item, acc, k, 'API Key'));
                }
              }
            }
          }
        }
      }
    }
    return results;
  }

  SearchResult _accResult(PasswordItem item, Account acc, String field) {
    return SearchResult(
      targetType: SearchTargetType.account,
      itemId: item.id,
      accountId: acc.id,
      title: item.name,
      subtitle: acc.username,
      hitField: field,
      itemType: item.type,
    );
  }

  SearchResult _keyResult(PasswordItem item, Account acc, ApiKey k, String field) {
    return SearchResult(
      targetType: SearchTargetType.apiKey,
      itemId: item.id,
      accountId: acc.id,
      apiKeyId: k.id,
      title: item.name,
      subtitle: acc.username,
      hitField: field,
      itemType: item.type,
    );
  }
}

/// 引用常量，避免与 services 层耦合
class ItemType2 {
  static const String password = 'password';
  static const String apikey = 'apikey';
}
