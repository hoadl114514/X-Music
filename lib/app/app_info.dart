/// 应用显示名、版本和项目地址。
abstract final class AppInfo {
  static const name = 'X-Music';

  /// 和 pubspec.yaml 的 version、发布标签（去掉 v）保持一致，检查更新靠它比较。
  static const version = '0.1.1';

  static const repo = 'hoadl114514/X-Music';
  static const repoUrl = 'https://github.com/$repo';
  static const releasesUrl = '$repoUrl/releases';
}
