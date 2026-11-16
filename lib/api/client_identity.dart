import 'dart:math';

/// 请求时自报的客户端身份：系统、版本号、渠道和配套的 User-Agent。
///
/// 网易云按身份决定放行哪些操作（例如 PC / 网页身份不能分享歌曲到动态），
/// 所以同一种身份的各个字段要互相对得上，不能 UA 是一个客户端、Cookie 里又是另一个。
/// 取值参照 api-enhanced 的 `util/request.js`（osMap / userAgentMap）。
class ClientProfile {
  const ClientProfile({
    required this.os,
    required this.appver,
    required this.osver,
    required this.channel,
    required this.userAgent,
  });

  final String os;
  final String appver;
  final String osver;
  final String channel;
  final String userAgent;

  /// PC 客户端：明文 `/api/` 和 EAPI 用它。
  static const pc = ClientProfile(
    os: 'pc',
    appver: '3.1.17.204416',
    osver: 'Microsoft-Windows-10-Professional-build-19045-64bit',
    channel: 'netease',
    userAgent:
        'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/3.1.17.204416',
  );

  /// macOS 客户端：播放日志只认它。
  static const osx = ClientProfile(
    os: 'osx',
    appver: '3.1.10.5100',
    osver: '15.5',
    channel: 'netease',
    userAgent:
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  );

  /// 安卓客户端：XEAPI 用它（高音质播放地址、分享到动态）。
  ///
  /// appver / osver 和 api-enhanced 的 XEAPI 请求一致；User-Agent 和注册公钥的版本一致。
  static const android = ClientProfile(
    os: 'android',
    appver: '9.1.65',
    osver: '16',
    channel: 'xiaomi',
    userAgent:
        'NeteaseMusic/9.5.61.260802021928(9005061);Dalvik/2.1.0 '
        '(Linux; U; Android 12; HBN-AL00 Build/cd737a2.0)',
  );

  /// 网页端：WEAPI 用它。Cookie 里的设备字段沿用 PC 的（和 api-enhanced 一致），只换 UA。
  static const web = ClientProfile(
    os: 'pc',
    appver: '3.1.17.204416',
    osver: 'Microsoft-Windows-10-Professional-build-19045-64bit',
    channel: 'netease',
    userAgent:
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0',
  );

  /// 写进 Cookie / EAPI 加密头里的设备字段。
  Map<String, String> fields(String deviceId) => {
    'os': os,
    'appver': appver,
    'osver': osver,
    'channel': channel,
    'deviceId': deviceId,
  };

  /// 身份相关的 Cookie 键：用户 Cookie 里的这些字段一律被身份覆盖（deviceId 除外）。
  static const keys = {'os', 'appver', 'osver', 'channel', 'buildver', 'versioncode', 'sDeviceId'};

  /// 52 位十六进制设备号（和 api-enhanced 生成的格式一致）。
  /// 每台设备生成一次后保存，所有接口共用同一个。
  static String newDeviceId([Random? random]) {
    final rnd = random ?? Random.secure();
    const hex = '0123456789ABCDEF';
    return String.fromCharCodes(List.generate(52, (_) => hex.codeUnitAt(rnd.nextInt(16))));
  }
}
