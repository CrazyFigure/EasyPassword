import 'dart:io';

import 'package:easypassword/core/app_environment.dart';
import 'package:easypassword/services/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('测试进程默认使用独立开发数据库环境', () {
    expect(AppEnvironment.usesDevelopmentStorage, isTrue);
    expect(
      AppEnvironment.webDavSnapshotFileName,
      'easypassword-dev-snapshot.json.enc',
    );
  });

  test('开发数据库定位到项目内且不命中安装版目录', () async {
    final databasePath = await DatabaseService.resolveDefaultPathForTest();

    expect(
      p.normalize(databasePath),
      p.normalize(
        p.join(Directory.current.path, '.dev-data', 'easypassword.db'),
      ),
    );
  });
}
