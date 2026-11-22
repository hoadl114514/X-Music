import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/netease_api.dart';
import '../data/models.dart';
import 'account_controller.dart';
import 'player_controller.dart';

/// 一起听。
///
/// - 自己开房间（房主）：把当前播放列表、切歌、播放 / 暂停、拖进度上报给房间，并定时发心跳。
///   好友用官方客户端打开邀请链接加入，就会跟着房主的进度听。
/// - 加入别人的房间：接受邀请后取房间的播放列表开始播放，之后定时刷新列表和成员。
///   公开接口拿不到房主的实时进度，所以加入方只能同步歌单，不能同步到秒。
class ListenTogether extends ChangeNotifier {
  ListenTogether({required this.api, required this.player, required this.account});

  final NeteaseApi api;
  final PlayerController player;
  final AccountController account;

  /// 心跳间隔。
  static const heartbeatEvery = Duration(seconds: 15);

  /// 刷新房间成员（和加入方刷新歌单）的间隔。
  static const refreshEvery = Duration(seconds: 10);

  String? _roomId;
  String? _inviterId;
  bool _host = false;
  bool _busy = false;
  List<SocialUser> _users = const [];
  Timer? _heartbeat;
  Timer? _refresh;
  int _seq = 0;
  int _version = 0;

  /// 上次上报时的状态，用来判断这次播放器变化要不要上报。
  String? _lastSongId;
  bool? _lastPlaying;
  List<String> _lastQueue = const [];
  Duration _lastPosition = Duration.zero;
  DateTime _lastPositionAt = DateTime.now();

  String? get roomId => _roomId;
  bool get active => _roomId != null;

  /// 自己是不是房主。
  bool get isHost => _host;
  bool get busy => _busy;

  /// 房间里的人（包括自己）。
  List<SocialUser> get users => _users;

  /// 邀请链接：好友用网易云音乐打开就能加入。格式见 NeteaseCloudMusicApi issue #1676。
  String? get inviteLink {
    final room = _roomId;
    if (room == null) return null;
    final inviter = _inviterId ?? '${account.profile?.userId ?? 0}';
    final song = player.current?.id ?? '';
    return 'https://st.music.163.com/listen-together/share/?songId=$song&roomId=$room&inviterId=$inviter';
  }

  /// 从邀请链接里取房间号和邀请人；不是一起听链接时返回 null。
  static ({String roomId, String inviterId})? parseLink(String text) {
    final match = RegExp(r'https?://\S+').firstMatch(text.trim());
    final uri = Uri.tryParse(match?.group(0) ?? text.trim());
    final room = uri?.queryParameters['roomId'];
    final inviter = uri?.queryParameters['inviterId'];
    if (room == null || room.isEmpty || inviter == null || inviter.isEmpty) return null;
    return (roomId: room, inviterId: inviter);
  }

  /// 开一个房间，自己当房主。当前有在放的歌就把播放列表同步进去。
  Future<void> createRoom() => _guard(() async {
    _requireLogin();
    final id = await api.listenTogetherCreate();
    await api.listenTogetherCheck(id);
    _enter(id, host: true, inviterId: '${account.profile!.userId}');
    await _reportQueue(force: true);
    await _reportPlayback(command: 'GOTO');
  });

  /// 用邀请链接加入别人的房间，取房间的播放列表开始放。
  Future<void> join(String link) => _guard(() async {
    _requireLogin();
    final parsed = parseLink(link);
    if (parsed == null) throw const ApiException('这不是一起听的邀请链接');
    if (!await api.listenTogetherCheck(parsed.roomId)) {
      throw const ApiException('房间已关闭或人数已满');
    }
    await api.listenTogetherAccept(parsed.roomId, parsed.inviterId);
    _enter(parsed.roomId, host: false, inviterId: parsed.inviterId);
    await _pullQueue(play: true);
  });

  /// 退出房间。房主退出会结束整个房间。
  Future<void> leave() => _guard(() async {
    final id = _roomId;
    _exit();
    if (id != null) await api.listenTogetherEnd(id);
  });

  void _requireLogin() {
    if (!account.isLoggedIn) throw const ApiException('登录后才能一起听', code: 301);
  }

  Future<void> _guard(Future<void> Function() body) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      await body();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _enter(String id, {required bool host, required String inviterId}) {
    _roomId = id;
    _host = host;
    _inviterId = inviterId;
    _seq = 0;
    _version = 0;
    _lastSongId = null;
    _lastPlaying = null;
    _lastQueue = const [];
    _users = [?_me];
    if (host) {
      player.addListener(_onPlayer);
      _heartbeat = Timer.periodic(heartbeatEvery, (_) => _sendHeartbeat());
    }
    _refresh = Timer.periodic(refreshEvery, (_) => _refreshRoom());
    unawaited(_refreshRoom());
    notifyListeners();
  }

  void _exit() {
    player.removeListener(_onPlayer);
    _heartbeat?.cancel();
    _refresh?.cancel();
    _heartbeat = _refresh = null;
    _roomId = null;
    _inviterId = null;
    _host = false;
    _users = const [];
    notifyListeners();
  }

  SocialUser? get _me => switch (account.profile) {
    final p? => SocialUser(userId: p.userId, nickname: p.nickname, avatarUrl: p.avatarUrl),
    null => null,
  };

  /// 房主：播放器变了就上报。换了列表报列表，换了歌报 GOTO，播放 / 暂停报 PLAY / PAUSE，
  /// 进度跳变（拖进度条）报 SEEK。
  void _onPlayer() {
    if (!_host || _roomId == null) return;
    unawaited(_reportQueue());
    final song = player.current?.id;
    final playing = player.isPlaying;
    if (song != _lastSongId) {
      unawaited(_reportPlayback(command: 'GOTO'));
    } else if (playing != _lastPlaying) {
      unawaited(_reportPlayback(command: playing ? 'PLAY' : 'PAUSE'));
    } else if (_jumped()) {
      unawaited(_reportPlayback(command: 'SEEK'));
    }
    _lastPosition = player.position;
    _lastPositionAt = DateTime.now();
  }

  /// 进度和按时间推算的位置差了 3 秒以上，算拖了进度条。
  bool _jumped() {
    final elapsed = player.isPlaying ? DateTime.now().difference(_lastPositionAt) : Duration.zero;
    final expected = _lastPosition + elapsed;
    return (player.position - expected).abs() > const Duration(seconds: 3);
  }

  Future<void> _reportQueue({bool force = false}) async {
    final id = _roomId;
    final me = account.profile?.userId;
    if (id == null || me == null) return;
    final ids = [for (final s in player.queue) s.id];
    if (ids.isEmpty || (!force && listEquals(ids, _lastQueue))) return;
    _lastQueue = ids;
    try {
      await api.listenTogetherSyncList(id, userId: me, version: ++_version, songIds: ids);
    } catch (_) {
      // 上报失败不打断播放，下次变化再报。
    }
  }

  Future<void> _reportPlayback({required String command}) async {
    final id = _roomId;
    final song = player.current;
    if (id == null || song == null) return;
    final former = _lastSongId;
    _lastSongId = song.id;
    _lastPlaying = player.isPlaying;
    try {
      await api.listenTogetherCommand(
        id,
        command: command,
        songId: song.id,
        playing: player.isPlaying,
        progress: player.position,
        clientSeq: ++_seq,
        formerSongId: command == 'GOTO' && former != null ? former : '-1',
      );
      if (command == 'GOTO') await _sendHeartbeat();
    } catch (_) {
      // 同上。
    }
  }

  Future<void> _sendHeartbeat() async {
    final id = _roomId;
    final song = player.current;
    if (id == null || song == null) return;
    try {
      await api.listenTogetherHeartbeat(
        id,
        songId: song.id,
        playing: player.isPlaying,
        progress: player.position,
      );
    } catch (_) {}
  }

  /// 刷新成员；加入方顺便看房间的歌单有没有换。房间没了就退出。
  Future<void> _refreshRoom() async {
    final id = _roomId;
    if (id == null) return;
    try {
      final status = await api.listenTogetherStatus();
      if (_roomId != id) return;
      if (!status.inRoom || (status.roomId != null && status.roomId != id)) {
        _exit();
        return;
      }
      if (status.users.isNotEmpty) _users = status.users;
      notifyListeners();
      if (!_host) await _pullQueue(play: false);
    } catch (_) {
      // 网络抖动时保留原状态，下次再刷。
    }
  }

  /// 加入方：取房间的歌单。[play] 为 true 时立即从第一首开始放；否则只在歌单变了时替换。
  Future<void> _pullQueue({required bool play}) async {
    final id = _roomId;
    if (id == null) return;
    final ids = await api.listenTogetherPlaylist(id);
    if (ids.isEmpty || (!play && listEquals(ids, _lastQueue))) return;
    _lastQueue = ids;
    final songs = await api.songDetails(ids);
    if (songs.isEmpty || _roomId != id) return;
    final current = player.current?.id;
    final start = play ? 0 : songs.indexWhere((s) => s.id == current).clamp(0, songs.length - 1);
    await player.playQueue(songs, start: start, title: '一起听');
  }

  @override
  void dispose() {
    player.removeListener(_onPlayer);
    _heartbeat?.cancel();
    _refresh?.cancel();
    super.dispose();
  }
}
