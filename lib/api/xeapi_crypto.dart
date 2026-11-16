import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// 网易云安卓端的 XEAPI 加密，取高音质（无损以上）播放地址要走这条。
///
/// 实现参照 NeteaseCloudMusicApiEnhanced/api-enhanced 的 `util/crypto.js`：
/// - 先用 [registerForm] 向 `/api/bsr/sk/get` 换一把服务端 X25519 公钥（[XeapiPublicKey]）；
/// - 每个请求随机一把 16 字节动态密钥，请求明文经「静态密钥 AES → 随机异或 + 旋转 → 动态密钥 AES」得到 `C`；
/// - 动态密钥用 X25519 + HKDF + AES-GCM 封给服务端公钥得到 `S`；
/// - `R` 是公钥版本号；
/// - 响应和 EAPI 一样用固定密钥 AES-ECB 解密，可能是 gzip。
abstract final class XeapiCrypto {
  static final _staticKey = _fromHex(
    'ab1d5a430f6bb04a3f01e81ddd72bd916d5ce591248ac128714806d7f8fb1b84',
  );
  static final _signKey = utf8.encode(
    'mUHCwVNWJbunMqAHf5MImuirT6plvs6VSFW62MGHstFQxhBGdEoIhLItH3djc4+FB/OKty3+lL2rGeoFBpVe5g==',
  );
  static final _responseKey = Uint8List.fromList(utf8.encode('e82ckenh8dichen8'));

  /// 注册公钥请求和响应的签名。
  static String sign(String timestamp, String nonce) =>
      base64.encode(Hmac(sha256, _signKey).convert(utf8.encode('$timestamp$nonce')).bytes);

  /// `/api/bsr/sk/get` 的表单。[nonce] 用来校验响应签名。
  static Map<String, String> registerForm({
    required String deviceId,
    required String nonce,
    required String timestamp,
    String currentKeyVersion = '',
  }) => {
    'appVersion': '9.5.61',
    'currentKeyVersion': currentKeyVersion,
    'deviceId': deviceId,
    'nonce': nonce,
    'os': 'android',
    'requestType': 'active',
    'signature': sign(timestamp, nonce),
    't1': '',
    't2': '',
    'timestamp': timestamp,
    'uid': '',
  };

  /// 解开 `/api/bsr/sk/get` 返回的 `encryptedData`。
  static XeapiPublicKey decryptPublicKey(String encryptedData) {
    final json = jsonDecode(utf8.decode(_aesEcb(false, _staticKey, base64.decode(encryptedData))));
    if (json is! Map) throw const FormatException('xeapi public key');
    final key = json['publicKey'];
    final sk = json['sk'];
    if (key is! String || sk is! String || sk.isEmpty) {
      throw const FormatException('xeapi public key');
    }
    return XeapiPublicKey(publicKey: key, version: '${json['version'] ?? ''}', sk: sk);
  }

  /// 加密一个表单请求，返回要 POST 的 `C` / `S` / `R` 三个字段。
  static Map<String, String> encrypt(
    Map<String, String> form,
    XeapiPublicKey key, {
    String os = 'android',
    Random? random,
  }) {
    final rnd = random ?? Random.secure();
    final plaintext = jsonEncode({
      if (form.isNotEmpty)
        'content': form.entries
            .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
            .join('&'),
      'queryString': 'e_r=true',
    });
    final dynamicKey = _randomBytes(rnd, 16);
    final c = _aesEcb(
      true,
      dynamicKey,
      _midTransform(_aesEcb(true, _staticKey, utf8.encode(plaintext)), rnd),
    );
    final s = _sealKey(dynamicKey, key, os, rnd);
    final r = _aesEcb(true, _staticKey, utf8.encode('${key.version}|'));
    return {
      'C': base64Url.encode(c).replaceAll('=', ''),
      'S': base64.encode(s),
      'R': base64.encode(r),
    };
  }

  /// 解密响应体。
  static String decrypt(Uint8List body) {
    final plain = _aesEcb(false, _responseKey, body);
    final bytes = plain.length > 1 && plain[0] == 0x1f && plain[1] == 0x8b
        ? gzip.decode(plain)
        : plain;
    return utf8.decode(bytes);
  }

  // ---------------------------------------------------------------- 内部

  /// 随机 16 字节逐字节异或，再整体循环左移若干字节，随机数放在最前面。
  static Uint8List _midTransform(Uint8List data, Random rnd) {
    final mask = _randomBytes(rnd, 16);
    final xored = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      xored[i] = data[i] ^ mask[i & 0x0f];
    }
    final rot = xored.isEmpty ? 0 : (mask[0] & 0x0f) % xored.length;
    return Uint8List.fromList([...mask, ...xored.sublist(rot), ...xored.sublist(0, rot)]);
  }

  /// 用临时 X25519 密钥和服务端公钥协商出 AES-GCM 密钥，封装「动态密钥|系统|sk」。
  /// 输出：临时公钥 32 字节 + IV 12 字节 + 密文 + 16 字节认证标签。
  static Uint8List _sealKey(Uint8List dynamicKey, XeapiPublicKey key, String os, Random rnd) {
    final peer = base64.decode(key.publicKey);
    final private = _randomBytes(rnd, 32);
    final ephemeral = X25519.publicKey(private);
    final shared = X25519.sharedSecret(private, peer);
    final prk = Hmac(sha256, Uint8List(32)).convert(shared).bytes;
    final aesKey = Uint8List.fromList(
      Hmac(sha256, prk).convert([...ephemeral, 1]).bytes.sublist(0, 16),
    );
    final iv = _randomBytes(rnd, 12);
    final gcm = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(aesKey), 128, iv, Uint8List(0)));
    final sealed = gcm.process(utf8.encode('${base64.encode(dynamicKey)}|$os|${key.sk}'));
    return Uint8List.fromList([...ephemeral, ...iv, ...sealed]);
  }

  static Uint8List _aesEcb(bool forEncryption, Uint8List key, List<int> data) =>
      (PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(AESEngine()))
            ..init(forEncryption, PaddedBlockCipherParameters(KeyParameter(key), null)))
          .process(Uint8List.fromList(data));

  static Uint8List _randomBytes(Random rnd, int n) =>
      Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));

  static Uint8List _fromHex(String hex) => Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

/// 服务端下发的 XEAPI 公钥。
class XeapiPublicKey {
  const XeapiPublicKey({required this.publicKey, required this.version, required this.sk});

  /// 32 字节 X25519 公钥，base64。
  final String publicKey;
  final String version;
  final String sk;
}

/// RFC 7748 X25519（蒙哥马利阶梯，BigInt 实现；每个请求只算两次，性能不是问题）。
abstract final class X25519 {
  static final _p = (BigInt.one << 255) - BigInt.from(19);
  static final _a24 = BigInt.from(121665);
  static final _base = Uint8List(32)..[0] = 9;

  static Uint8List publicKey(List<int> privateKey) => scalarMult(privateKey, _base);

  static Uint8List sharedSecret(List<int> privateKey, List<int> peerPublic) =>
      scalarMult(privateKey, peerPublic);

  static Uint8List scalarMult(List<int> scalar, List<int> uBytes) {
    final k = Uint8List.fromList(scalar);
    k[0] &= 248;
    k[31] &= 127;
    k[31] |= 64;
    final u = Uint8List.fromList(uBytes);
    u[31] &= 127;

    final x1 = _decode(u);
    var x2 = BigInt.one, z2 = BigInt.zero, x3 = x1, z3 = BigInt.one;
    var swap = 0;
    for (var t = 254; t >= 0; t--) {
      final bit = (k[t >> 3] >> (t & 7)) & 1;
      swap ^= bit;
      if (swap == 1) {
        (x2, x3) = (x3, x2);
        (z2, z3) = (z3, z2);
      }
      swap = bit;
      final a = (x2 + z2) % _p;
      final aa = (a * a) % _p;
      final b = (x2 - z2) % _p;
      final bb = (b * b) % _p;
      final e = (aa - bb) % _p;
      final c = (x3 + z3) % _p;
      final d = (x3 - z3) % _p;
      final da = (d * a) % _p;
      final cb = (c * b) % _p;
      final s = (da + cb) % _p;
      final m = (da - cb) % _p;
      x3 = (s * s) % _p;
      z3 = (x1 * ((m * m) % _p)) % _p;
      x2 = (aa * bb) % _p;
      z2 = (e * ((aa + _a24 * e) % _p)) % _p;
    }
    if (swap == 1) {
      (x2, x3) = (x3, x2);
      (z2, z3) = (z3, z2);
    }
    return _encode((x2 * z2.modPow(_p - BigInt.two, _p)) % _p);
  }

  static BigInt _decode(Uint8List bytes) {
    var r = BigInt.zero;
    for (var i = bytes.length - 1; i >= 0; i--) {
      r = (r << 8) | BigInt.from(bytes[i]);
    }
    return r % _p;
  }

  static Uint8List _encode(BigInt v) {
    final out = Uint8List(32);
    var x = v;
    for (var i = 0; i < 32; i++) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x >>= 8;
    }
    return out;
  }
}
