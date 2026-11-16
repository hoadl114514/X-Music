import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../api/netease_api.dart';
import '../audio/audio_cache.dart';
import '../audio/audio_engine.dart';
import '../data/models.dart';
import '../data/retry.dart';
import '../lyrics/lyric_service.dart';
import '../widgets/cover_palette.dart';
import 'settings.dart';

/// 播放器需要的数据来源。测试里换成假的实现。
abstract class PlaybackBackend {
  Future<List<QualityInfo>> qualities(String songId);
  Future<SongUrl?> songUrl(String songId, AudioQuality quality);
  Future<Lyrics> lyrics(Song song, LyricSource source, {required bool fallback});

  /// 开始放一首歌：同步到网易云的「最近播放」。未登录时什么都不做。
  Future<void> startPlay(Song song, {String? sourceId});

  /// 听够了一首歌：给网易云的听歌排行计数。未登录时什么都不做。
  Future<void> scrobble(Song song, {required Duration listened, String? sourceId});
}

class NeteaseBackend implements PlaybackBackend {
  NeteaseBackend(this._api, this._lyrics);

  final NeteaseApi _api;
  final LyricService _lyrics;

  @override
  Future<List<QualityInfo>> qualities(String songId) => _api.qualities(songId);

  @override
  Future<SongUrl?> songUrl(String songId, AudioQuality quality) => _api.songUrl(songId, quality);

  @override
  Future<Lyrics> lyrics(Song song, LyricSource source, {required bool fallback}) =>
      _lyrics.fetch(song, source, fallback: fallback);

  @override
  Future<void> startPlay(Song song, {String? sourceId}) async {
    if (!_api.hasLoginCookie) return;
    await _api.startPlay(song.id, sourceId: sourceId);
  }

  @override
  Future<void> scrobble(Song song, {required Duration listened, String? sourceId}) async {
    if (!_api.hasLoginCookie) return;
    await _api.scrobble(song.id, seconds: listened.inSeconds, sourceId: sourceId);
  }
}

enum Repeat { list, one }

/// 播放页上合成一个按钮的播放模式。私人 FM 下只有 [list]（显示为「∞」）和 [one]。
enum PlayMode {
  list('列表循环'),
  shuffle('随机播放'),
  one('单曲循环');

  const PlayMode(this.label);

  final String label;
}

/// 播放器状态：队列、进度、音质、歌词。
///
/// 每次切歌递增 [_token]；异步结果回来时 token 已变说明用户又切了歌，直接丢弃。
class PlayerController extends ChangeNotifier {
  PlayerController({
    required this._engine,
    required this._backend,
    required this._settings,
    this.cache,
    this.retryDelays = defaultRetryDelays,
  }) {
    _applyMode(_savedMode);
    _subs = [
      _engine.completed.listen((_) => _onCompleted()),
      _engine.errors.listen(_onEngineError),
    ];
  }

  /// 听歌缓存。为 null 时不缓存（测试）。
  final AudioCache? cache;

  /// 取播放地址、加载音频失败时的重试间隔，重试次数就是它的长度。
  final List<Duration> retryDelays;

  static const _tick = Duration(milliseconds: 50);

  final AudioEngine _engine;
  final PlaybackBackend _backend;
  final AppSettings _settings;
  late final List<StreamSubscription<Object?>> _subs;
  final _notices = StreamController<String>.broadcast();
  final _random = Random();

  List<Song> _queue = const [];
  String _queueTitle = '';

  /// 队列来源的歌单 / 专辑 id，上报播放时带上。
  String? _sourceId;

  /// 当前这首实际听了多久（拖动进度不算），换歌时用来判断要不要上报。
  Duration _listened = Duration.zero;

  /// 已经报过「开始播放」的那首（每次换到一首歌只报一次）。
  int _startReportedToken = -1;
  int _index = -1;
  int _token = 0;

  /// 每换到一首歌（或单曲循环重放）递增，用来判断「开始播放」是否已上报。
  int _songToken = 0;

  Duration _position = Duration.zero;
  bool _playing = false;
  bool _loading = false;

  /// 加载完成后是否自动播放。
  bool _wantPlay = false;

  /// 播放内核里装的是不是当前这首。加载失败时内核里可能还留着上一首，
  /// 这时点播放要重新加载，不能直接 play（否则会放出上一首）。
  bool _ready = false;

  /// 当前这首播放中途出错后已经自动重试了几次。换歌时清零。
  int _errorRetries = 0;
  Timer? _retryTimer;
  Duration _lyricOffset = Duration.zero;
  double _volume = 1;
  bool _shuffle = false;
  Repeat _repeat = Repeat.list;
  final List<int> _history = [];
  int _failStreak = 0;

  List<QualityInfo> _qualities = const [];
  AudioQuality? _quality;
  ({Duration start, Duration end})? _trial;

  Lyrics _lyrics = Lyrics.empty;
  bool _lyricsLoading = false;
  List<Color>? _coverPalette;

  Timer? _timer;

  /// 播放中每 50ms 一次的进度推进。[notifyListeners] 不包含它，见 [ticks]。
  final _ticks = _Ticks();

  /// 播放进度每次推进时通知（约 50ms 一次）。其他状态变化走 [addListener]。
  /// 要显示实时进度的 widget 用 [PlayerScope.ticking]。
  Listenable get ticks => _ticks;

  /// 私人 FM 这类"无尽队列"：放到最后一首时调用它取下一批追加到队列。
  Future<List<Song>> Function()? _extend;

  Timer? _sleepTimer;
  DateTime? _sleepAt;

  /// 给用户看的提示（切歌失败、试听、音质降级等），由界面弹 SnackBar。
  Stream<String> get notices => _notices.stream;

  /// 从界面以外的地方（例如通知栏按钮）给用户弹一条提示。
  void notice(String message) => _notices.add(message);

  Song? get current => _index >= 0 && _index < _queue.length ? _queue[_index] : null;

  /// 当前歌曲。只在确定有歌时使用（播放页、播放条）。
  Song get song => current!;
  List<Song> get queue => _queue;

  /// 随机模式下预先选好的下一首（迷你播放条滑动时要提前显示它）。
  int? _shuffleNext;

  /// 按「下一首」会放的歌；私人 FM 放到最后一首（下一批还没取到）时为 null。
  Song? get peekNext {
    final len = _queue.length;
    if (len == 0 || _index < 0) return null;
    if (_upNext case final id?) {
      final i = _queue.indexWhere((s) => s.id == id);
      if (i >= 0 && i != _index) return _queue[i];
    }
    if (isRadio && _index == len - 1) return null;
    if (_shuffle && len > 1) return _queue[_shuffleNext ??= _pickShuffle()];
    return _queue[(_index + 1) % len];
  }

  /// 按「上一首」（不回到开头时）会放的歌；没有上一首时为 null。
  Song? get peekPrevious {
    final len = _queue.length;
    if (len <= 1 || _index < 0) return null;
    if (_history.isNotEmpty && (_shuffle || isRadio)) {
      final i = _history.last;
      if (i >= 0 && i < len && i != _index) return _queue[i];
    }
    if (isRadio && _index == 0) return null;
    return _queue[(_index - 1 + len) % len];
  }

  int _pickShuffle() {
    var i = _index;
    while (i == _index) {
      i = _random.nextInt(_queue.length);
    }
    return i;
  }

  int get index => _index;

  /// 队列来源，例如歌单名、"搜索：xxx"。
  String get queueTitle => _queueTitle;
  Duration get position => _position;

  /// 正在播放，或正在加载且加载完会自动播放。用于播放 / 暂停按钮。
  bool get isPlaying => _playing || (_loading && _wantPlay);

  /// 正在取播放地址或缓冲。
  bool get isLoading => _loading;
  double get volume => _volume;
  bool get shuffle => _shuffle;
  Repeat get repeat => _repeat;

  /// 这首歌提供的音质（从低到高）。取不到时为空。
  List<QualityInfo> get qualities => _qualities;

  /// 实际在放的音质。
  AudioQuality? get quality => _quality;

  /// 非 null 表示只拿到了试听片段。
  ({Duration start, Duration end})? get trial => _trial;

  /// 正在放私人 FM（无尽队列）。
  bool get isRadio => _extend != null;

  /// 定时关闭的时间点；没开时为 null。
  DateTime? get sleepAt => _sleepAt;

  /// 当前封面的主色（从图片里取，取到之前用占位色）。
  List<Color> get palette => _coverPalette ?? current?.palette ?? const [Color(0xFF333333)];

  Lyrics get lyrics => _lyrics;
  bool get lyricsLoading => _lyricsLoading;

  /// 歌词时间轴偏移。正值表示歌词提前。
  Duration get lyricOffset => _lyricOffset;

  /// 进度条用的总时长：试听时是片段长度。
  Duration get duration {
    if (_trial case final t?) return t.end - t.start;
    final d = current?.duration ?? Duration.zero;
    return d > Duration.zero ? d : (_engine.duration ?? Duration.zero);
  }

  double get progress {
    final total = duration.inMicroseconds;
    return total == 0 ? 0 : (_position.inMicroseconds / total).clamp(0.0, 1.0);
  }

  /// 用于歌词对齐的时间点：叠加偏移；试听片段换算回整首歌的时间。
  Duration get lyricPosition => _position + (_trial?.start ?? Duration.zero) + _lyricOffset;

  /// 当前所在歌词行；还没到第一行时返回 -1。
  int get activeLyricIndex {
    final lines = _lyrics.lines;
    final p = lyricPosition;
    var lo = 0, hi = lines.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].start <= p) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  // ---------------------------------------------------------------- 队列

  /// 替换队列并从 [start] 开始播放。[sourceId] 是来源歌单 / 专辑的 id。
  Future<void> playQueue(List<Song> songs, {int start = 0, String title = '', String? sourceId}) =>
      _replaceQueue(songs, start: start, title: title, sourceId: sourceId);

  /// 换队列。[extend] 不为 null 时是无尽队列（私人 FM）。
  Future<void> _replaceQueue(
    List<Song> songs, {
    int start = 0,
    String title = '',
    String? sourceId,
    Future<List<Song>> Function()? extend,
  }) {
    if (songs.isEmpty) return Future.value();
    _reportListened();
    // 私人 FM 期间关掉了随机，换回普通队列时恢复上次选的模式。
    if (isRadio && extend == null) _applyMode(_savedMode);
    _extend = extend;
    _extendFuture = null;
    _radioSeen
      ..clear()
      ..addAll([
        if (extend != null)
          for (final s in songs) s.id,
      ]);
    if (extend != null) _shuffle = false;
    _queue = List.unmodifiable(songs);
    _shuffleNext = null;
    _upNext = null;
    _queueTitle = title;
    _sourceId = sourceId;
    _history.clear();
    _failStreak = 0;
    _index = -1; // 新队列同一位置可能是另一首歌，让 _load 视为换歌。
    return _load(start.clamp(0, songs.length - 1));
  }

  /// 播放一个无尽队列（私人 FM）：先取第一批，放到最后一首时再用 [fetch] 取下一批。
  /// 随机播放对它无意义，期间关闭。
  Future<void> playRadio(Future<List<Song>> Function() fetch, {required String title}) async {
    final first = await fetch();
    if (first.isEmpty) {
      _notices.add('$title 暂时没有可播放的歌曲');
      return;
    }
    // 先标成无尽队列再开始放：第一首加载失败自动跳下一首时，也要按私人 FM 的规则走，
    // 不能当成普通队列绕回第一首。
    await _replaceQueue(first, title: title, extend: fetch);
  }

  /// 从队列里去掉当前这首并跳到下一首（私人 FM 的「不喜欢」）。
  Future<void> skipAndRemoveCurrent() async {
    if (current == null) return;
    final i = _index;
    if (i == _queue.length - 1) await _extendQueue();
    if (_queue.length <= 1) return;
    _reportListened();
    _queue = List.unmodifiable([..._queue]..removeAt(i));
    _shuffleNext = null;
    _index = -1; // 让 _load 视为换歌。
    _history.clear();
    await _load(i.clamp(0, _queue.length - 1));
  }

  /// 取下一批。已经在取时等那一次，不另发请求（连按下一首时第二次不能当成「没取到」）。
  Future<void> _extendQueue() => _extendFuture ??= _doExtend().whenComplete(() {
    _extendFuture = null;
  });

  Future<void>? _extendFuture;

  /// 这次私人 FM 里出现过的歌（含已经「不喜欢」移出队列的），取下一批时去重用。
  final _radioSeen = <String>{};

  /// 取下一批的最多尝试次数。私人 FM 常常返回已经放过的歌，去重后为空时再取一次；网络失败也重试。
  static const _extendAttempts = 3;

  Future<void> _doExtend() async {
    final fetch = _extend;
    if (fetch == null) return;
    Object? error;
    for (var attempt = 0; attempt < _extendAttempts; attempt++) {
      if (attempt > 0) await Future<void>.delayed(extendRetryDelay * attempt);
      if (!identical(fetch, _extend)) return;
      try {
        final batch = await fetch();
        if (!identical(fetch, _extend)) return;
        final more = [
          for (final s in batch)
            if (_radioSeen.add(s.id)) s,
        ];
        if (more.isNotEmpty) {
          _queue = List.unmodifiable([..._queue, ...more]);
          notifyListeners();
          return;
        }
        error = null;
      } catch (e) {
        error = e;
      }
    }
    if (error != null) _notices.add('获取更多歌曲失败：$error');
  }

  /// 取下一批失败或全是重复时，重试前等多久（第 n 次重试等 n 倍）。测试里可以调短。
  @visibleForTesting
  static Duration extendRetryDelay = const Duration(milliseconds: 800);

  /// 下一首播放：把 [song] 放到当前这首后面（队列里已有就挪过去）。随机模式下也先放它。
  /// 队列为空时直接播放。
  Future<void> playNext(Song song) async {
    final cur = current;
    if (cur == null) return playQueue([song], title: '播放列表');
    if (cur.id == song.id) return;
    final list = [
      for (final s in _queue)
        if (s.id != song.id) s,
    ];
    final i = list.indexWhere((s) => s.id == cur.id);
    list.insert(i + 1, song);
    _queue = List.unmodifiable(list);
    _shuffleNext = null;
    _index = i;
    // 队列位置变了，旧的随机历史对不上，清掉。
    _history.clear();
    _upNext = song.id;
    notifyListeners();
  }

  /// 「下一首播放」指定的歌 id，切下一首时优先放它（随机模式也是）。
  String? _upNext;

  /// 定时关闭：[after] 后暂停；传 null 取消。
  void setSleepTimer(Duration? after) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepAt = null;
    if (after != null) {
      _sleepAt = DateTime.now().add(after);
      _sleepTimer = Timer(after, () {
        _sleepTimer = null;
        _sleepAt = null;
        pause();
        _notices.add('定时关闭：已暂停播放');
      });
    }
    notifyListeners();
  }

  /// 跳到队列里的第 [i] 首。
  Future<void> jumpTo(int i) {
    if (i < 0 || i >= _queue.length) return Future.value();
    _history.add(_index);
    return _load(i);
  }

  Future<void> next() => _advance(auto: false);

  /// 上一首。[restart] 为 true 时和多数播放器一致：播放超过 3 秒先回到开头。
  /// 通知栏、耳机的「上一首」传 false，直接切歌，免得看起来像卡在这一首。
  Future<void> previous({bool restart = true}) {
    if (_queue.length <= 1 || (restart && _position > const Duration(seconds: 3))) {
      return seek(Duration.zero);
    }
    if (_history.isNotEmpty && (_shuffle || isRadio)) {
      final i = _history.removeLast();
      if (i >= 0 && i < _queue.length && i != _index) return _load(i);
    }
    // 私人 FM 是一路往后放的，第一首没有「上一首」，不能绕到队尾。
    if (isRadio && _index == 0) return seek(Duration.zero);
    return _load((_index - 1 + _queue.length) % _queue.length);
  }

  void toggleShuffle() {
    if (isRadio) return;
    _shuffle = !_shuffle;
    _history.clear();
    _saveMode();
    notifyListeners();
  }

  void toggleRepeat() {
    _repeat = _repeat == Repeat.list ? Repeat.one : Repeat.list;
    _saveMode();
    notifyListeners();
  }

  /// 上次选的播放模式，重启后沿用。
  PlayMode get _savedMode =>
      PlayMode.values.where((m) => m.name == _settings.playMode).firstOrNull ?? PlayMode.list;

  void _applyMode(PlayMode mode) {
    _shuffle = mode == PlayMode.shuffle;
    _repeat = mode == PlayMode.one ? Repeat.one : Repeat.list;
  }

  /// 私人 FM 里开单曲循环前记着的模式，关掉单曲循环时还原。
  PlayMode? _modeBeforeRadioRepeat;

  /// 记住用户选的模式。私人 FM 下只有「∞」和单曲循环：开单曲循环照记；
  /// 关掉时还原开之前记的模式（随机还是随机），不把「∞」当成列表循环记下。
  void _saveMode() {
    final mode = playMode;
    if (isRadio) {
      if (mode == PlayMode.one) {
        _modeBeforeRadioRepeat ??= _savedMode;
      } else {
        final before = _modeBeforeRadioRepeat ?? _savedMode;
        _modeBeforeRadioRepeat = null;
        _settings.playMode = (before == PlayMode.one ? PlayMode.list : before).name;
        return;
      }
    } else {
      _modeBeforeRadioRepeat = null;
    }
    _settings.playMode = mode.name;
  }

  /// 当前播放模式：单曲循环优先于随机。
  PlayMode get playMode => _repeat == Repeat.one
      ? PlayMode.one
      : _shuffle
      ? PlayMode.shuffle
      : PlayMode.list;

  /// 按 列表循环 → 随机播放 → 单曲循环 → 列表循环 切换；私人 FM 下只在「∞」和单曲循环之间切换。
  void cyclePlayMode() {
    final next = switch (playMode) {
      PlayMode.list => isRadio ? PlayMode.one : PlayMode.shuffle,
      PlayMode.shuffle => PlayMode.one,
      PlayMode.one => PlayMode.list,
    };
    final shuffle = next == PlayMode.shuffle;
    if (shuffle != _shuffle) _history.clear();
    _shuffle = shuffle;
    _repeat = next == PlayMode.one ? Repeat.one : Repeat.list;
    _saveMode();
    notifyListeners();
  }

  Future<void> _advance({required bool auto}) async {
    if (_queue.isEmpty) return;
    if (auto && _repeat == Repeat.one) {
      _songToken++;
      _reportStart();
      return seek(Duration.zero).then((_) => play());
    }
    // 无尽队列放到最后一首：先取下一批，取到了就顺着放下去。
    if (isRadio && _index == _queue.length - 1) {
      final from = _index;
      await _extendQueue();
      // 等的时候已经切到别的歌了（例如又按了一次），这次就不再切。
      if (_index != from) return;
      // 没取到新歌：私人 FM 不绕回第一首，停在这里。
      if (_index == _queue.length - 1) {
        _notices.add('暂时没有更多推荐了，稍后再试');
        if (auto) {
          _playing = false;
          _stopTicker();
          notifyListeners();
        }
        return;
      }
    }
    _history.add(_index);
    final upNext = _upNext;
    _upNext = null;
    if (upNext != null) {
      final i = _queue.indexWhere((s) => s.id == upNext);
      if (i >= 0 && i != _index) return _load(i);
    }
    if (_shuffle && _queue.length > 1) {
      // 用预先选好的那首，和迷你播放条滑动时显示的一致。
      final planned = _shuffleNext;
      final i = planned != null && planned != _index && planned < _queue.length
          ? planned
          : _pickShuffle();
      return _load(i);
    }
    return _load((_index + 1) % _queue.length);
  }

  void _onCompleted() {
    if (!_playing) return;
    // 放完就上报，单曲循环或只有一首时不会走到换歌那一步。
    _reportListened();
    _advance(auto: true);
  }

  // ---------------------------------------------------------------- 加载

  Future<void> _load(
    int index, {
    Duration startAt = Duration.zero,
    bool? autoplay,
    bool keepLyrics = false,
  }) async {
    final token = ++_token;
    _shuffleNext = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _wantPlay = autoplay ?? true;
    final changingSong = index != _index;
    if (changingSong) {
      _reportListened();
      _songToken++;
      _errorRetries = 0;
    }
    _index = index;
    // 私人 FM 放到倒数第二首就提前取下一批，切到最后一首之后不用等网络。
    if (isRadio && index >= _queue.length - 2) unawaited(_extendQueue());
    _ready = false;
    final song = this.song;
    _position = startAt;
    _loading = true;
    _stopTicker();
    if (changingSong) {
      _qualities = const [];
      _quality = null;
      _trial = null;
      _lyricOffset = Duration.zero;
      _coverPalette = null;
      if (song.coverUrl case final url?) {
        unawaited(
          CoverPalette.of(url).then((p) {
            if (p != null && p.isNotEmpty && current?.id == song.id) {
              _coverPalette = p;
              notifyListeners();
            }
          }),
        );
      }
    }
    if (!keepLyrics) {
      _lyrics = Lyrics.empty;
      unawaited(_loadLyrics(song, _settings.lyricSource, fallback: true));
    }
    _playing = false;
    notifyListeners();
    unawaited(_engine.pause());

    try {
      final cache = this.cache;
      final preferred = _settings.preferredQuality;
      // 缓存里有就直接放本地文件，一个请求都不发（离线也能放）。
      final cached = cache == null ? null : await cache.lookup(song.id, preferred);
      if (token != _token) return;
      if (cached case final local?) {
        if (changingSong || _qualities.isEmpty) unawaited(_loadQualities(song, token));
        return await _playLocal(local, token, startAt);
      }
      if (changingSong || _qualities.isEmpty) {
        try {
          _qualities = await _backend.qualities(song.id);
        } on ApiException {
          _qualities = const []; // 取不到就直接按偏好请求，由服务端降级。
        }
        if (token != _token) return;
      }
      final target = AudioQuality.pick(_qualities.map((q) => q.quality), preferred) ?? preferred;
      // 这首歌没有偏好的那档时，按实际请求的音质再找一次缓存。
      if (cache != null && target != preferred) {
        final local = await cache.lookup(song.id, target);
        if (token != _token) return;
        if (local != null) return await _playLocal(local, token, startAt);
      }
      // 网络抖动、地址失效、音频没取下来都自动重试；每次重新取地址，免得拿着过期的链接反复试。
      final url = await withRetry(
        () async {
          final url = await _backend.songUrl(song.id, target);
          if (url != null && token == _token) {
            // 试听片段不缓存，只缓存完整的歌。
            final slot = cache != null && url.trial == null
                ? await cache.slot(song.id, target, url.quality ?? target, url.url)
                : null;
            if (token == _token) await _engine.load(url.url, start: startAt, cacheTo: slot);
          }
          return url;
        },
        delays: retryDelays,
        retryIf: (e) => token == _token && _isRetryable(e),
        shouldStop: () => token != _token,
      );
      if (token != _token) return;
      if (url == null) {
        // 现在取不到地址（例如会员过期），但以前缓存过：照样放。
        if (cache != null) {
          final local = await cache.best(song.id);
          if (token != _token) return;
          if (local != null) return await _playLocal(local, token, startAt);
        }
        _loading = false;
        _playing = false;
        notifyListeners();
        _notices.add('「${song.title}」暂无版权或需要会员');
        _failStreak++;
        if (_wantPlay && _failStreak < _queue.length) unawaited(_advance(auto: false));
        return;
      }
      _quality = url.quality ?? target;
      _trial = url.trial;
      if (url.trial != null) {
        _notices.add('「${song.title}」只能试听片段，登录会员账号后可完整播放');
      } else if (_quality != null && _quality!.index < target.index) {
        _notices.add('当前账号最高可用 ${_quality!.label}');
      }
      await _loaded();
    } catch (e) {
      if (token != _token) return;
      // 联网失败：有其他音质的缓存就先放它。
      if (cache case final cache?) {
        try {
          final local = await cache.best(song.id);
          if (token != _token) return;
          if (local != null) return await _playLocal(local, token, startAt, offline: true);
        } catch (_) {}
        if (token != _token) return;
      }
      _fail(e is ApiException ? e.message : '播放失败：$e');
    }
  }

  /// 放缓存里的文件。
  Future<void> _playLocal(
    CachedAudio local,
    int token,
    Duration startAt, {
    bool offline = false,
  }) async {
    await _engine.load(Uri.file(local.file.path).toString(), start: startAt);
    if (token != _token) return;
    _quality = local.quality;
    _trial = null;
    if (offline) _notices.add('网络不可用，正在播放本地缓存（${local.quality.label}）');
    await _loaded();
  }

  /// 地址装进内核之后：标记就绪，按需开始播放。
  Future<void> _loaded() async {
    _ready = true;
    _failStreak = 0;
    _loading = false;
    if (_wantPlay) {
      await _startPlayback();
    } else {
      notifyListeners();
    }
  }

  /// 放缓存时在后台取一下音质列表，给播放页切音质用。取不到就算了。
  Future<void> _loadQualities(Song song, int token) async {
    try {
      final q = await _backend.qualities(song.id);
      if (token != _token) return;
      _qualities = q;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadLyrics(Song song, LyricSource source, {required bool fallback}) async {
    _lyricsLoading = true;
    try {
      final l = await _backend.lyrics(song, source, fallback: fallback);
      if (current?.id != song.id) return;
      if (l.isEmpty && !fallback) {
        _notices.add('${source.label}没有这首歌的歌词');
        return;
      }
      _lyrics = l;
    } catch (_) {
      if (current?.id != song.id) return;
      if (!fallback) _notices.add('${source.label}歌词获取失败');
    } finally {
      if (current?.id == song.id) {
        _lyricsLoading = false;
        notifyListeners();
      }
    }
  }

  /// 当前这首听够了（30 秒，或短歌的一半）就上报给网易云，然后清零。
  void _reportListened() {
    final song = current;
    final listened = _listened;
    _listened = Duration.zero;
    if (song == null || !_settings.syncRecentPlays) return;
    final half = song.duration ~/ 2;
    final need = half > Duration.zero && half < _scrobbleAfter ? half : _scrobbleAfter;
    if (listened < need) return;
    unawaited(
      _backend
          .scrobble(song, listened: listened, sourceId: _sourceId)
          .catchError((Object _) {}), // 上报失败不影响播放，也不打扰用户。
    );
  }

  static const _scrobbleAfter = Duration(seconds: 30);

  /// 这首歌第一次真正开始播放时报给网易云，让它进「最近播放」。
  void _reportStart() {
    final song = current;
    if (song == null || _startReportedToken == _songToken || !_settings.syncRecentPlays) return;
    _startReportedToken = _songToken;
    unawaited(_backend.startPlay(song, sourceId: _sourceId).catchError((Object _) {}));
  }

  /// 接口明确拒绝（未登录、无权限等）就别重试了；断网、超时、5xx 和播放内核的错误都值得再试。
  static bool _isRetryable(Object e) {
    if (e is ApiException) {
      final code = e.code;
      return code == null || code >= 500 || code == 408 || code == 429;
    }
    return true;
  }

  /// 播放中途出错（断网、解码失败等）：从出错的位置重新加载，几次都不行再报错。
  void _onEngineError(Object e) {
    // 加载过程中的错误由 _load 自己处理。
    if (_loading || current == null) return;
    _ready = false;
    if (_errorRetries >= retryDelays.length) {
      _fail('播放出错：$e');
      return;
    }
    final delay = retryDelays[_errorRetries++];
    // 等待重试期间按「加载中」处理：界面转圈，暂停 / 播放只改加载完后要不要接着放。
    _wantPlay = _playing;
    _playing = false;
    _loading = true;
    _stopTicker();
    notifyListeners();
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_load(_index, startAt: _position, autoplay: _wantPlay, keepLyrics: true));
    });
  }

  void _fail(String message) {
    _ready = false;
    _loading = false;
    _playing = false;
    _stopTicker();
    notifyListeners();
    _notices.add(message);
  }

  // ---------------------------------------------------------------- 控制

  Future<void> play() async {
    if (current == null || _playing) return;
    if (_loading) {
      // 加载完成后自动开始。
      _wantPlay = true;
      notifyListeners();
      return;
    }
    if (!_ready) {
      // 上次加载失败了，内核里不是这首（可能还是上一首），重新加载这首再放。
      _errorRetries = 0;
      await _load(_index, startAt: _position, autoplay: true, keepLyrics: true);
      return;
    }
    await _startPlayback();
  }

  Future<void> _startPlayback() async {
    _reportStart();
    _playing = true;
    await _engine.play();
    _startTicker();
    notifyListeners();
  }

  Future<void> pause() async {
    if (_loading) {
      _wantPlay = false;
      notifyListeners();
      return;
    }
    if (!_playing) return;
    _playing = false;
    _stopTicker();
    _position = _engine.position;
    await _engine.pause();
    notifyListeners();
  }

  Future<void> toggle() => isPlaying ? pause() : play();

  Future<void> seek(Duration to) async {
    _position = Duration(microseconds: to.inMicroseconds.clamp(0, duration.inMicroseconds));
    notifyListeners();
    await _engine.seek(_position);
  }

  Future<void> seekBy(Duration delta) => seek(_position + delta);

  /// 切换音质并设为默认。保持进度和播放状态。
  Future<void> setQuality(AudioQuality q) {
    _settings.preferredQuality = q;
    if (current == null || q == _quality) return Future.value();
    return _load(_index, startAt: _position, autoplay: isPlaying, keepLyrics: true);
  }

  /// 换一个歌词来源（只查这一个来源）。没有歌词时保留当前歌词并提示。
  Future<void> setLyricSource(LyricSource source) async {
    final s = current;
    if (s == null || source == _lyrics.source) return;
    await _loadLyrics(s, source, fallback: false);
  }

  void setVolume(double v) {
    _volume = v.clamp(0.0, 1.0);
    _engine.setVolume(_volume);
    notifyListeners();
  }

  void adjustLyricOffset(Duration delta) {
    _lyricOffset += delta;
    notifyListeners();
  }

  void resetLyricOffset() {
    _lyricOffset = Duration.zero;
    notifyListeners();
  }

  void _startTicker() {
    _timer ??= Timer.periodic(_tick, (_) {
      final p = _engine.position;
      // 只累计正常播放推进的时间，拖动进度造成的跳变不算。
      final step = p - _position;
      if (step > Duration.zero && step < const Duration(seconds: 2)) _listened += step;
      _position = p;
      // 只通知关心进度的（进度条、歌词）；普通监听者不跟着每 50ms 重建，列表滚动才不卡。
      _ticks.fire();
    });
  }

  void _stopTicker() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopTicker();
    _ticks.dispose();
    _retryTimer?.cancel();
    _sleepTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _notices.close();
    _engine.dispose();
    super.dispose();
  }
}

class _Ticks extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// 把 [PlayerController] 挂到树上；依赖它的 widget 在播放状态变化（切歌、播放 / 暂停……）时重建，
/// 播放进度推进时不重建。要跟着进度走的用 [PlayerScope.ticking]。
class PlayerScope extends InheritedNotifier<PlayerController> {
  const PlayerScope({super.key, required PlayerController controller, required super.child})
    : super(notifier: controller);

  static PlayerController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlayerScope>()!.notifier!;

  /// 同 [of]，另外在播放进度推进时（约 50ms 一次）也重建。只给进度条、歌词这类用。
  static PlayerController ticking(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<PlayerTickScope>();
    return of(context);
  }

  /// 只取引用、不订阅变化，用于按钮回调。
  static PlayerController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PlayerScope>()!.notifier!;
}

/// 播放进度的通知，放在 [PlayerScope] 下面，见 [PlayerScope.ticking]。
class PlayerTickScope extends InheritedNotifier<Listenable> {
  PlayerTickScope({super.key, required PlayerController controller, required super.child})
    : super(notifier: controller.ticks);
}
