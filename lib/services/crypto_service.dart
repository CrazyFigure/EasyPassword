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
  static const String _syncPrefix = 'EPS3:';

  // 当前加密密钥（32 字节）。由应用锁密码派生，或回退到设备密钥。
  List<int> _key = List<int>.filled(32, 0);
  bool _keyReady = false;
  // 旧版应用锁 PIN 派生密钥，仅在升级后的当前会话用于读取并迁移历史密文。
  final List<List<int>> _legacyDecryptKeys = [];

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

  /// 注册只读旧密钥。不会用于新数据加密，远端旧快照升级成功后自然淘汰。
  void addLegacyDecryptKey(String keyB64) {
    final key = base64Decode(keyB64);
    if (_legacyDecryptKeys.any((existing) => _sameBytes(existing, key))) return;
    _legacyDecryptKeys.add(key);
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
    final payload = <int>[
      ...iv,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes
    ];
    return base64Encode(payload);
  }

  /// 解密 base64(iv||ciphertext||tag)，失败返回原串（容错）
  Future<String> decrypt(String payloadB64) async {
    if (payloadB64.isEmpty) return '';
    try {
      return await _decryptWithKey(payloadB64, _key);
    } catch (_) {
      for (final legacyKey in _legacyDecryptKeys) {
        try {
          return await _decryptWithKey(payloadB64, legacyKey);
        } catch (_) {
          // 当前旧密钥无法认证时继续尝试下一把，全部失败才执行原有容错。
        }
      }
    }
    // 密钥不匹配或数据损坏时返回原文，避免普通详情页崩溃。
    return payloadB64;
  }

  /// 尝试使用指定 Base64 密钥解密字段；认证失败返回 null。
  /// 仅供旧版“应用锁密码即数据密钥”的一次性迁移使用。
  Future<String?> tryDecryptWithKey(String payloadB64, String keyB64) async {
    if (payloadB64.isEmpty) return '';
    try {
      return await _decryptWithKey(payloadB64, base64Decode(keyB64));
    } catch (_) {
      return null;
    }
  }

  /// 使用 WebDAV 凭据派生的共享密钥加密整个同步快照。
  /// 不同设备只要填写相同连接信息即可解密，且远端始终只有密文。
  Future<String> encryptForSync(
      String plaintext, String secret, String identity) async {
    final key = await _deriveSyncKey(secret, identity);
    return '$_syncPrefix${await _encryptWithKey(plaintext, key)}';
  }

  /// 解密跨设备同步快照；认证失败时明确报错，禁止把损坏密文当 JSON 使用。
  Future<String> decryptForSync(
      String payload, String secret, String identity) async {
    if (!payload.startsWith(_syncPrefix)) {
      // v1/v2 本机快照保持兼容，旧远端若使用同一字段密钥仍可迁移。
      return decrypt(payload);
    }
    final key = await _deriveSyncKey(secret, identity);
    try {
      return await _decryptWithKey(payload.substring(_syncPrefix.length), key);
    } catch (_) {
      throw Exception('同步快照无法解密：请确认各设备使用相同的 WebDAV 地址、用户名和密码');
    }
  }

  /// 纯文本与加密串的双向工具：加解密一条明文
  Future<String> encryptOrPlain(String plaintext) => encrypt(plaintext);

  /// PBKDF2 派生同步专用密钥；identity 的哈希作为稳定盐，避免在远端另存密钥。
  Future<List<int>> _deriveSyncKey(String secret, String identity) async {
    final identityHash = await Sha256().hash(utf8.encode(identity));
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: 256,
    );
    final key = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(secret)),
      nonce: identityHash.bytes.sublist(0, _saltLength),
    );
    return key.extractBytes();
  }

  Future<String> _encryptWithKey(String plaintext, List<int> key) async {
    final iv = _randomBytes(_ivLength);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(key),
      nonce: iv,
    );
    return base64Encode(<int>[...iv, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<String> _decryptWithKey(String payloadB64, List<int> key) async {
    final payload = base64Decode(payloadB64);
    if (payload.length < _ivLength + 16) {
      throw const FormatException('同步快照长度无效');
    }
    final iv = payload.sublist(0, _ivLength);
    final cipherText = payload.sublist(_ivLength, payload.length - 16);
    final tag = payload.sublist(payload.length - 16);
    final clear = await AesGcm.with256bits().decrypt(
      SecretBox(cipherText, nonce: iv, mac: Mac(tag)),
      secretKey: SecretKey(key),
    );
    return utf8.decode(clear);
  }

  bool _sameBytes(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    var difference = 0;
    for (var i = 0; i < first.length; i++) {
      difference |= first[i] ^ second[i];
    }
    return difference == 0;
  }

  List<int> _randomBytes(int length) {
    final list = List<int>.generate(length, (_) => _random.nextInt(256));
    return list;
  }
}
