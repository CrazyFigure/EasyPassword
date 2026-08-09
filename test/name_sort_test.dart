/// 名称排序规则测试：数字优先、字母与汉字按拼音混排。
library;

import 'package:easypassword/core/name_sort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 按规则排序后返回名称列表，便于逐条核对顺序
  List<String> sorted(List<String> names) =>
      sortByName(names, (name) => name);

  group('分档：数字 → 字母/汉字 → 符号', () {
    test('数字开头的名称排在最前', () {
      // 阿里云拼音 aliyun < apple，所以汉字可以排到字母之前
      expect(
        sorted(['Apple', '阿里云', '1Password', 'banana']),
        ['1Password', '阿里云', 'Apple', 'banana'],
      );
    });

    test('符号开头的名称垫底', () {
      expect(
        sorted(['@内部系统', 'Google', '2FA', '_临时']),
        ['2FA', 'Google', '@内部系统', '_临时'],
      );
    });

    test('数字按数值大小而非字符串比较', () {
      expect(
        sorted(['10号机', '2号机', '1号机']),
        ['1号机', '2号机', '10号机'],
      );
    });
  });

  group('字母与汉字按拼音混合排序', () {
    test('汉字按拼音插入字母序列，而不是整体排在字母之后', () {
      // 拼音键：aliyun < apple < baidu < bing < tengxun < zhihu < zoom
      expect(
        sorted(['Zoom', '百度', 'Apple', '腾讯', '阿里云', '知乎', 'Bing']),
        ['阿里云', 'Apple', '百度', 'Bing', '腾讯', '知乎', 'Zoom'],
      );
    });

    test('同首字母的汉字按后续拼音继续比较', () {
      // bai du < bi li bi li < bo shi
      expect(
        sorted(['博世', '哔哩哔哩', '百度']),
        ['百度', '哔哩哔哩', '博世'],
      );
    });

    test('大小写不影响排序位置', () {
      expect(
        sorted(['zebra', 'Apple', 'banana', 'Zoom']),
        ['Apple', 'banana', 'zebra', 'Zoom'],
      );
    });

    test('中英混合名称按整体拼音键比较', () {
      // github < 谷歌(gu ge) < 华为(hua wei)
      expect(
        sorted(['华为云', '谷歌 Cloud', 'GitHub']),
        ['GitHub', '谷歌 Cloud', '华为云'],
      );
    });
  });

  group('稳定性', () {
    test('排序键相同时按原名兜底，顺序不抖动', () {
      // 「李」与「里」同音 li，必须给出确定顺序
      final once = sorted(['里程', '李明', '里程']);
      final twice = sorted(['李明', '里程', '里程']);
      expect(once, twice);
    });

    test('空名称与纯符号不会抛异常', () {
      expect(() => sorted(['', '###', 'A']), returnsNormally);
      expect(sorted(['', '###', 'A']).first, 'A');
    });
  });

  test('compareNames 与 sortByName 结果一致', () {
    expect(compareNames('1A', 'Apple'), lessThan(0));
    expect(compareNames('阿里', 'Bing'), lessThan(0));
    // 拼音键逐字符比较：zhihu 的 "zh" 小于 zoom 的 "zo"，所以知乎在前
    expect(compareNames('Zoom', '知乎'), greaterThan(0));
    expect(compareNames('Apple', 'Apple'), 0);
  });
}
