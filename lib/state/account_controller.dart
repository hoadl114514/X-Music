import 'package:flutter/widgets.dart';

import '../api/cookies.dart';
import '../api/netease_api.dart';
import '../data/models.dart';
import 'settings.dart';

/// 登录状态（只支持 Cookie 登录）、我的歌单和"喜欢"列表。
class AccountController extends ChangeNotifier {
  AccountController({required this._api, required this._settings});

  final NeteaseApi _api;
  final AppSettings _settings;

  UserProfile? _profile;
  List<Playlist> _playlists = const [];
  Set<String> _liked = {};
  bool _busy = false;

  UserProfile? get profile => _profile;
  bool get isLoggedIn => _profile != null;
  bool get busy => _busy;
  List<Playlist> get playlists => _playlists;

  /// 「我喜欢的音乐」歌单。
  Playlist? get likedPlaylist {
    for (final p in _playlists) {
      if (p.isLikedList) return p;
    }
    return null;
  }

  bool isLiked(String songId) => _liked.contains(songId);

  /// 自己创建的歌单（不含「我喜欢的音乐」），用于「收藏到歌单」。
  List<Playlist> get ownPlaylists => [
    for (final p in _playlists)
      if (!p.isLikedList && p.creatorId == _profile?.userId) p,
  ];

  /// 共建歌单：自己建的和加入的别人的，都放在音乐库的「共享歌单」里。
  List<Playlist> get sharedPlaylists => [
    for (final p in _playlists)
      if (!p.isLikedList && isShared(p)) p,
  ];

  /// 能往里加歌的歌单：自己创建的，加上加入的别人的共建歌单。
  /// 共建成员加歌和自己加歌是同一个接口，有没有权限由服务端判断。
  List<Playlist> get addablePlaylists => [
    for (final p in _playlists)
      if (!p.isLikedList && (p.creatorId == _profile?.userId || isShared(p))) p,
  ];

  /// 是否收藏了别人的歌单 [id]。
  bool isSubscribed(String id) => _playlists.any((p) => p.id == id && p.subscribed);

  /// 是自己创建的歌单。
  bool isOwn(Playlist p) => _profile != null && p.creatorId == _profile!.userId;

  /// 收藏 / 取消收藏别人的歌单，成功后刷新歌单列表。
  Future<void> setSubscribed(Playlist playlist, bool subscribed) async {
    if (!isLoggedIn) throw const ApiException('登录后才能收藏歌单', code: 301);
    await _api.setPlaylistSubscribed(playlist.id, subscribed);
    _playlists = await _api.userPlaylists(_profile!.userId);
    notifyListeners();
  }

  /// 把歌加到自己的歌单，成功后刷新歌曲数。
  Future<void> addToPlaylist(Playlist playlist, Song song) async {
    if (!isLoggedIn) throw const ApiException('登录后才能收藏到歌单', code: 301);
    await _api.addToPlaylist(playlist.id, [song.id]);
    _playlists = await _api.userPlaylists(_profile!.userId);
    notifyListeners();
  }

  /// 新建歌单，成功后刷新歌单列表并返回新歌单（找不到时为 null）。
  Future<Playlist?> createPlaylist(String name, {bool private = false, bool shared = false}) async {
    if (!isLoggedIn) throw const ApiException('登录后才能新建歌单', code: 301);
    final created = await _api.createPlaylist(name, private: private, shared: shared);
    if (shared && created != null) _settings.addSharedPlaylist(created.id);
    await _reloadPlaylists();
    return _find(created?.id) ?? created;
  }

  /// 改自己歌单的名称、简介、封面（[cover] 是 JPEG / PNG 图片）。只提交有变化的部分。
  Future<void> updatePlaylist(
    Playlist playlist, {
    String? name,
    String? description,
    List<int>? cover,
  }) async {
    if (!isLoggedIn) throw const ApiException('登录后才能编辑歌单', code: 301);
    try {
      if (name != null && name != playlist.name) await _api.renamePlaylist(playlist.id, name);
      if (description != null && description != (playlist.description ?? '')) {
        await _api.setPlaylistDescription(playlist.id, description);
      }
      if (cover != null) await _api.setPlaylistCover(playlist.id, cover);
    } finally {
      // 部分成功时也要刷新，界面和服务端保持一致。
      await _reloadPlaylists().catchError((Object _) {});
    }
  }

  /// 删除自己的歌单，成功后从列表里去掉。
  Future<void> deletePlaylist(Playlist playlist) async {
    if (!isLoggedIn) throw const ApiException('登录后才能删除歌单', code: 301);
    await _api.deletePlaylist(playlist.id);
    _playlists = [
      for (final p in _playlists)
        if (p.id != playlist.id) p,
    ];
    notifyListeners();
  }

  /// 列表里 id 为 [id] 的歌单（最新信息），没有为 null。
  Playlist? _find(String? id) =>
      id == null ? null : _playlists.where((p) => p.id == id).firstOrNull;

  /// 按 id 取最新的歌单信息，列表里没有时返回 [fallback]。
  Playlist latest(Playlist fallback) => _find(fallback.id) ?? fallback;

  /// 重新拉取歌单列表（音乐库切回来、下拉刷新时用）。
  Future<void> reloadPlaylists() => _reloadPlaylists();

  Future<void> _reloadPlaylists() async {
    final p = _profile;
    if (p == null) return;
    _playlists = await _api.userPlaylists(p.userId);
    notifyListeners();
  }

  /// 从自己的歌单（含「我喜欢的音乐」）里删歌，成功后刷新歌曲数。
  Future<void> removeFromPlaylist(Playlist playlist, List<Song> songs) async {
    if (!isLoggedIn) throw const ApiException('登录后才能编辑歌单', code: 301);
    if (songs.isEmpty) return;
    await _api.removeFromPlaylist(playlist.id, [for (final s in songs) s.id]);
    if (playlist.isLikedList) {
      _liked.removeAll([for (final s in songs) s.id]);
      notifyListeners();
    }
    await _reloadPlaylists().catchError((Object _) {});
  }

  /// 能删歌的歌单：自己创建的和「我喜欢的音乐」。
  /// 是不是共建歌单：接口标了，或者是在本机建的共建歌单。
  bool isShared(Playlist p) => p.shared || _settings.sharedPlaylistIds.contains(p.id);

  bool canEditTracks(Playlist p) => isOwn(p) || likedPlaylist?.id == p.id;

  /// 启动时用保存的 Cookie 恢复登录。网络失败时保留 Cookie，下次再试。
  Future<void> restore() async {
    final saved = parseCookie(_settings.cookie);
    if (!saved.containsKey('MUSIC_U')) return;
    _api.cookies = saved;
    try {
      await _refresh();
    } catch (_) {
      // 离线等情况：不清 Cookie，界面显示未登录。
    }
  }

  /// 用一段 Cookie 文本登录，成功返回账号，失败抛 [ApiException]。
  Future<UserProfile> login(String cookieText) => loginWithCookies(parseCookie(cookieText));

  /// 用 Cookie 键值登录（扫码登录拿到的 Cookie 也走这里）：先验证账号，成功才保存。
  Future<UserProfile> loginWithCookies(Map<String, String> cookies) async {
    if (!cookies.containsKey('MUSIC_U')) {
      throw const ApiException('Cookie 里没有 MUSIC_U，请确认复制完整');
    }
    final previous = _api.cookies;
    _api.cookies = cookies;
    _setBusy(true);
    try {
      final profile = await _api.account();
      if (profile == null) throw const ApiException('Cookie 无效或已过期');
      _settings.cookie = encodeCookie(cookies);
      await _refresh(profile: profile);
      return profile;
    } catch (e) {
      _api.cookies = previous;
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  void logout() {
    _api.cookies = const {};
    _settings.cookie = '';
    _profile = null;
    _playlists = const [];
    _liked = {};
    notifyListeners();
  }

  /// 重新拉取歌单和喜欢列表。
  Future<void> refresh() => _refresh();

  Future<void> _refresh({UserProfile? profile}) async {
    final p = profile ?? await _api.account();
    _profile = p;
    if (p == null) {
      _playlists = const [];
      _liked = {};
      notifyListeners();
      return;
    }
    notifyListeners();
    // 喜欢列表取不到不影响歌单显示，红心按未喜欢处理。
    final liked = _api.likedSongIds(p.userId).catchError((Object _) => <String>{});
    _playlists = await _api.userPlaylists(p.userId);
    _liked = await liked;
    notifyListeners();
  }

  /// 切换喜欢。先改界面，接口失败再改回来并抛出错误。
  Future<void> toggleLike(String songId) async {
    if (!isLoggedIn) throw const ApiException('登录后才能收藏歌曲', code: 301);
    final liked = !_liked.contains(songId);
    liked ? _liked.add(songId) : _liked.remove(songId);
    notifyListeners();
    try {
      await _api.setLiked(songId, liked);
    } catch (_) {
      liked ? _liked.remove(songId) : _liked.add(songId);
      notifyListeners();
      rethrow;
    }
  }

  void _setBusy(bool v) {
    _busy = v;
    notifyListeners();
  }
}

class AccountScope extends InheritedNotifier<AccountController> {
  const AccountScope({super.key, required AccountController controller, required super.child})
    : super(notifier: controller);

  static AccountController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountScope>()!.notifier!;

  static AccountController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AccountScope>()!.notifier!;
}
