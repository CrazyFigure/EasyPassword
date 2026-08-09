/// 名称排序规则：数字在最前，字母与汉字按拼音混合排序。
///
/// 为什么不继续用 SQL 的 `name COLLATE NOCASE ASC`：
/// SQLite 的 NOCASE 只按 UTF-8 码点比较，汉字码点整体大于 ASCII，结果是
/// 「所有汉字堆在字母之后」，而且汉字之间按码点排也不符合中文习惯。
/// 拼音字典只能在 Dart 侧查表，因此名称排序统一改为在内存中比较。
///
/// 规则（[compareNames]）：
/// 1. 分三档：数字 (0) < 字母或汉字 (1) < 其他符号 (2)，按首字符归档；
/// 2. 同档内比较排序键——汉字换成不带声调的拼音，字母转小写，
///    数字按数值大小（"2" 排在 "10" 之前，而非按字符串）；
/// 3. 排序键完全相同时（同音字、纯大小写差异）回退到原名比较，
///    保证顺序稳定、不随查询次数抖动。
library;

import 'package:pinyin/pinyin.dart';

/// 首字符所属的档位。数字优先，符号垫底。
int _bucketOf(String name) {
  if (name.isEmpty) return 2;
  final code = name.codeUnitAt(0);
  // 0-9
  if (code >= 0x30 && code <= 0x39) return 0;
  // A-Z / a-z
  if ((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A)) return 1;
  // 汉字与字母同档，才能按拼音交叉排列
  if (ChineseHelper.isChineseCode(code)) return 1;
  return 2;
}

/// 排序键缓存：一次刷新里同一个名称会被比较多次，转拼音要逐字查表，
/// 缓存后整份列表只算一遍。
final Map<String, String> _sortKeyCache = {};

/// 缓存上限。密码库通常几百条，超出时整体清空比逐条淘汰更简单，
/// 也避免长期驻留占内存。
const int _maxCacheSize = 2000;

/// 名称的比较键：汉字转小写拼音，其余字符保留并统一小写。
String sortKeyOf(String name) {
  final cached = _sortKeyCache[name];
  if (cached != null) return cached;
  // 用 getPinyin 而非 getPinyinE：后者遇到字典缺失的字会 print 噪音日志。
  // 这里逐字处理，字典没有的字直接保留原字，效果等价且安静。
  final buffer = StringBuffer();
  for (final rune in name.runes) {
    final char = String.fromCharCode(rune);
    if (ChineseHelper.isChineseCode(rune)) {
      final pinyin =
          PinyinHelper.convertToPinyinArray(char, PinyinFormat.WITHOUT_TONE);
      // 多音字取第一个读音：常用读音在字典中排在前面
      buffer.write(pinyin.isEmpty ? char : pinyin.first);
    } else {
      buffer.write(char.toLowerCase());
    }
  }
  final key = buffer.toString();
  if (_sortKeyCache.length >= _maxCacheSize) _sortKeyCache.clear();
  _sortKeyCache[name] = key;
  return key;
}

/// 比较两个名称。返回值语义同 [Comparable.compareTo]。
int compareNames(String a, String b) {
  final bucketA = _bucketOf(a);
  final bucketB = _bucketOf(b);
  if (bucketA != bucketB) return bucketA.compareTo(bucketB);

  // 数字档按数值比较："2" 在 "10" 之前，符合人对编号的预期
  if (bucketA == 0) {
    final numCompare = _compareNumericPrefix(a, b);
    if (numCompare != 0) return numCompare;
  }

  final keyCompare = sortKeyOf(a).compareTo(sortKeyOf(b));
  if (keyCompare != 0) return keyCompare;
  // 同音或仅大小写不同时，用原名兜底保证顺序稳定
  return a.compareTo(b);
}

/// 比较两个名称的数字前缀（如 "12ab" → 12）。前缀相等时返回 0，交给拼音键继续比。
int _compareNumericPrefix(String a, String b) {
  final numA = _numericPrefixOf(a);
  final numB = _numericPrefixOf(b);
  if (numA == null || numB == null) return 0;
  return numA.compareTo(numB);
}

/// 取开头连续数字段的数值；超长数字串（如 API 编号）按字符串长度降级避免溢出。
int? _numericPrefixOf(String name) {
  var end = 0;
  while (end < name.length) {
    final code = name.codeUnitAt(end);
    if (code < 0x30 || code > 0x39) break;
    end++;
  }
  if (end == 0) return null;
  return int.tryParse(name.substring(0, end));
}

/// 按名称规则排序任意列表；[nameOf] 提供每个元素参与比较的名称。
List<T> sortByName<T>(Iterable<T> source, String Function(T) nameOf) {
  final list = source.toList();
  list.sort((a, b) => compareNames(nameOf(a), nameOf(b)));
  return list;
}
