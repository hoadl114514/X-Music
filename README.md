<p align="center"><img src="android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" width="96" alt="X-Music"></p>

# X-Music

一个基于 Flutter 开发的网易云音乐第三方客户端。
小项目，不喜勿喷，有问题欢迎在 [issue](https://github.com/hoadl114514/X-Music/issues) 指出。

> 当前版本：v0.1.1。已接入网易云接口和真实播放。目前只做手机端（Android + iOS）。
>
> 第三方客户端，与网易云音乐官方无关。

## 下载

到 [Releases](https://github.com/hoadl114514/X-Music/releases) 下载 APK。大多数手机选 `arm64-v8a`，不确定就选 `universal`。

- 从 v0.1.0 起，安装包使用正式签名。之前的 alpha 版是 debug 签名，需要先卸载旧版再安装（登录状态和设置会清空）。
- App 启动时会检查 GitHub 上的新正式版，有更新就弹窗提示；设置页「关于」下面也可以手动检查。

**电脑版（预览）**：每次推送后，GitHub Actions 的 Build 运行里有 `x-music-windows`（解压后运行 `X-Music.exe`）和 `x-music-macos`（`.dmg` / `.zip`）。macOS 版没有签名，第一次打开要在「访达」里右键 →「打开」，或运行 `xattr -cr /Applications/X-Music.app`。

| 首页 | 抽屉侧栏 | 播放页 | 播放页下滑 | 全屏歌词 |
| --- | --- | --- | --- | --- |
| ![](docs/preview/home.png) | ![](docs/preview/drawer.png) | ![](docs/preview/now-playing.png) | ![](docs/preview/now-playing-cards.png) | ![](docs/preview/lyrics.png) |

## 运行

需要 Flutter 3.47+（Dart 3.13+）。

```bash
flutter pub get
flutter run              # 连接 Android / iOS 设备或模拟器
flutter run -d windows   # Windows 电脑版（需要 Visual Studio 的 C++ 桌面开发组件和 rustup）
flutter run -d macos     # macOS 电脑版（需要 Xcode）
```

构建正式签名的 APK：在 `android/` 下新建 `key.properties`（已被 `.gitignore` 忽略），写入 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`，再运行 `flutter build apk --release`。没有这个文件时 release 包退回 debug 签名，只适合本地调试。

`web/` 目录只用于在浏览器里快速预览界面，不是发布目标（QQ 歌词解密依赖 64 位整数，Web 上不可用）。

## 已实现

- **登录**：扫码（用网易云 App 扫一扫）或粘贴 Cookie（需要包含 `MUSIC_U`，只保存在本机）。未登录也能搜索、播放免费歌曲的标准音质。
- **搜索**：单曲 / 歌单 / 歌手 / 专辑，输入时联想，滚到底自动翻页；保留最近 20 条搜索历史（可单条删除或清空）。
- **歌单**：首页「我的歌单」、底部「我喜欢」；点歌开始播放整张歌单。歌单没有封面或封面加载失败时，用第一首歌的封面。
- **播放**：just_audio；上一首 / 下一首、随机、单曲循环（播放模式会记住，重启后沿用）、播放队列、拖动进度。无版权的歌自动跳过；只能试听时提示，歌词时间自动换算。
- **音质**：只显示当前歌曲实际提供的档位（标准 → 超清母带共 9 档，来自 `song/music/detail/get`）。选中的档位同时设为默认；歌曲没有该档时自动选它有的最高档，账号权益不足时服务端降级并提示。
- **歌词**：两个来源，网易云（YRC 逐字 / LRC 逐行）和 QQ 音乐（QRC 逐字，客户端解密）。都带翻译和罗马音（有就显示，可开关）。默认来源取不到时自动换另一个；播放页「更多」里可以手动切换来源、调整歌词偏移。QQ 歌词按标题、歌手、时长、版本（Live / 伴奏 / Remix…）保守匹配，拿不准就不用。
- **喜欢**：红心同步到网易云账号。
- **用户主页**：歌手和绑定的账号合在一起显示。主页有 TA 的热门作品、音乐品味（听歌排行、喜欢的音乐）、创建 / 收藏的歌单（各显示前三，可查看全部）；有发行作品的再加「全部歌曲」（热度 / 最新）和「专辑」（可搜索）。从评论区头像 / 昵称、歌单创建者、抽屉个人资料、歌手名进入。关注、私信、关注 / 粉丝列表、用户动态待开发（代码里标了 `TODO(用户主页)`）。
- **用户状态**：用户主页名字下面显示 TA 当前的状态（例如「学习中」），状态带歌时点一下播放。抽屉里的「听歌状态」入口和自己的主页都可以从官方提供的状态里选一个，可编辑的状态能自己写文字；还能看「和我状态相同的人」。接口参考 api-enhanced 的 `user/social/status*`，需要登录。
- **看图**：长按封面、头像进入看图页，可缩放，长按保存到相册。
- **列表内搜索**：歌单、我喜欢、专辑、歌手等歌曲列表都能搜索列表内的歌曲。
- **评论**：歌曲、歌单、专辑的评论区，热门 / 最新两种排序，楼中楼回复，点赞、发评论、回复、删除自己的评论。
- **最近播放同步**：登录后开始放一首歌就报给网易云，出现在官方客户端的「最近播放」；听满 30 秒（短歌听一半）再给听歌排行计数。走和官方客户端一样的日志接口（EAPI + clientlog 域名）；设置里可以关掉。
- **检查更新**：启动时查 GitHub 最新正式版，比当前版本新就弹窗，可以去下载、以后再说或跳过此版本。设置页「关于」点一下打开项目主页。
- **电脑版（Windows / macOS）**：窗口够宽时是三栏布局（左侧导航、内容区、底部常驻播放条），窄了自动退回手机布局；播放页封面和歌词左右并排。关闭窗口隐藏到托盘 / 菜单栏继续播放，托盘菜单可以切歌、退出；Windows 接入系统媒体控制（SMTC），macOS 接入「正在播放」，键盘媒体键都能用。全局快捷键：Windows 上 `Ctrl+Alt+空格 / ← / → / ↑ / ↓`，macOS 上 `⌘⌥+` 同样的键，分别是播放暂停、上一首、下一首、音量加减；窗口内按空格播放 / 暂停。Windows 用 media_kit（libmpv）播放，macOS 用系统自带的 AVPlayer。
- **复制**：长按歌词复制这一句，或进入批量选择（点选单句、长按选一段、全选，可带翻译 / 罗马音）；长按歌名 / 歌手选择复制歌名、歌手、专辑或「歌名 - 歌手」。

## 设计

- 电脑布局（窗口宽度 ≥ 840）：左侧导航栏 + 内容区（二级页面在内容区里打开）+ 底部播放条（歌曲信息、控制和进度、播放列表、音量）。
- 手机端布局：顶栏（头像 + 搜索）+ 内容 + 迷你播放条 + 底部导航；点头像从左侧滑出抽屉侧栏（个人资料、听歌排行、最近播放、动态、设置、私信）。
- 暗色、无彩界面，颜色交给封面；唯一强调色是樱花粉 `#F5A3C7`，只用在选中、喜欢、进度等功能性位置。
- 播放页：背景是封面主色的纯色渐变；第一屏是大封面、歌名/喜欢、进度、控制；往下滑是歌词预览卡片和歌手卡片。
- 全屏歌词：封面主色做底，已唱的行偏白、未唱的行压暗，当前行逐字填色，附翻译和罗马音；当前行自动滚动，手动滚动后暂停跟随 3 秒；「更多」里可调歌词偏移。

## 目录

```
lib/
  app/        应用入口、显示名与版本、服务装配（AppServices）、检查更新
  api/        网易云接口（EAPI 加解密、Cookie）
  audio/      播放内核接口 + just_audio 实现
  lyrics/     歌词解析（LRC / YRC / QRC）、QQ 歌词搜索匹配与解密、歌词来源调度
  theme/      颜色、圆角、阴影、ThemeData
  data/       模型、格式化工具
  state/      播放器、账号、本地设置
  shell/      主框架：顶栏、抽屉侧栏、迷你播放条、底部导航
  pages/      首页、搜索、歌单、登录、设置、播放页、全屏歌词、评论区
  widgets/    通用组件（封面、主色提取、歌曲行、红心、待开发标签）
```

## 检查

```bash
flutter analyze
flutter test        # 全部离线，不访问网络
```

## 致谢

- [Suxiaoqinx/Netease_url](https://github.com/Suxiaoqinx/Netease_url)（MIT）：EAPI 加密与播放地址接口的参考。
- [NeteaseCloudMusicApiEnhanced/api-enhanced](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced)（MIT）网易云API参考
- [WXRIW/Lyricify-Lyrics-Helper](https://github.com/WXRIW/Lyricify-Lyrics-Helper)（Apache-2.0）：QQ 音乐歌词接口与 QRC 解密算法。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
