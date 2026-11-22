import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api/netease_api.dart';
import '../app/app.dart';
import '../state/account_controller.dart';
import '../theme/app_theme.dart';

/// 登录：扫码、Cookie 两种方式。
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LoginPage()));

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('登录网易云账号'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '扫码'),
              Tab(text: 'Cookie'),
            ],
          ),
        ),
        body: const TabBarView(children: [_QrLogin(), _CookieLogin()]),
      ),
    );
  }
}

/// 拿到 Cookie 后统一验证、保存、提示并关闭登录页。
Future<void> _finish(BuildContext context, Map<String, String> cookies) async {
  final profile = await AccountScope.read(context).loginWithCookies(cookies);
  if (!context.mounted) return;
  AppScope.toast('已登录：${profile.nickname}');
  Navigator.of(context).pop();
}

String _message(Object e) => e is ApiException ? e.message : '$e';

// ---------------------------------------------------------------- 扫码

class _QrLogin extends StatefulWidget {
  const _QrLogin();

  @override
  State<_QrLogin> createState() => _QrLoginState();
}

class _QrLoginState extends State<_QrLogin> with AutomaticKeepAliveClientMixin {
  static const _interval = Duration(seconds: 2);

  String? _key;
  QrCheck? _state;
  String? _error;
  Timer? _poll;
  bool _checking = false;
  bool _done = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    _poll?.cancel();
    setState(() {
      _key = null;
      _state = null;
      _error = null;
    });
    try {
      final key = await AppScope.of(context).api.qrKey();
      if (!mounted) return;
      setState(() => _key = key);
      _poll = Timer.periodic(_interval, (_) => _check());
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  Future<void> _check() async {
    final key = _key;
    if (key == null || _checking || _done) return;
    _checking = true;
    try {
      final r = await AppScope.of(context).api.qrCheck(key);
      if (!mounted || key != _key) return;
      setState(() => _state = r);
      switch (r.status) {
        case QrStatus.expired:
          _poll?.cancel();
        case QrStatus.confirmed:
          _poll?.cancel();
          _done = true;
          await _finish(context, r.cookies);
        case QrStatus.waiting || QrStatus.scanned:
          break;
      }
    } catch (e) {
      // 单次查询失败（网络抖动）不打断轮询；登录验证失败则显示出来。
      if (_done && mounted) {
        setState(() {
          _done = false;
          _error = _message(e);
        });
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final key = _key;
    final status = _state?.status;
    final expired = status == QrStatus.expired;
    final hint = switch (status) {
      null || QrStatus.waiting => '打开网易云音乐 App，用「扫一扫」扫描二维码',
      QrStatus.scanned => '${_state?.nickname ?? '已扫码'}，请在手机上确认登录',
      QrStatus.confirmed => '登录中…',
      QrStatus.expired => '二维码已过期',
    };
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: Container(
            width: 220,
            height: 220,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.panel),
            ),
            child: _error != null
                ? Center(
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  )
                : key == null
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      QrImageView(data: NeteaseApi.qrContent(key), padding: EdgeInsets.zero),
                      if (expired || status == QrStatus.scanned)
                        ColoredBox(
                          color: Colors.white.withValues(alpha: 0.9),
                          child: Icon(
                            expired ? Icons.refresh_rounded : Icons.check_circle_rounded,
                            size: 56,
                            color: expired ? Colors.black54 : context.colors.accent,
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 20),
        Text(hint, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
        const SizedBox(height: 8),
        Text(
          '二维码在本机屏幕上时，可以用另一台设备扫，或截图后在网易云「扫一扫」里从相册选择。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: context.colors.textMuted, height: 1.5),
        ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('刷新二维码'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Cookie

class _CookieLogin extends StatefulWidget {
  const _CookieLogin();

  @override
  State<_CookieLogin> createState() => _CookieLoginState();
}

class _CookieLoginState extends State<_CookieLogin> with AutomaticKeepAliveClientMixin {
  final _input = TextEditingController();
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final account = AccountScope.read(context);
    try {
      final profile = await account.login(_input.text);
      if (!mounted) return;
      AppScope.toast('已登录：${profile.nickname}');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final busy = AccountScope.of(context).busy;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '在电脑浏览器登录 music.163.com，打开开发者工具，复制请求头里的 Cookie 粘贴到下面。'
          '至少需要包含 MUSIC_U。',
          style: TextStyle(color: context.colors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 8),
        Text(
          'Cookie 只保存在本机，用来以你的账号请求网易云接口。请勿分享给他人。',
          style: TextStyle(color: context.colors.textMuted, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _input,
          minLines: 4,
          maxLines: 8,
          enabled: !busy,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: 'MUSIC_U=…; __csrf=…',
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: context.colors.accent,
            foregroundColor: context.colors.onAccent,
            minimumSize: const Size.fromHeight(48),
          ),
          child: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('验证并登录'),
        ),
      ],
    );
  }
}

/// 需要登录的页面在未登录时显示的占位。
class LoginPrompt extends StatelessWidget {
  const LoginPrompt({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 48, color: context.colors.textMuted),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: context.colors.textSecondary)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => LoginPage.open(context),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.accent,
              foregroundColor: context.colors.onAccent,
            ),
            child: const Text('登录'),
          ),
        ],
      ),
    );
  }
}
