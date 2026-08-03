/// 应用锁服务：密码校验、安全问题恢复、主密钥派生（需求 3.5.1）
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'crypto_service.dart';
import 'database.dart';

class AppLockService {
  final CryptoService crypto;
  AppLockService(this.crypto);

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
    await DatabaseService.setSetting('app_lock_enabled', '1');
    await DatabaseService.setSetting('app_lock_pin_hash', hash);
    await DatabaseService.setSetting('app_lock_salt', salt);
    await DatabaseService.setSetting('security_question', question);
    await DatabaseService.setSetting('security_answer_hash', answerHash);
    // 派生并设置主密钥（加密数据将用该密钥重加密）
    final key = await crypto.deriveKeyFromPassword(pin, salt);
    crypto.setKey(key);
  }

  /// 关闭应用锁：回退到设备密钥
  Future<void> disable() async {
    final deviceKey = await DatabaseService.getSetting('device_key') ??
        crypto.generateDeviceKey();
    await DatabaseService.setSetting('device_key', deviceKey);
    await DatabaseService.setSetting('app_lock_enabled', '0');
    await DatabaseService.setSetting('app_lock_pin_hash', '');
    await DatabaseService.setSetting('app_lock_salt', '');
    crypto.setKey(deviceKey);
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

  /// 解锁时用密码派生主密钥（校验通过后调用）
  Future<void> unlockWithPin(String pin) async {
    final salt = await DatabaseService.getSetting('app_lock_salt');
    if (salt == null) return;
    final key = await crypto.deriveKeyFromPassword(pin, salt);
    crypto.setKey(key);
  }

  /// 通过安全问题重置密码
  Future<void> resetPin(String newPin, String question, String answer) async {
    await enable(newPin, question, answer);
  }

  /// 初始化密钥：有锁时提示用户输入，无锁时使用设备密钥
  Future<void> initKey() async {
    final enabled = await isEnabled();
    if (!enabled) {
      var deviceKey = await DatabaseService.getSetting('device_key');
      if (deviceKey == null) {
        deviceKey = crypto.generateDeviceKey();
        await DatabaseService.setSetting('device_key', deviceKey);
      }
      crypto.setKey(deviceKey);
    }
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
