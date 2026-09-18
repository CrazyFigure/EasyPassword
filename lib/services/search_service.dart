/// 全局搜索：搜索 网站/App、各级备注、用户名、密码、API Key
/// 支持分区筛选（密码区 / API Key 区 / 全部，需求 3.3）
library;

import '../models/account.dart';
import '../models/api_key.dart';
import '../models/folder.dart';
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
  final String hitValue; // 命中的具体内容
  final String itemType; // password / apikey
  final String? folderName; // 所属目录名；null 表示条目位于分区根目录

  // 上下文详细字段，便于搜索卡片展示丰富的位置与属性
  final String url; // 网址
  final String siteNote; // 网站级备注
  final String? username; // 用户名
  final String? accountNote; // 用户级备注
  final String? password; // 密码明文（仅命中密码时填充）
  final String? apiKey; // API Key 明文（仅命中 API Key 时填充）
  final String? apiKeyNote; // API Key 备注

  const SearchResult({
    required this.targetType,
    required this.itemId,
    this.accountId,
    this.apiKeyId,
    required this.title,
    required this.subtitle,
    required this.hitField,
    this.hitValue = '',
    required this.itemType,
    this.folderName,
    this.url = '',
    this.siteNote = '',
    this.username,
    this.accountNote,
    this.password,
    this.apiKey,
    this.apiKeyNote,
  });
}

class SearchService {
  final DataService data;
  final CryptoService crypto;
  SearchService(this.data, this.crypto);

  /// 全局搜索。
  /// [scope] = 'all' | 'password' | 'apikey'；返回按类型排序的结果。
  Future<List<SearchResult>> search(String query,
      {String scope = 'all'}) async {
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
      // 同一分区只查一次文件夹并建立索引，给所有命中结果补充可读目录名，
      // 避免搜索到文件夹内多条数据时逐条查库造成 N+1 查询。
      final folderNames = <String, String>{
        for (final Folder folder in await data.listFolders(type))
          folder.id: folder.name,
      };
      // 搜索跨文件夹：文件夹内的条目也必须能被搜到
      final items = await data.listItems(type, allFolders: true);
      for (final item in items) {
        // folder_id 可能因异常数据找不到有效文件夹，此时按根目录结果展示，
        // 不能把内部 id 暴露给用户。
        final folderName =
            item.folderId == null ? null : folderNames[item.folderId!];

        // 预查条目下的账号列表，供条目级命中提供首个账号预览，并供账号层继续遍历
        final accounts = await data.listAccounts(item.id);
        final firstAcc = accounts.isNotEmpty ? accounts.first : null;

        // 1) 条目名 / 网址 / 网站级备注
        if (item.name.toLowerCase().contains(q)) {
          results.add(SearchResult(
            targetType: SearchTargetType.item,
            itemId: item.id,
            title: item.name,
            subtitle: item.name,
            hitField: '名称',
            hitValue: item.name,
            itemType: type,
            folderName: folderName,
            url: item.url,
            siteNote: item.siteNote,
            username: firstAcc?.username,
            accountNote: firstAcc?.note,
          ));
        } else if (item.url.isNotEmpty && item.url.toLowerCase().contains(q)) {
          // 支持根据网址匹配条目
          results.add(SearchResult(
            targetType: SearchTargetType.item,
            itemId: item.id,
            title: item.name,
            subtitle: item.url,
            hitField: '网址',
            hitValue: item.url,
            itemType: type,
            folderName: folderName,
            url: item.url,
            siteNote: item.siteNote,
            username: firstAcc?.username,
            accountNote: firstAcc?.note,
          ));
        } else if (item.siteNote.toLowerCase().contains(q)) {
          results.add(SearchResult(
            targetType: SearchTargetType.item,
            itemId: item.id,
            title: item.name,
            subtitle: item.siteNote,
            hitField: '网站级备注',
            hitValue: item.siteNote,
            itemType: type,
            folderName: folderName,
            url: item.url,
            siteNote: item.siteNote,
            username: firstAcc?.username,
            accountNote: firstAcc?.note,
          ));
        }

        // 2) 账号层：用户名 / 备注 / 密码（解密）
        for (final acc in accounts) {
          if (acc.username.toLowerCase().contains(q)) {
            results.add(_accResult(
              item: item,
              acc: acc,
              field: '用户名',
              value: acc.username,
              folderName: folderName,
            ));
          } else if (acc.note.toLowerCase().contains(q)) {
            results.add(_accResult(
              item: item,
              acc: acc,
              field: '用户级备注',
              value: acc.note,
              folderName: folderName,
            ));
          } else {
            final pwd = await crypto.decrypt(acc.passwordEnc);
            if (pwd.toLowerCase().contains(q)) {
              results.add(_accResult(
                item: item,
                acc: acc,
                field: '密码',
                value: pwd,
                folderName: folderName,
                plainPassword: pwd,
              ));
            }
          }

          // 3) API Key 层（仅 apikey 类型条目有）
          if (type == ItemType2.apikey) {
            final keys = await data.listApiKeys(acc.id);
            for (final k in keys) {
              if (k.note.toLowerCase().contains(q)) {
                results.add(_keyResult(
                  item: item,
                  acc: acc,
                  k: k,
                  field: 'API Key 备注',
                  value: k.note,
                  folderName: folderName,
                ));
              } else {
                final plain = await crypto.decrypt(k.keyEnc);
                if (plain.toLowerCase().contains(q)) {
                  results.add(_keyResult(
                    item: item,
                    acc: acc,
                    k: k,
                    field: 'API Key',
                    value: plain,
                    folderName: folderName,
                    plainKey: plain,
                  ));
                }
              }
            }
          }
        }
      }
    }
    return results;
  }

  /// 构造账号级命中结果，并把条目的目录上下文与账号信息透传给搜索页。
  SearchResult _accResult({
    required PasswordItem item,
    required Account acc,
    required String field,
    required String value,
    String? folderName,
    String? plainPassword,
  }) {
    return SearchResult(
      targetType: SearchTargetType.account,
      itemId: item.id,
      accountId: acc.id,
      title: item.name,
      subtitle: value,
      hitField: field,
      hitValue: value,
      itemType: item.type,
      folderName: folderName,
      url: item.url,
      siteNote: item.siteNote,
      username: acc.username,
      accountNote: acc.note,
      password: plainPassword,
    );
  }

  /// 构造 API Key 级命中结果，并把条目、账号与 API Key 的上下文透传给搜索页。
  SearchResult _keyResult({
    required PasswordItem item,
    required Account acc,
    required ApiKey k,
    required String field,
    required String value,
    String? folderName,
    String? plainKey,
  }) {
    return SearchResult(
      targetType: SearchTargetType.apiKey,
      itemId: item.id,
      accountId: acc.id,
      apiKeyId: k.id,
      title: item.name,
      subtitle: value,
      hitField: field,
      hitValue: value,
      itemType: item.type,
      folderName: folderName,
      url: item.url,
      siteNote: item.siteNote,
      username: acc.username,
      accountNote: acc.note,
      apiKey: plainKey,
      apiKeyNote: k.note,
    );
  }
}

/// 引用常量，避免与 services 层耦合
class ItemType2 {
  static const String password = 'password';
  static const String apikey = 'apikey';
}
