import 'package:flutter/painting.dart';

/// 歌曲。[palette] 是封面图加载出来之前的占位色，也是取不到封面主色时播放页背景的兜底。
/// 官方首页里取到的推荐：「根据你喜爱的歌曲推荐」和「雷达歌单」两个板块。
class HomeFeed {
  const HomeFeed({
    required this.songTitle,
    required this.songs,
    this.radarTitle = '雷达歌单',
    this.radar = const [],
  });

  /// 歌曲推荐板块的官方标题，例如「根据你喜爱的歌曲推荐」。
  final String songTitle;
  final List<SongRcmd> songs;

  /// 雷达歌单板块的官方标题，例如「某某的雷达歌单」。
  final String radarTitle;
  final List<Playlist> radar;
}

/// 推荐里的一首歌和它的标签。
class SongRcmd {
  const SongRcmd({required this.song, this.tag, this.quality});

  final Song song;

  /// 推荐理由标签，例如「单曲循环的日语歌」「昨日上万播放」。
  final String? tag;

  /// 最高音质的角标：SQ（无损）或 Hi-Res。
  final String? quality;
}

class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.coverUrl,
    this.subtitle,
    this.artists = const [],
    this.albumId,
    this._palette,
  });

  final String id;
  final String title;

  /// 带 id 的歌手列表，用于跳转歌手页。和 [artist] 一一对应；本地构造的歌曲可能为空。
  final List<ArtistRef> artists;

  /// 专辑 id，用于跳转专辑页。
  final String? albumId;

  /// 多位歌手用 ` / ` 连接。
  final String artist;
  final String album;
  final Duration duration;
  final String? coverUrl;

  /// 别名或译名，例如 `(TV动画《…》片头曲)`。
  final String? subtitle;
  final List<Color>? _palette;

  List<Color> get palette => _palette ?? fallbackPalette(id);

  /// 存本地缓存用。封面主色不存，读回来用占位色。
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'ms': duration.inMilliseconds,
    if (coverUrl != null) 'cover': coverUrl,
    if (subtitle != null) 'sub': subtitle,
    if (albumId != null) 'albumId': albumId,
    if (artists.isNotEmpty)
      'artists': [
        for (final a in artists) [a.id, a.name],
      ],
  };

  /// [toJson] 的逆操作；格式不对时返回 null。
  static Song? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], title = json['title'];
    if (id is! String || title is! String) return null;
    final ms = json['ms'];
    return Song(
      id: id,
      title: title,
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      duration: Duration(milliseconds: ms is int ? ms : 0),
      coverUrl: json['cover'] as String?,
      subtitle: json['sub'] as String?,
      albumId: json['albumId'] as String?,
      artists: [
        for (final a in json['artists'] as List? ?? const [])
          if (a is List && a.length == 2 && a[0] is String && a[1] is String)
            ArtistRef(a[0] as String, a[1] as String),
      ],
    );
  }

  @override
  bool operator ==(Object other) => other is Song && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.playCount,
    this.trackCount = 0,
    this.coverUrl,
    this.creator,
    this.creatorId,
    this.description,
    this.subscribed = false,
    this.isLikedList = false,
    this.shared = false,
    this.sharedUsers = const [],
    this._palette,
  });

  final String id;
  final String name;
  final int playCount;
  final int trackCount;
  final String? coverUrl;
  final String? creator;
  final int? creatorId;

  /// 简介；排行榜用来放更新频率（如「每周四更新」）。
  final String? description;

  /// 当前账号是否收藏了这个歌单（自己创建的为 false）。
  final bool subscribed;

  /// 账号的「我喜欢的音乐」。
  final bool isLikedList;

  /// 共建歌单（创建时 type 为 SHARED，好友可以一起加歌）。
  final bool shared;

  /// 共建歌单里除创建者以外的成员。接口没给时为空。
  final List<SocialUser> sharedUsers;
  final List<Color>? _palette;

  List<Color> get palette => _palette ?? fallbackPalette(id);

  /// 换一个封面（[url] 为 null 时原样返回）。
  Playlist withCover(String? url) => url == null || url == coverUrl
      ? this
      : Playlist(
          id: id,
          name: name,
          playCount: playCount,
          trackCount: trackCount,
          coverUrl: url,
          creator: creator,
          creatorId: creatorId,
          description: description,
          subscribed: subscribed,
          isLikedList: isLikedList,
          shared: shared,
          sharedUsers: sharedUsers,
          palette: _palette,
        );
}

extension PlaylistJson on Playlist {
  /// 存本地缓存用。封面主色不存。
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'plays': playCount,
    'tracks': trackCount,
    'cover': ?coverUrl,
    'creator': ?creator,
    'creatorId': ?creatorId,
    'desc': ?description,
    if (subscribed) 'sub': true,
    if (isLikedList) 'liked': true,
    if (shared) 'shared': true,
    if (sharedUsers.isNotEmpty) 'users': [for (final u in sharedUsers) u.toJson()],
  };

  /// [toJson] 的逆操作；格式不对时返回 null。
  static Playlist? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], name = json['name'];
    if (id is! String || name is! String) return null;
    return Playlist(
      id: id,
      name: name,
      playCount: json['plays'] as int? ?? 0,
      trackCount: json['tracks'] as int? ?? 0,
      coverUrl: json['cover'] as String?,
      creator: json['creator'] as String?,
      creatorId: json['creatorId'] as int?,
      description: json['desc'] as String?,
      subscribed: json['sub'] == true,
      isLikedList: json['liked'] == true,
      shared: json['shared'] == true,
      sharedUsers: [
        for (final u in json['users'] as List? ?? const []) ?SocialUserJson.fromJson(u),
      ],
    );
  }
}

class ArtistRef {
  const ArtistRef(this.id, this.name);

  final String id;
  final String name;
}

class Artist {
  const Artist({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.description,
    this.songCount = 0,
    this.albumCount = 0,
    this.accountId,
    this.followed = false,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final String? description;
  final int songCount;
  final int albumCount;

  /// 歌手入驻后绑定的网易云账号；没有为 null。
  final int? accountId;

  /// 当前账号是否关注（收藏）了这个歌手。只有歌手详情接口带这个字段。
  final bool followed;
}

/// 用户主页的资料（`/api/v1/user/detail`）。
class UserDetail {
  const UserDetail({
    required this.userId,
    required this.nickname,
    this.avatarUrl,
    this.backgroundUrl,
    this.signature,
    this.identity,
    this.level = 0,
    this.listenSongs = 0,
    this.follows = 0,
    this.followeds = 0,
    this.artistId,
    this.playRecordPublic = true,
    this.followed = false,
  });

  final int userId;
  final String nickname;
  final String? avatarUrl;
  final String? backgroundUrl;

  /// 个性签名。
  final String? signature;

  /// 认证说明，例如「唱作音乐人毛不易」。
  final String? identity;
  final int level;

  /// 累计听歌数。
  final int listenSongs;
  final int follows;
  final int followeds;

  /// 账号绑定的歌手（音乐人）；普通用户为 null。
  final String? artistId;

  /// 是否公开听歌排行。
  final bool playRecordPublic;

  /// 我是否已关注 TA（登录后才有意义）。
  final bool followed;
}

class Album {
  const Album({
    required this.id,
    required this.name,
    required this.artist,
    this.coverUrl,
    this.publishTime,
    this.size = 0,
    this.description,
  });

  final String id;
  final String name;

  /// 多位歌手用 ` / ` 连接。
  final String artist;
  final String? coverUrl;
  final DateTime? publishTime;

  /// 曲目数。
  final int size;
  final String? description;
}

class UserProfile {
  const UserProfile({
    required this.userId,
    required this.nickname,
    this.avatarUrl,
    this.vipType = 0,
  });

  final int userId;
  final String nickname;
  final String? avatarUrl;

  /// 0 为普通用户，其他值为各类会员。
  final int vipType;

  Map<String, Object?> toJson() => {
    'id': userId,
    'name': nickname,
    'avatar': ?avatarUrl,
    'vip': vipType,
  };

  static UserProfile? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], name = json['name'];
    if (id is! int || name is! String) return null;
    return UserProfile(
      userId: id,
      nickname: name,
      avatarUrl: json['avatar'] as String?,
      vipType: json['vip'] as int? ?? 0,
    );
  }
}

/// 网易云的音质档位，从低到高排列；[index] 越大越好。
enum AudioQuality {
  standard('standard', 'l', '标准', '标准'),
  higher('higher', 'm', '较高', '较高'),
  exhigh('exhigh', 'h', '极高', 'HQ'),
  lossless('lossless', 'sq', '无损', 'SQ'),
  hires('hires', 'hr', 'Hi-Res', 'Hi-Res'),
  jyeffect('jyeffect', 'je', '高清环绕声', '环绕'),
  sky('sky', 'sk', '沉浸环绕声', '沉浸'),
  dolby('dolby', 'db', '杜比全景声', 'Dolby'),
  jymaster('jymaster', 'jm', '超清母带', '母带');

  const AudioQuality(this.level, this.detailKey, this.label, this.badge);

  /// 接口里的 `level` 值。
  final String level;

  /// `song/music/detail/get` 返回里对应的字段名。
  final String detailKey;
  final String label;

  /// 播放页歌手名前的小徽章。
  final String badge;

  static AudioQuality? fromLevel(String? level) {
    for (final q in values) {
      if (q.level == level) return q;
    }
    return null;
  }

  /// 在 [available] 里挑一个：不超过 [preferred] 的最高档；都比它高就取最低档。
  static AudioQuality? pick(Iterable<AudioQuality> available, AudioQuality preferred) {
    final sorted = available.toList()..sort((a, b) => a.index - b.index);
    if (sorted.isEmpty) return null;
    return sorted.lastWhere((q) => q.index <= preferred.index, orElse: () => sorted.first);
  }
}

/// 某一档音质的文件信息。
class QualityInfo {
  const QualityInfo({
    required this.quality,
    required this.bitrate,
    required this.size,
    this.sampleRate,
  });

  final AudioQuality quality;

  /// bit/s。
  final int bitrate;

  /// 字节。
  final int size;
  final int? sampleRate;

  Map<String, Object?> toJson() => {
    'q': quality.level,
    'br': bitrate,
    'size': size,
    'sr': ?sampleRate,
  };

  static QualityInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final q = AudioQuality.fromLevel(json['q'] as String?);
    if (q == null) return null;
    return QualityInfo(
      quality: q,
      bitrate: json['br'] as int? ?? 0,
      size: json['size'] as int? ?? 0,
      sampleRate: json['sr'] as int?,
    );
  }
}

/// 取到的播放地址。[quality] 是服务端实际给的档位，可能低于请求的档位（版权或会员限制）。
class SongUrl {
  const SongUrl({required this.url, required this.quality, this.trial});

  final String url;
  final AudioQuality? quality;

  /// 非 null 表示只给了试听片段，值为片段在整首歌里的起止时间。
  final ({Duration start, Duration end})? trial;
}

/// 逐字歌词里的一个"字"（实际上可以是一个词或一个音节）。
class LyricWord {
  const LyricWord(this.text, this.start, this.end, {this.ruby});

  final String text;
  final Duration start;
  final Duration end;

  /// 注音（日语振假名、拼音等），显示在字的上方。只有 TTML 歌词会有。
  final String? ruby;

  /// 在 [position] 时该字已唱出的比例，0–1。
  double progressAt(Duration position) {
    if (position <= start) return 0;
    if (position >= end) return 1;
    return (position - start).inMicroseconds / (end - start).inMicroseconds;
  }
}

class LyricLine {
  const LyricLine({
    required this.start,
    required this.end,
    required this.words,
    this.translation,
    this.romaji,
    this.duet = false,
    this.background,
  });

  final Duration start;
  final Duration end;

  /// 逐字歌词时每个字单独计时；逐行歌词时只有一个覆盖整行的"字"。
  final List<LyricWord> words;
  final String? translation;
  final String? romaji;

  /// 对唱：由另一位歌手演唱，靠右显示。只有 TTML 歌词会有。
  final bool duet;

  /// 背景人声（和声），跟在主歌词下面、字号更小。只有 TTML 歌词会有。
  /// 它自己的 [start]、[end] 不影响当前行的判断。
  final LyricLine? background;

  String get text => words.map((w) => w.text).join();

  LyricLine copyWith({String? translation, String? romaji}) => LyricLine(
    start: start,
    end: end,
    words: words,
    translation: translation ?? this.translation,
    romaji: romaji ?? this.romaji,
    duet: duet,
    background: background,
  );
}

enum LyricSource {
  netease('网易云'),
  qq('QQ 音乐'),
  amll('AMLL');

  const LyricSource(this.label);

  final String label;

  static LyricSource? byName(String? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// 一首歌的完整歌词。
class Lyrics {
  const Lyrics({required this.lines, required this.source, required this.wordSynced});

  static const empty = Lyrics(lines: [], source: null, wordSynced: false);

  final List<LyricLine> lines;

  /// 歌词来自哪里；没有歌词时为 null。
  final LyricSource? source;

  /// 是否逐字。
  final bool wordSynced;

  bool get isEmpty => lines.isEmpty;
  bool get hasTranslation => lines.any((l) => l.translation != null);
  bool get hasRomaji => lines.any((l) => l.romaji != null);

  /// 存本地缓存用。时间都用毫秒。
  Map<String, Object?> toJson() => {
    'src': ?source?.name,
    'word': wordSynced,
    'lines': [for (final l in lines) _lineJson(l)],
  };

  static Lyrics? fromJson(Object? json) {
    if (json is! Map || json['lines'] is! List) return null;
    final lines = <LyricLine>[];
    for (final l in json['lines'] as List) {
      final line = _lineFrom(l);
      if (line == null) return null;
      lines.add(line);
    }
    return Lyrics(
      lines: lines,
      source: LyricSource.byName(json['src'] as String?),
      wordSynced: json['word'] == true,
    );
  }

  static Map<String, Object?> _lineJson(LyricLine l) => {
    's': l.start.inMilliseconds,
    'e': l.end.inMilliseconds,
    'w': [
      for (final w in l.words) [w.text, w.start.inMilliseconds, w.end.inMilliseconds, ?w.ruby],
    ],
    't': ?l.translation,
    'r': ?l.romaji,
    if (l.duet) 'd': true,
    if (l.background case final bg?) 'bg': _lineJson(bg),
  };

  static LyricLine? _lineFrom(Object? json) {
    if (json is! Map) return null;
    final s = json['s'], e = json['e'], w = json['w'];
    if (s is! int || e is! int || w is! List) return null;
    final words = <LyricWord>[];
    for (final x in w) {
      if (x is! List || x.length < 3 || x[0] is! String || x[1] is! int || x[2] is! int) {
        return null;
      }
      words.add(
        LyricWord(
          x[0] as String,
          Duration(milliseconds: x[1] as int),
          Duration(milliseconds: x[2] as int),
          ruby: x.length > 3 ? x[3] as String? : null,
        ),
      );
    }
    return LyricLine(
      start: Duration(milliseconds: s),
      end: Duration(milliseconds: e),
      words: words,
      translation: json['t'] as String?,
      romaji: json['r'] as String?,
      duet: json['d'] == true,
      background: json['bg'] == null ? null : _lineFrom(json['bg']),
    );
  }
}

/// 评论区属于哪类资源。网易云用 `前缀 + id` 作为评论区 id（threadId）。
enum CommentTarget {
  song('R_SO_4_'),
  playlist('A_PL_0_'),
  album('R_AL_3_'),

  /// 动态的评论区 id 是 `A_EV_2_动态id_作者id`，所以这里的 id 传 `动态id_作者id`。
  event('A_EV_2_');

  const CommentTarget(this.prefix);

  final String prefix;

  String threadId(String id) => '$prefix$id';
}

/// 评论排序：按热度或按时间。
enum CommentSort {
  hot(2, '热门'),
  latest(3, '最新');

  const CommentSort(this.type, this.label);

  /// 接口里的 sortType。
  final int type;
  final String label;
}

class CommentUser {
  const CommentUser({required this.userId, required this.nickname, this.avatarUrl});

  final int userId;
  final String nickname;
  final String? avatarUrl;
}

/// 一条评论。楼中楼回复也用它，[replyTo] 是被回复的那条（可能已删除，为 null）。
class Comment {
  const Comment({
    required this.id,
    required this.user,
    required this.content,
    required this.time,
    this.likedCount = 0,
    this.liked = false,
    this.replyCount = 0,
    this.replyTo,
    this.location,
  });

  final int id;
  final CommentUser user;
  final String content;
  final DateTime time;
  final int likedCount;
  final bool liked;

  /// 楼层里的回复数。
  final int replyCount;
  final ({int id, String nickname, String content})? replyTo;

  /// IP 属地，如「广东」。
  final String? location;

  Comment copyWith({int? likedCount, bool? liked, int? replyCount}) => Comment(
    id: id,
    user: user,
    content: content,
    time: time,
    likedCount: likedCount ?? this.likedCount,
    liked: liked ?? this.liked,
    replyCount: replyCount ?? this.replyCount,
    replyTo: replyTo,
    location: location,
  );
}

/// 一页评论。[cursor] 原样传给下一页。
class CommentPage {
  const CommentPage({
    required this.comments,
    required this.total,
    required this.hasMore,
    required this.cursor,
  });

  final List<Comment> comments;
  final int total;
  final bool hasMore;
  final String cursor;
}

/// 根据 id 稳定地挑一组占位色。
List<Color> fallbackPalette(String seed) {
  const palettes = [
    [Color(0xFFF7A8C8), Color(0xFF8E7CF0), Color(0xFFFFD98A)],
    [Color(0xFF6FA8DC), Color(0xFF2B3F66), Color(0xFFBFD8F2)],
    [Color(0xFF1B1036), Color(0xFFE0367F), Color(0xFF29D3F0)],
    [Color(0xFF5A3A22), Color(0xFFE09A4A), Color(0xFF1E140E)],
    [Color(0xFF3B2A4D), Color(0xFFB0605A), Color(0xFFE8B66B)],
    [Color(0xFF2E5E4E), Color(0xFF9FD3A8), Color(0xFF14261F)],
  ];
  // 不用 String.hashCode：它在不同运行之间不保证稳定。
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palettes[h % palettes.length];
}

// ---------------------------------------------------------------- 社交

/// 关注 / 粉丝列表、私信、动态里出现的用户。
class SocialUser {
  const SocialUser({
    required this.userId,
    required this.nickname,
    this.avatarUrl,
    this.signature,
    this.followed = false,
    this.mutual = false,
    this.musician = false,
    this.followeds = 0,
  });

  final int userId;
  final String nickname;
  final String? avatarUrl;
  final String? signature;

  /// 我是否关注了 TA（未登录时总是 false）。
  final bool followed;

  /// 互相关注。
  final bool mutual;

  /// 音乐人 / 认证艺人。「关注」页的「音乐人」「朋友」按这个分。
  final bool musician;

  /// 粉丝数。
  final int followeds;

  SocialUser copyWith({bool? followed}) => SocialUser(
    userId: userId,
    nickname: nickname,
    avatarUrl: avatarUrl,
    signature: signature,
    followed: followed ?? this.followed,
    mutual: mutual,
    musician: musician,
    followeds: followeds,
  );
}

extension SocialUserJson on SocialUser {
  /// 存本地缓存用，只存头像和名字这些显示用的信息。
  Map<String, Object?> toJson() => {'id': userId, 'name': nickname, 'avatar': ?avatarUrl};

  static SocialUser? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], name = json['name'];
    if (id is! int || name is! String) return null;
    return SocialUser(userId: id, nickname: name, avatarUrl: json['avatar'] as String?);
  }
}

/// 一页用户（关注 / 粉丝）。
class SocialUserPage {
  const SocialUserPage({required this.users, required this.more, this.cursor});

  final List<SocialUser> users;
  final bool more;

  /// 下一页的游标；按 offset 翻页的接口为 null。
  final String? cursor;
}

/// 一条动态。转发的动态（[forwarded] 不为空）正文是转发语，被转发的内容在 [forwarded] 里。
class UserEvent {
  const UserEvent({
    required this.id,
    required this.user,
    required this.time,
    required this.type,
    this.text = '',
    this.title,
    this.pics = const [],
    this.song,
    this.playlist,
    this.album,
    this.forwarded,
    this.threadId,
    this.likedCount = 0,
    this.liked = false,
    this.commentCount = 0,
    this.shareCount = 0,
  });

  final int id;
  final SocialUser user;
  final DateTime time;

  /// 接口里的动态类型：18 分享单曲、13 分享歌单、19 分享专辑、22 转发……
  final int type;
  final String text;
  final String? title;

  /// 配图（原图地址）。
  final List<String> pics;
  final Song? song;
  final Playlist? playlist;
  final Album? album;
  final UserEvent? forwarded;

  /// 评论区 id（`A_EV_2_…`），也用来点赞。
  final String? threadId;
  final int likedCount;
  final bool liked;
  final int commentCount;
  final int shareCount;

  /// 「分享单曲」这类动作说明，普通动态为 null。
  String? get action => switch (type) {
    18 => '分享单曲',
    19 => '分享专辑',
    13 => '分享歌单',
    17 || 28 => '分享节目',
    22 => '转发',
    24 => '分享专栏文章',
    21 || 39 || 41 => '分享视频',
    _ => null,
  };

  UserEvent copyWith({bool? liked, int? likedCount}) => UserEvent(
    id: id,
    user: user,
    time: time,
    type: type,
    text: text,
    title: title,
    pics: pics,
    song: song,
    playlist: playlist,
    album: album,
    forwarded: forwarded,
    threadId: threadId,
    likedCount: likedCount ?? this.likedCount,
    liked: liked ?? this.liked,
    commentCount: commentCount,
    shareCount: shareCount,
  );
}

/// 一页动态。下一页传 [lasttime]。
class EventPage {
  const EventPage({required this.events, required this.more, required this.lasttime});

  final List<UserEvent> events;
  final bool more;
  final int lasttime;
}

/// 私信列表里的一个会话。
class Conversation {
  const Conversation({
    required this.user,
    required this.preview,
    required this.time,
    this.unread = 0,
  });

  final SocialUser user;

  /// 最后一条消息的摘要。
  final String preview;
  final DateTime time;
  final int unread;
}

/// 一条私信。分享歌曲 / 歌单 / 专辑时带上对应资源。
class PrivateMessage {
  const PrivateMessage({
    required this.id,
    required this.fromUserId,
    required this.time,
    this.text = '',
    this.song,
    this.playlist,
    this.album,
    this.imageUrl,
  });

  final int id;
  final int fromUserId;
  final DateTime time;
  final String text;
  final Song? song;
  final Playlist? playlist;
  final Album? album;
  final String? imageUrl;
}

/// 一页私信记录，[messages] 按时间从旧到新。
class MessageHistory {
  const MessageHistory({required this.messages, required this.more});

  final List<PrivateMessage> messages;
  final bool more;
}

/// 「我的关注」的筛选：全部、音乐人、普通用户。顺序即接口里的 scene。
enum FollowScene {
  all('全部'),
  musicians('音乐人'),
  friends('朋友');

  const FollowScene(this.label);

  final String label;
}

// ---------------------------------------------------------------- 用户状态

/// 用户状态：个人主页名字下面那条「状态」，例如「学习中」「emo 中」。
///
/// 可选状态列表（`/api/social/user/status/support`）里的每一项也用这个类，
/// 这时 [canEdit] 为 true 表示文字可以自己改。
class UserStatus {
  const UserStatus({
    required this.type,
    required this.content,
    this.iconUrl,
    this.actionUrl,
    this.desc,
    this.canEdit = false,
    this.song,
  });

  /// 状态类型，设置状态时原样传回。
  final String type;

  /// 状态文字。
  final String content;
  final String? iconUrl;
  final String? actionUrl;

  /// 可选状态的说明文字。
  final String? desc;

  /// 文字是否可以自己改。
  final bool canEdit;

  /// 状态带的歌；没有为 null。
  final Song? song;

  UserStatus copyWith({String? content}) => UserStatus(
    type: type,
    content: content ?? this.content,
    iconUrl: iconUrl,
    actionUrl: actionUrl,
    desc: desc,
    canEdit: canEdit,
    song: song,
  );
}

/// 「相同状态的人」里的一个用户。
class StatusUser {
  const StatusUser({
    required this.userId,
    required this.nickname,
    this.avatarUrl,
    this.status,
    this.tags = const [],
  });

  final int userId;
  final String nickname;
  final String? avatarUrl;
  final UserStatus? status;

  /// 推荐理由标签，例如共同喜欢的歌手。
  final List<String> tags;
}

/// 和我状态相同的人（`/api/social/user/status/rcmd`）。没设置状态时 [users] 为空。
class StatusRcmd {
  const StatusRcmd({this.title, this.status, this.users = const []});

  final String? title;

  /// 我当前的状态。
  final UserStatus? status;
  final List<StatusUser> users;
}

/// 一起听的状态：是否在房间里，房间号、房主、房间里的人。
class ListenTogetherStatus {
  const ListenTogetherStatus({
    required this.inRoom,
    this.roomId,
    this.creatorId = 0,
    this.users = const [],
  });

  final bool inRoom;
  final String? roomId;
  final int creatorId;
  final List<SocialUser> users;
}

/// 一起听房间的最后一条播放指令。
class ListenTogetherCommand {
  const ListenTogetherCommand({
    required this.songId,
    required this.playing,
    required this.progress,
    required this.serverTime,
    required this.clientSeq,
    required this.userId,
  });

  final String songId;
  final bool playing;

  /// 发指令时的进度。
  final Duration progress;

  /// 服务器收到指令的时间（毫秒时间戳，接口字段 serverSeq）。不像时间戳时为 0。
  final int serverTime;
  final int clientSeq;
  final int userId;

  /// 按 [now] 推算的当前进度：暂停时就是 [progress]；播放时加上服务器收到指令后过去的时间。
  /// 服务器时间不可信（缺失或和本机差太多）时，从 [receivedAt]（本机拿到快照的时间）算起。
  Duration positionAt(DateTime now, {required DateTime receivedAt}) {
    if (!playing) return progress;
    final nowMs = now.millisecondsSinceEpoch;
    final trusted = serverTime > 1000000000000 && (nowMs - serverTime).abs() < 600000;
    final from = trusted ? serverTime : receivedAt.millisecondsSinceEpoch;
    final elapsed = nowMs - from;
    return progress + Duration(milliseconds: elapsed < 0 ? 0 : elapsed);
  }
}

/// 一起听房间的快照：播放列表和最后一条指令（没有时为 null）。
class ListenTogetherSnapshot {
  const ListenTogetherSnapshot({required this.songIds, this.command});

  final List<String> songIds;
  final ListenTogetherCommand? command;
}

/// 歌曲百科里的一首相关歌曲（只有列表展示用的信息，播放前再取详情）。
class SongBrief {
  const SongBrief({required this.id, required this.title, this.artist = '', this.coverUrl});

  final String id;
  final String title;
  final String artist;
  final String? coverUrl;
}

/// 歌曲百科：基本信息（曲风、标签、语种、BPM、获奖、影视节目……）、相似歌曲、相关歌单。
class SongWiki {
  const SongWiki({this.facts = const [], this.similar = const [], this.playlists = const []});

  /// 每条是一个名称和它的若干个值，例如「曲风」→「流行-华语流行」。
  final List<({String label, List<String> values})> facts;
  final List<SongBrief> similar;
  final List<Playlist> playlists;

  bool get isEmpty => facts.isEmpty && similar.isEmpty && playlists.isEmpty;

  /// 在相似歌曲后面补上 [more] 里还没有的歌。
  SongWiki withMoreSimilar(List<SongBrief> more) {
    final seen = {for (final s in similar) s.id};
    return SongWiki(
      facts: facts,
      similar: [...similar, ...more.where((s) => seen.add(s.id))],
      playlists: playlists,
    );
  }
}

/// 播放页百科里「关于艺人」卡片的资料。
class ArtistProfile {
  const ArtistProfile({
    required this.artist,
    this.coverUrl,
    this.fans,
    this.followed = false,
    this.latestAlbum,
  });

  final Artist artist;

  /// 横版大图；没有时用头像。
  final String? coverUrl;

  /// 粉丝数；取不到为 null。
  final int? fans;
  final bool followed;
  final Album? latestAlbum;
}

/// 共建歌单的成员（创建者在最前）和每首歌是谁添加的。
class SharedPlaylistInfo {
  const SharedPlaylistInfo({this.creator, this.members = const [], this.adders = const {}});

  final SocialUser? creator;
  final List<SocialUser> members;

  /// 歌曲 id → 添加这首歌的成员。
  final Map<String, SocialUser> adders;
}

/// 私人 FM 的模式（接口参数参考 api-enhanced 的 personal_fm_mode）。
enum FmMode {
  normal('推荐', '根据你的口味连续播放', 'DEFAULT'),
  familiar('熟悉', '多放你听过、喜欢的', 'FAMILIAR'),
  explore('探索', '多放没听过的新歌', 'EXPLORE'),
  aiDj('AI DJ', '由 AI 帮你挑歌', 'aidj'),
  exercise('运动', '适合运动时听', 'SCENE_RCMD', 'EXERCISE'),
  focus('专注', '适合工作、学习时听', 'SCENE_RCMD', 'FOCUS'),
  night('深夜', '安静的夜晚', 'SCENE_RCMD', 'NIGHT_EMO');

  const FmMode(this.label, this.description, this.mode, [this.subMode]);

  final String label;
  final String description;

  /// 接口的 mode / subMode。
  final String mode;
  final String? subMode;

  static FmMode fromName(String? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => normal);
}
