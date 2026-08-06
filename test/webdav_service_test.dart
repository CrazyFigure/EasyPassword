/// WebDAV 同步快照与合并单元测试（本地逻辑，不依赖网络）
library;

import 'package:easypassword/services/crypto_service.dart';
import 'package:easypassword/services/data_service.dart';
import 'package:easypassword/services/database.dart';
import 'package:easypassword/services/app_lock_service.dart';
import 'package:easypassword/services/webdav_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseService.overridePath = inMemoryDatabasePath;
  });

  late CryptoService crypto;
  late String deviceKey;
  late DataService data;
  late WebDavService webdav;

  setUp(() async {
    crypto = CryptoService();
    deviceKey = crypto.generateDeviceKey();
    crypto.setKey(deviceKey);
    data = DataService(crypto);
    webdav = WebDavService(crypto, data);
    final db = await DatabaseService.db;
    await db.delete('api_keys');
    await db.delete('accounts');
    await db.delete('password_items');
    await db.delete('folders');
    await db.delete('settings');
    await db.delete('sync_journal');
  });

  test('加密快照不包含明文', () async {
    final item = await data.addItem('password', 'Google');
    await data.addAccount(item.id, 'user@gmail.com', 'TopSecret123');

    final snapshot = await webdav.buildSnapshot();
    expect(snapshot, isNot(contains('TopSecret123')));
    expect(snapshot, isNot(contains('user@gmail.com')));
  });

  test('快照可恢复全部数据（跨设备恢复）', () async {
    // 设备 A：写入数据并生成快照
    final item = await data.addItem('apikey', 'OpenAI',
        url: 'https://platform.openai.com', siteNote: 'API 平台');
    final acc = await data.addAccount(item.id, 'admin@openai.com', 'pwd123');
    await data.addApiKey(acc.id, 'sk-proj-xyz', note: '生产');

    final snapshot = await webdav.buildSnapshot();

    // 设备 B：清空本地数据后合并快照
    final db = await DatabaseService.db;
    await db.delete('api_keys');
    await db.delete('accounts');
    await db.delete('password_items');

    final merged = await webdav.mergeSnapshot(snapshot);
    expect(merged, 1);

    final items = await data.listItems('apikey');
    expect(items.length, 1);
    expect(items.first.name, 'OpenAI');
    expect(items.first.siteNote, 'API 平台');

    final accounts = await data.listAccounts(items.first.id);
    expect(accounts.length, 1);
    expect(accounts.first.username, 'admin@openai.com');
    expect(await data.plainPassword(accounts.first), 'pwd123');

    final keys = await data.listApiKeys(accounts.first.id);
    expect(keys.length, 1);
    expect(await data.plainKey(keys.first), 'sk-proj-xyz');
  });

  test('不同设备使用不同本地密钥仍可同步密码、API Key 与系统设置', () async {
    const baseUrl = 'https://dav.example.com/dav/';
    const username = 'sync-user';
    const password = 'webdav-app-password';

    // 设备 A 使用自己的随机字段密钥写入数据，并生成 WebDAV 共享密钥快照。
    final item = await data.addItem('apikey', '跨端服务');
    final account = await data.addAccount(item.id, 'device-a', 'password-a');
    await data.addApiKey(account.id, 'key-a');
    final lockTime = DateTime.now().millisecondsSinceEpoch;
    await DatabaseService.setSetting('font_scale', '1.15', updatedAt: lockTime);
    await DatabaseService.setSetting('app_lock_enabled', '1',
        updatedAt: lockTime);
    await DatabaseService.setSetting('app_lock_pin_hash', 'pin-hash',
        updatedAt: lockTime);
    final snapshot = await webdav.buildSnapshot(
      baseUrl: baseUrl,
      username: username,
      password: password,
    );

    // 设备 B 模拟为另一把随机字段密钥；同步快照必须仍可解密并在本机重加密。
    final db = await DatabaseService.db;
    await db.delete('api_keys');
    await db.delete('accounts');
    await db.delete('password_items');
    await db.delete('settings');
    final cryptoB = CryptoService()
      ..setKey(CryptoService().generateDeviceKey());
    final dataB = DataService(cryptoB);
    final webdavB = WebDavService(cryptoB, dataB);
    await webdavB.mergeSnapshot(
      snapshot,
      // 尾斜杠差异必须规范化为同一个同步身份。
      baseUrl: 'https://dav.example.com/dav',
      username: username,
      password: password,
    );

    final restoredItems = await dataB.listItems('apikey');
    final restoredAccounts = await dataB.listAccounts(restoredItems.single.id);
    final restoredKeys = await dataB.listApiKeys(restoredAccounts.single.id);
    expect(await dataB.plainPassword(restoredAccounts.single), 'password-a');
    expect(await dataB.plainKey(restoredKeys.single), 'key-a');
    expect(await DatabaseService.getSetting('font_scale'), '1.15');
    expect(await DatabaseService.getSetting('app_lock_enabled'), '1');
    expect(await DatabaseService.getSetting('app_lock_pin_hash'), 'pin-hash');
  });

  test('远端路径会规范化且拒绝目录穿越片段', () {
    expect(WebDavService.normalizeRemotePath(''), '/EasyPassword');
    expect(
      WebDavService.normalizeRemotePath(r'\backup\mobile\'),
      '/backup/mobile',
    );
    expect(
      () => WebDavService.normalizeRemotePath('/backup/../other'),
      throwsException,
    );
  });

  test('服务器地址已包含配置路径时仍使用同一个快照加密身份', () async {
    await data.addItem('password', '路径兼容测试');
    final snapshot = await webdav.buildSnapshot(
      baseUrl: 'https://dav.example.com/dav/',
      username: 'user',
      password: 'pass',
      remotePath: '/backup/mobile',
    );

    await expectLater(
      webdav.mergeSnapshot(
        snapshot,
        baseUrl: 'https://dav.example.com/dav/backup/mobile/',
        username: 'user',
        password: 'pass',
        remotePath: '/backup/mobile',
      ),
      completes,
    );
  });

  test('旧服务器地址中的路径大小写不会在升级后改变', () async {
    await data.addItem('password', '旧路径兼容测试');
    final snapshot = await webdav.buildSnapshot(
      baseUrl: 'https://dav.example.com/dav/easypassword/',
      username: 'user',
      password: 'pass',
    );

    await expectLater(
      webdav.mergeSnapshot(
        snapshot,
        baseUrl: 'https://dav.example.com/dav/',
        username: 'user',
        password: 'pass',
        remotePath: '/easypassword',
      ),
      completes,
    );
  });

  test('同一条目的修改与删除冲突始终由 updated_at 更新的一侧胜出', () async {
    final item = await data.addItem('password', '待删除条目');
    await data.deleteItem(item.id);
    final db = await DatabaseService.db;
    final deletedRow = (await db
            .query('password_items', where: 'id = ?', whereArgs: [item.id]))
        .single;
    final deletedAt = deletedRow['updated_at'] as int;
    final deleteSnapshot = await webdav.buildSnapshot();

    // 本地较早修改不能覆盖远端较晚删除，合并后条目保持不可见。
    await db.update(
      'password_items',
      {'name': '较早的本地修改', 'deleted': 0, 'updated_at': deletedAt - 1000},
      where: 'id = ?',
      whereArgs: [item.id],
    );
    await webdav.mergeSnapshot(deleteSnapshot);
    expect(await data.listItems('password'), isEmpty);

    // 反过来，较晚修改应能胜过较早删除并恢复条目。
    await db.update(
      'password_items',
      {'name': '较晚的远端修改', 'deleted': 0, 'updated_at': deletedAt + 1000},
      where: 'id = ?',
      whereArgs: [item.id],
    );
    final modifySnapshot = await webdav.buildSnapshot();
    await db.update(
      'password_items',
      {'name': '较早删除', 'deleted': 1, 'updated_at': deletedAt},
      where: 'id = ?',
      whereArgs: [item.id],
    );
    await webdav.mergeSnapshot(modifySnapshot);
    final restored = await data.listItems('password');
    expect(restored.single.name, '较晚的远端修改');
  });

  test('离线修改会写入同步日志且成功水位清理不会误删后续修改', () async {
    await data.addItem('password', '离线新增');
    expect(await DatabaseService.hasPendingSyncChanges(), isTrue);
    final firstWatermark = await DatabaseService.getSyncJournalHighWaterMark();

    await data.addItem('password', '同步期间新增');
    await DatabaseService.clearSyncJournalThrough(firstWatermark);

    // 水位之后的新日志仍存在，下一轮自动同步会继续上传。
    expect(await DatabaseService.hasPendingSyncChanges(), isTrue);
  });

  test('升级后首次解锁会迁移旧 PIN 密钥字段且不破坏设备密钥字段', () async {
    await DatabaseService.setSetting('device_key', deviceKey);
    final appLock = AppLockService(crypto);
    await appLock.enable('246810', '问题', '答案');
    final salt = (await DatabaseService.getSetting('app_lock_salt'))!;
    final legacyKey = await crypto.deriveKeyFromPassword('246810', salt);

    // 开启应用锁前已经存在的字段仍由设备密钥加密，迁移时必须原样保留。
    final currentItem = await data.addItem('password', '设备密钥数据');
    await data.addAccount(currentItem.id, 'current-user', 'current-secret');

    // 模拟旧版解锁后用 PIN 派生密钥新建的密码字段。
    final db = await DatabaseService.db;
    await db.delete('settings',
        where: 'key = ?', whereArgs: ['data_key_decoupled']);
    crypto.setKey(legacyKey);
    final item = await data.addItem('password', '旧版数据');
    await data.addAccount(item.id, 'legacy-user', 'legacy-secret');
    final legacySnapshotCipher = await crypto.encrypt('legacy-snapshot');

    // 新版启动时字段密钥已恢复为设备密钥，首次解锁负责一次性迁移旧密文。
    crypto.setKey(deviceKey);
    await appLock.unlockWithPin('246810');
    final account = (await data.listAccounts(item.id)).single;
    final currentAccount = (await data.listAccounts(currentItem.id)).single;
    expect(await data.plainPassword(account), 'legacy-secret');
    expect(await data.plainPassword(currentAccount), 'current-secret');
    expect(await crypto.decrypt(legacySnapshotCipher), 'legacy-snapshot');
    expect(await DatabaseService.getSetting('data_key_decoupled'), '1');
  });
}
