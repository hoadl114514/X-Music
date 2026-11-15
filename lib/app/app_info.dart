/// 应用显示名、版本和项目地址。
abstract final class AppInfo {
  static const name = 'X-Music';

  /// 和发布标签（去掉 v）保持一致，检查更新靠它比较。
  /// 小修复版用第四段（如 0.1.2.1）；pubspec.yaml 只能写三段，那时只加 build 号。
  static const version = '0.1.2.1';

  static const repo = 'hoadl114514/X-Music';
  static const repoUrl = 'https://github.com/$repo';
  static const releasesUrl = '$repoUrl/releases';
}
