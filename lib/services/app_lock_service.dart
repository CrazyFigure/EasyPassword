/// 应用锁服务：密码校验、安全问题恢复、主密钥派生（需求 3.5.1）
library;

import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'crypto_service.dart';
import 'database.dart';

class AppLockService {
  final CryptoService crypto;
  AppLockService(this.crypto);

  /// 应用锁设置保存后的通知入口，用于把锁配置纳入自动同步。
  Future<void> Function()? onChanged;

  void _notifyChanged() {
    final callback = onChanged;
    if (callback != null) unawaited(callback());
  }

  static const int _pinIterations = 210000;

  /// 应用锁是否开启
  Future<bool> isEnabled() async {
    final v = await DatabaseService.getSetting('app_lock_enabled');
    return v == '1';
  }

  /// 开启应用锁：保存密码哈希、盐、安全问题；派生主密钥
  Future<void> enable(String pin, String question, String answer) async {
    final salt = crypto.generateSalt();
    final hash = await _hashPin(pin, salt);
    final answerHash = await _hashAnswer(answer, salt);
    // 同一批锁设置使用同一个时间，防止多端合并出盐与哈希不配套的组合。
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    await DatabaseService.setSetting('app_lock_enabled', '1',
        updatedAt: updatedAt);
    await DatabaseService.setSetting('app_lock_pin_hash', hash,
        updatedAt: updatedAt);
    await DatabaseService.setSetting('app_lock_salt', salt,
        updatedAt: updatedAt);
    await DatabaseService.setSetting('security_question', question,
        updatedAt: updatedAt);
    await DatabaseService.setSetting('security_answer_hash', answerHash,
        updatedAt: updatedAt);
    await DatabaseService.setSetting('data_key_decoupled', '1');
    // 应用锁只负责访问控制；字段始终使用本机数据密钥，避免改 PIN 或
    // 跨设备同步锁设置后，历史密码因密钥切换而无法解密。
    _notifyChanged();
  }

  /// 关闭应用锁：回退到设备密钥
  Future<void> disable() async {
    final deviceKey = await DatabaseService.getSetting('device_key') ??
        crypto.generateDeviceKey();
    await DatabaseService.setSetting('device_key', deviceKey);
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    await DatabaseService.setSetting('app_lock_enabled', '0',
        updatedAt: updatedAt);
    await DatabaseService.setSetting('app_lock_pin_hash', '',
        updatedAt: updatedAt);
    await DatabaseService.setSetting('app_lock_salt', '', updatedAt: updatedAt);
    crypto.setKey(deviceKey);
    _notifyChanged();
  }

  /// 校验应用锁密码
  Future<bool> verify(String pin) async {
    final hash = await DatabaseService.getSetting('app_lock_pin_hash');
    final salt = await DatabaseService.getSetting('app_lock_salt');
    if (hash == null || salt == null) return false;
    final calc = await _hashPin(pin, salt);
    return _safeEquals(calc, hash);
  }

  /// 获取安全问题
  Future<String?> getSecurityQuestion() =>
      DatabaseService.getSetting('security_question');

  /// 校验安全问题答案
  Future<bool> verifySecurityAnswer(String answer) async {
    final answerHash = await DatabaseService.getSetting('security_answer_hash');
    final salt = await DatabaseService.getSetting('app_lock_salt');
    if (answerHash == null || salt == null) return false;
    final calc = await _hashAnswer(answer, salt);
    return _safeEquals(calc, answerHash);
  }

  /// 解锁仅完成访问授权；本机字段密钥与应用锁密码解耦。
  Future<void> unlockWithPin(String pin) async {
    // 保留参数以维持调用语义；PIN 已由 verify 完成校验。
    if (pin.isEmpty) return;
    await _migrateLegacyPinEncryptedFields(pin);
  }

  /// 通过安全问题重置密码
  Future<void> resetPin(String newPin, String question, String answer) async {
    await enable(newPin, question, answer);
  }

  /// 初始化本机数据密钥。应用锁是否开启不再改变字段加密密钥。
  Future<void> initKey() async {
    var deviceKey = await DatabaseService.getSetting('device_key');
    if (deviceKey == null || deviceKey.isEmpty) {
      deviceKey = crypto.generateDeviceKey();
      await DatabaseService.setSetting('device_key', deviceKey);
    }
    crypto.setKey(deviceKey);
  }

  /// v1.1 及更早版本会在解锁后把字段密钥切换为 PIN 派生密钥，导致库中
  /// 可能同时存在设备密钥和旧 PIN 密钥两类密文。首次成功解锁时逐字段
  /// 探测旧密钥，只重加密确实能被旧密钥认证的数据，避免升级后丢失密码。
  Future<void> _migrateLegacyPinEncryptedFields(String pin) async {
    final salt = await DatabaseService.getSetting('app_lock_salt');
    if (salt == null || salt.isEmpty) return;
    final legacyKey = await crypto.deriveKeyFromPassword(pin, salt);
    // 即使字段已迁移，也保留本次会话的旧密钥以读取尚未升级的 v1/v2 远端快照。
    crypto.addLegacyDecryptKey(legacyKey);
    if (await DatabaseService.getSetting('data_key_decoupled') == '1') return;
    final db = await DatabaseService.db;
    await db.transaction((txn) async {
      for (final row in await txn.query('accounts')) {
        final encrypted = row['password_enc']?.toString() ?? '';
        final plain = await crypto.tryDecryptWithKey(encrypted, legacyKey);
        if (plain == null) continue;
        await txn.update(
          'accounts',
          {'password_enc': await crypto.encrypt(plain)},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      for (final row in await txn.query('api_keys')) {
        final encrypted = row['key_enc']?.toString() ?? '';
        final plain = await crypto.tryDecryptWithKey(encrypted, legacyKey);
        if (plain == null) continue;
        await txn.update(
          'api_keys',
          {'key_enc': await crypto.encrypt(plain)},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    });
    await DatabaseService.setSetting('data_key_decoupled', '1');
  }

  Future<String> _hashPin(String pin, String saltHex) async {
    final algo = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pinIterations,
      bits: 256,
    );
    final key = await algo.deriveKey(
      secretKey: SecretKey(utf8.encode('pin:$pin')),
      nonce: base64Decode(saltHex),
    );
    return base64Encode(await key.extractBytes());
  }

  Future<String> _hashAnswer(String answer, String saltHex) async {
    final algo = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    final key = await algo.deriveKey(
      secretKey: SecretKey(utf8.encode('ans:${answer.trim().toLowerCase()}')),
      nonce: base64Decode(saltHex),
    );
    return base64Encode(await key.extractBytes());
  }

  bool _safeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
