import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../api/netease_api.dart';
import '../data/models.dart';
import 'account_controller.dart';
import 'player_controller.dart';

/// 一起听。房主和加入方用同一套逻辑，谁操作都会同步给对方：
///
/// - 本地切歌、播放 / 暂停、拖进度、换列表时上报指令（带递增的 clientSeq），并定时发心跳；
/// - 每 [pollEvery] 拉一次房间快照（`sync/playlist/get`），里面有房间的歌单和最后一条播放指令。
///   指令不是自己发的，就照着换列表、切歌、跳进度、播放 / 暂停。
///   进度按「指令里的进度 + 服务器收到指令后过去的时间」推算，见 [ListenTogetherCommand.positionAt]。
///
/// 做法参考开源项目 Enji（together.rs）、MeloX-Android 和 YTPlayer 的快照轮询实现。
/// 好友用官方客户端也能加入：官方客户端走长连接，我们走轮询，两边读写的是同一个房间状态。
class ListenTogether extends ChangeNotifier {
  ListenTogether({required this.api, required this.player, required this.account});

  final NeteaseApi api;
  final PlayerController player;
  final AccountController account;

  /// 拉房间快照的间隔。
  static const pollEvery = Duration(seconds: 2);

  /// 心跳间隔。
  static const heartbeatEvery = Duration(seconds: 20);

  /// 刷新房间成员的间隔。
  static const membersEvery = Duration(seconds: 10);

  /// 进度差超过这么多才跳，免得每次轮询都抖一下。
  static const seekThreshold = Duration(milliseconds: 1500);

  /// 照着房间指令操作播放器后，这段时间内播放器的变化不再上报，避免来回反弹。
  static const _echoWindow = Duration(seconds: 2);

  String? _roomId;
  String? _inviterId;
  bool _host = false;
  bool _busy = false;
  List<SocialUser> _users = const [];
  Timer? _poll;
  Timer? _heartbeat;
  Timer? _members;
  bool _polling = false;
  int _failures = 0;

  /// 进房间的时间和连续几次查到「不在房间」。刚进房间时状态接口可能还没更新，
  /// 所以过了 [_grace] 且连续两次不在房间才认为房间结束了。
  DateTime _enteredAt = DateTime.now();
  int _absent = 0;
  static const _grace = Duration(seconds: 15);

  /// 自己发过的指令序号（最近 64 条），用来认出快照里哪条是自己的。
  final _sent = Queue<int>();
  int _seq = 0;
  int _version = 0;

  /// 最近处理过的远端指令，避免重复应用。
  (int, int, int)? _seen;
  ListenTogetherCommand? _remote;
  DateTime _remoteAt = DateTime.now();
  DateTime _suppressUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// 上次上报 / 应用时的状态，用来判断这次播放器变化要不要上报。
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

  /// 连续几次拉不到房间状态：页面上提示连接不稳。
  bool get struggling => _failures > 1;

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
    await _report('GOTO');
  });

  /// 用邀请链接加入别人的房间：拉一次快照，跟上房间正在放的歌和进度。
  Future<void> join(String link) => _guard(() async {
    _requireLogin();
    final parsed = parseLink(link);
    if (parsed == null) throw const ApiException('这不是一起听的邀请链接');
    if (!await api.listenTogetherCheck(parsed.roomId)) {
      throw const ApiException('房间已关闭或人数已满');
    }
    await api.listenTogetherAccept(parsed.roomId, parsed.inviterId);
    _enter(parsed.roomId, host: false, inviterId: parsed.inviterId);
    await _pull();
  });

  /// 退出房间。任一方结束，整个房间就结束了。
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
    _sent.clear();
    _seen = null;
    _remote = null;
    _failures = 0;
    _absent = 0;
    _enteredAt = DateTime.now();
    _lastSongId = player.current?.id;
    _lastPlaying = player.isPlaying;
    _lastQueue = const [];
    _users = [?_me];
    player.addListener(_onPlayer);
    _poll = Timer.periodic(pollEvery, (_) => _pull());
    _heartbeat = Timer.periodic(heartbeatEvery, (_) => _sendHeartbeat());
    _members = Timer.periodic(membersEvery, (_) => _refreshMembers());
    unawaited(_refreshMembers());
    notifyListeners();
  }

  void _exit() {
    player.removeListener(_onPlayer);
    _poll?.cancel();
    _heartbeat?.cancel();
    _members?.cancel();
    _poll = _heartbeat = _members = null;
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

  // ---- 本地 → 房间 ----

  /// 播放器变了就上报：换列表报列表，换歌报 GOTO，播放 / 暂停报 PLAY / PAUSE，拖进度报 SEEK。
  /// 刚照着房间指令操作过的变化不报。
  void _onPlayer() {
    if (_roomId == null) return;
    final song = player.current?.id;
    final playing = player.isPlaying;
    if (DateTime.now().isBefore(_suppressUntil) || player.isLoading) {
      _remember();
      return;
    }
    unawaited(_reportQueue());
    if (song != _lastSongId) {
      unawaited(_report('GOTO'));
    } else if (playing != _lastPlaying) {
      unawaited(_report(playing ? 'PLAY' : 'PAUSE'));
    } else if (_jumped()) {
      unawaited(_report('SEEK'));
    }
    _remember();
  }

  void _remember() {
    _lastSongId = player.current?.id;
    _lastPlaying = player.isPlaying;
    _lastPosition = player.position;
    _lastPositionAt = DateTime.now();
  }

  /// 进度和按时间推算的位置差了 3 秒以上，算拖了进度条。
  bool _jumped() {
    final elapsed = (_lastPlaying ?? false)
        ? DateTime.now().difference(_lastPositionAt)
        : Duration.zero;
    return (player.position - (_lastPosition + elapsed)).abs() > const Duration(seconds: 3);
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

  Future<void> _report(String command) async {
    final id = _roomId;
    final song = player.current;
    if (id == null || song == null) return;
    final former = _lastSongId;
    final seq = ++_seq;
    _sent.add(seq);
    while (_sent.length > 64) {
      _sent.removeFirst();
    }
    try {
      await api.listenTogetherCommand(
        id,
        command: command,
        songId: song.id,
        playing: player.isPlaying,
        progress: player.position,
        clientSeq: seq,
        formerSongId: command == 'GOTO' && former != null && former != song.id ? former : '-1',
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

  // ---- 房间 → 本地 ----

  /// 拉一次房间快照，有别人的新指令就照着做。
  Future<void> _pull() async {
    final id = _roomId;
    if (id == null || _polling) return;
    _polling = true;
    try {
      final snap = await api.listenTogetherSnapshot(id);
      if (_roomId != id) return;
      final wasStruggling = struggling;
      _failures = 0;
      if (wasStruggling) notifyListeners();
      await _apply(snap);
    } catch (_) {
      _failures++;
      if (_failures == 2) notifyListeners();
    } finally {
      _polling = false;
    }
  }

  bool _isOurs(ListenTogetherCommand c) =>
      c.userId == account.profile?.userId && _sent.contains(c.clientSeq);

  Future<void> _apply(ListenTogetherSnapshot snap) async {
    final c = snap.command;
    if (c != null && c.clientSeq > _seq) _seq = c.clientSeq;
    final ids = snap.songIds;
    final listChanged = ids.isNotEmpty && !listEquals(ids, _lastQueue);
    final fresh = c != null && !_isOurs(c) && _seen != (c.serverTime, c.userId, c.clientSeq);
    if (c != null) _seen = (c.serverTime, c.userId, c.clientSeq);
    if (fresh) {
      _remote = c;
      _remoteAt = DateTime.now();
    }
    // 房间的歌单换了（别人换的）：换成房间的歌单。
    if (listChanged) {
      _lastQueue = ids;
      final queueIds = [for (final s in player.queue) s.id];
      if (!listEquals(ids, queueIds)) {
        await _replaceQueue(ids, songId: (fresh ? c : _remote)?.songId);
      }
    }
    final remote = _remote;
    if (remote == null) return;
    // 别人的新指令照着做；旧指令只在进度偏得太多时校正一下。
    if (fresh || listChanged) {
      await _follow(remote);
    } else if (remote.playing && player.isPlaying && player.current?.id == remote.songId) {
      await _seekIfOff(remote);
    }
  }

  Future<void> _replaceQueue(List<String> ids, {String? songId}) async {
    final known = {for (final s in player.queue) s.id: s};
    final missing = [
      for (final id in ids)
        if (!known.containsKey(id)) id,
    ];
    if (missing.isNotEmpty) {
      for (final s in await api.songDetails(missing)) {
        known[s.id] = s;
      }
    }
    final songs = [for (final id in ids) ?known[id]];
    if (songs.isEmpty) return;
    final start = songId == null
        ? 0
        : songs.indexWhere((s) => s.id == songId).clamp(0, songs.length - 1);
    _suppress();
    await player.playQueue(songs, start: start, title: '一起听');
  }

  /// 照着房间指令：切到那首歌，跳到推算的进度，播放或暂停。
  Future<void> _follow(ListenTogetherCommand c) async {
    _suppress();
    if (player.current?.id != c.songId) {
      final i = player.queue.indexWhere((s) => s.id == c.songId);
      if (i >= 0) {
        await player.jumpTo(i);
      } else {
        final songs = await api.songDetails([c.songId]);
        if (songs.isEmpty) return;
        await player.playNext(songs.first);
        final j = player.queue.indexWhere((s) => s.id == c.songId);
        if (j >= 0) await player.jumpTo(j);
      }
    }
    await _seekIfOff(c);
    if (c.playing && !player.isPlaying) {
      await player.play();
    } else if (!c.playing && player.isPlaying) {
      await player.pause();
    }
    _suppress();
    _remember();
  }

  Future<void> _seekIfOff(ListenTogetherCommand c) async {
    final target = c.positionAt(DateTime.now(), receivedAt: _remoteAt);
    if ((player.position - target).abs() > seekThreshold) {
      _suppress();
      await player.seek(target);
    }
  }

  void _suppress() => _suppressUntil = DateTime.now().add(_echoWindow);

  /// 刷新成员；房间确实没了就退出。
  Future<void> _refreshMembers() async {
    final id = _roomId;
    if (id == null) return;
    try {
      final status = await api.listenTogetherStatus();
      if (_roomId != id) return;
      if (!status.inRoom || (status.roomId != null && status.roomId != id)) {
        _absent++;
        if (_absent >= 2 && DateTime.now().difference(_enteredAt) > _grace) _exit();
        return;
      }
      _absent = 0;
      if (status.users.isNotEmpty) _users = status.users;
      notifyListeners();
    } catch (_) {
      // 网络抖动时保留原状态，下次再刷。
    }
  }

  @override
  void dispose() {
    player.removeListener(_onPlayer);
    _poll?.cancel();
    _heartbeat?.cancel();
    _members?.cancel();
    super.dispose();
  }
}
