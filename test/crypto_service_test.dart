/// 加密服务单元测试
library;

import 'package:easypassword/services/crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CryptoService', () {
    test('加解密往返一致', () async {
      final crypto = CryptoService();
      final key = crypto.generateDeviceKey();
      crypto.setKey(key);

      const plain = 'MySecretPassword123!';
      final enc = await crypto.encrypt(plain);
      expect(enc, isNot(contains(plain))); // 不包含明文

      final dec = await crypto.decrypt(enc);
      expect(dec, plain);
    });

    test('不同密钥解密失败时返回原串（容错）', () async {
      final crypto = CryptoService();
      crypto.setKey(crypto.generateDeviceKey());
      final enc = await crypto.encrypt('secret');

      final crypto2 = CryptoService();
      crypto2.setKey(crypto2.generateDeviceKey());
      final dec = await crypto2.decrypt(enc);
      // 解密失败返回原密文（容错设计）
      expect(dec, enc);
    });

    test('同一明文两次加密结果不同（随机 IV）', () async {
      final crypto = CryptoService();
      crypto.setKey(crypto.generateDeviceKey());
      final a = await crypto.encrypt('same');
      final b = await crypto.encrypt('same');
      expect(a, isNot(b));
    });

    test('密码派生密钥稳定', () async {
      final crypto = CryptoService();
      final salt = crypto.generateSalt();
      final k1 = await crypto.deriveKeyFromPassword('pin123', salt);
      final k2 = await crypto.deriveKeyFromPassword('pin123', salt);
      expect(k1, k2);
    });
  });
}
