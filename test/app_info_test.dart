import 'package:easypassword/core/constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('应用内版本读取 Flutter 构建产物的包版本', () async {
    // 模拟平台插件返回由 pubspec 或 CI --build-name 写入的包元数据。
    PackageInfo.setMockInitialValues(
      appName: 'EasyPassword',
      packageName: 'com.easypassword.app',
      version: '0.2.9',
      buildNumber: '1',
      buildSignature: '',
    );

    await AppInfo.initialize();

    expect(AppInfo.currentVersion, '0.2.9');
  });
}
