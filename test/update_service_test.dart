/// 更新检查测试：覆盖版本比较、Release 资源识别与网络回退错误分类。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:easypassword/services/update_service.dart';

void main() {
  /// 构造与 GitHub Releases API 结构一致的最小成功响应。
  http.Response releaseResponse(String tag) {
    return http.Response.bytes(
      utf8.encode(jsonEncode({
        'tag_name': tag,
        'name': '$tag 正式版',
        'html_url': 'https://github.com/CrazyFigure/EasyPassword/releases/$tag',
        'published_at': '2026-08-06T05:50:26Z',
        'assets': [
          {'name': 'EasyPassword-$tag.apk'},
          {'name': 'EasyPassword-Setup-${tag.substring(1)}.exe'},
        ],
      })),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  test('远端版本更高时识别新版和 Windows 安装包', () async {
    final service = UpdateService(
      currentVersion: '0.2.0',
      fetcher: (_) async => releaseResponse('v0.2.1'),
    );

    final result = await service.check();

    expect(result.updateAvailable, isTrue);
    expect(result.currentVersion, '0.2.0');
    expect(result.latestVersion, '0.2.1');
    expect(result.installerAssetName, 'EasyPassword-Setup-0.2.1.exe');
  });

  test('安装包版本与最新 Release 相同时判定为最新版', () async {
    final service = UpdateService(
      currentVersion: '0.2.0',
      fetcher: (_) async => releaseResponse('v0.2.0'),
    );

    final result = await service.check();

    expect(result.updateAvailable, isFalse);
  });

  test('系统代理与直连都失败时返回 network 错误', () async {
    final proxyModes = <bool>[];
    final service = UpdateService(
      currentVersion: '0.2.0',
      fetcher: (useSystemProxy) async {
        proxyModes.add(useSystemProxy);
        throw http.ClientException('连接失败');
      },
    );

    await expectLater(
      service.check(),
      throwsA(
        isA<UpdateCheckException>()
            .having((error) => error.code, 'code', 'network'),
      ),
    );
    expect(proxyModes, [true, false]);
  });

  test('非法 Release 标签返回 parse 错误而不是误报最新版', () async {
    final service = UpdateService(
      currentVersion: '0.2.0',
      fetcher: (_) async => releaseResponse('latest'),
    );

    await expectLater(
      service.check(),
      throwsA(
        isA<UpdateCheckException>()
            .having((error) => error.code, 'code', 'parse'),
      ),
    );
  });
}
