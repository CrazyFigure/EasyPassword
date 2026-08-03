/// 加密服务：AES-256-GCM 字段加密 + PBKDF2 密钥派生
/// 所有密码/API Key 字段以 iv||ciphertext||tag 的 Base64 形式存储
library;

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class CryptoService {
  static final _random = Random.secure();
  static const int _pbkdf2Iterations = 210000;
  static const int _saltLength = 16;
  static const int _ivLength = 12;

  // 当前加密密钥（32 字节）。由应用锁密码派生，或回退到设备密钥。
  List<int> _key = List<int>.filled(32, 0);
  bool _keyReady = false;

  bool get isKeyReady => _keyReady;

  /// 生成随机盐（hex）
  String generateSalt() {
    final bytes = _randomBytes(_saltLength);
    return base64Encode(bytes);
  }

  /// 生成随机设备密钥（hex），无应用锁时的本地主密钥
  String generateDeviceKey() {
    return base64Encode(_randomBytes(32));
  }

  /// 由密码派生 32 字节主密钥
  Future<String> deriveKeyFromPassword(String password, String saltHex) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: 256,
    );
    final secretKey = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: base64Decode(saltHex),
    );
    return base64Encode(await secretKey.extractBytes());
  }

  /// 设置当前主密钥（base64）
  void setKey(String keyB64) {
    _key = base64Decode(keyB64);
    _keyReady = true;
  }

  /// 加密明文，返回 base64(iv||ciphertext||tag)
  Future<String> encrypt(String plaintext) async {
    assert(_keyReady, 'crypto key not ready');
    final aes = AesGcm.with256bits();
    final iv = _randomBytes(_ivLength);
    final secretBox = await aes.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(_key),
      nonce: iv,
    );
    final payload = <int>[...iv, ...secretBox.cipherText, ...secretBox.mac.bytes];
    return base64Encode(payload);
  }

  /// 解密 base64(iv||ciphertext||tag)，失败返回原串（容错）
  Future<String> decrypt(String payloadB64) async {
    if (payloadB64.isEmpty) return '';
    try {
      final payload = base64Decode(payloadB64);
      if (payload.length <= _ivLength) return payloadB64;
      final iv = payload.sublist(0, _ivLength);
      final ct = payload.sublist(_ivLength, payload.length - 16);
      final tag = payload.sublist(payload.length - 16);
      final aes = AesGcm.with256bits();
      final clear = await aes.decrypt(
        SecretBox(ct, nonce: iv, mac: Mac(tag)),
        secretKey: SecretKey(_key),
      );
      return utf8.decode(clear);
    } catch (_) {
      // 密钥不匹配或数据损坏时返回原文，避免崩溃
      return payloadB64;
    }
  }

  /// 纯文本与加密串的双向工具：加解密一条明文
  Future<String> encryptOrPlain(String plaintext) => encrypt(plaintext);

  List<int> _randomBytes(int length) {
    final list = List<int>.generate(length, (_) => _random.nextInt(256));
    return list;
  }
}
