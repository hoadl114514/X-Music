import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../data/models.dart';
import 'client_identity.dart';
import 'cookies.dart';
import 'eapi_crypto.dart';
import 'weapi_crypto.dart';
import 'xeapi_crypto.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.code, this.network = false});

  final String message;

  /// 请求没发出去或没收到响应（超时、断网）。这时服务端可能已经处理了请求。
  final bool network;

  /// 接口返回的 `code`；网络层错误时为 HTTP 状态码或 null。
  final int? code;

  /// 301 / 302：未登录或登录已失效。
  bool get needsLogin => code == 301 || code == 302;

  /// -460 / -462：网络环境或操作被风控。
  bool get riskControl => code == -460 || code == -462;

  @override
  String toString() => code == null ? message : '$message（code=$code）';
}

/// 网易云接口。
///
/// 大部分接口走明文 `/api/`（表单 POST + Cookie），播放地址和分享到动态走 XEAPI，
/// 歌词、收藏等走 EAPI，少数网页端才放行的走 WEAPI。各传输方式用的客户端身份见「传输」一节。
/// 只依赖 Cookie 里的 `MUSIC_U` 识别账号；没有 Cookie 时仍可搜索、播放免费歌曲。
class NeteaseApi {
  /// [deviceId] 是本机保存的设备号，不传时每个实例随机一个。
  NeteaseApi({
    http.Client? client,
    Map<String, String> cookies = const {},
    Random? random,
    String? deviceId,
  }) : _client = client ?? http.Client(),
       _cookies = Map.of(cookies),
       _random = random ?? Random(),
       _deviceId = deviceId ?? ClientProfile.newDeviceId(random);

  static const _timeout = Duration(seconds: 15);

  final http.Client _client;
  final Random _random;
  final String _deviceId;
  Map<String, String> _cookies;

  Map<String, String> get cookies => Map.unmodifiable(_cookies);
  set cookies(Map<String, String> value) {
    final before = deviceId;
    _cookies = Map.of(value);
    // XEAPI 公钥和设备号绑定，设备号变了要重取。
    if (deviceId != before) _xeapiKey = null;
  }

  /// 所有请求共用的设备号：用户 Cookie 里带了 `deviceId` 就用它，否则用本机保存的。
  String get deviceId => _str(_cookies['deviceId']) ?? _deviceId;

  bool get hasLoginCookie => (_cookies['MUSIC_U'] ?? '').isNotEmpty;

  void close() => _client.close();

  // ---------------------------------------------------------------- 账号

  /// 当前 Cookie 对应的账号；未登录或 Cookie 失效时返回 null。
  Future<UserProfile?> account() async {
    final data = await _api('https://music.163.com/api/nuser/account/get', const {});
    final profile = data['profile'];
    if (profile is! Map) return null;
    return UserProfile(
      userId: _int(profile['userId']),
      nickname: '${profile['nickname'] ?? ''}',
      avatarUrl: _str(profile['avatarUrl']),
      vipType: _int(profile['vipType']),
    );
  }

  // ---------------------------------------------------------------- 扫码登录
  //
  // 登录接口不带用户 Cookie。成功后网易云通过 Set-Cookie 下发 MUSIC_U 等字段，
  // 调用方拿到后交给 AccountController 验证并保存。

  /// 申请一个扫码登录用的 key。
  Future<String> qrKey() async {
    final data = await _api('https://music.163.com/api/login/qrcode/unikey', const {
      'type': '3',
    }, anonymous: true);
    final key = _str(data['unikey']);
    if (key == null) throw const ApiException('获取二维码失败');
    return key;
  }

  /// 二维码内容：用网易云音乐 App 扫这个地址。
  static String qrContent(String key) => 'https://music.163.com/login?codekey=$key';

  /// 查询扫码状态。800 过期、801 等待扫码、802 已扫码待确认、803 登录成功（带 Cookie）。
  Future<QrCheck> qrCheck(String key) async {
    final res = await _post(
      Uri.parse('https://music.163.com/api/login/qrcode/client/login'),
      {'key': key, 'type': '3'},
      ClientProfile.pc,
      anonymous: true,
    );
    final data = _decodeJson(utf8.decode(res.bodyBytes));
    final code = _int(data['code']);
    final status = switch (code) {
      800 => QrStatus.expired,
      801 => QrStatus.waiting,
      802 => QrStatus.scanned,
      803 => QrStatus.confirmed,
      _ => throw ApiException(_str(data['message']) ?? '扫码状态查询失败', code: code),
    };
    return QrCheck(
      status: status,
      nickname: _str(data['nickname']),
      avatarUrl: _https(_str(data['avatarUrl'])),
      cookies: status == QrStatus.confirmed ? parseSetCookie(res.headers['set-cookie']) : const {},
    );
  }

  // ---------------------------------------------------------------- 搜索 / 详情

  /// 输入时的联想词（像搜索引擎的下拉补全）。
  Future<List<String>> searchKeywords(String keyword) async {
    final data = await _api('https://music.163.com/api/search/suggest/keyword', {'s': keyword});
    final r = data['result'];
    return [
      if (r is Map)
        for (final m in _list(r['allMatch']))
          if (m is Map) ?_str(m['keyword']),
    ];
  }

  /// 输入时的快速结果：几首歌、歌手、专辑、歌单。
  Future<SearchSuggestion> searchSuggest(String keyword) async {
    final data = await _api('https://music.163.com/api/search/suggest/web', {'s': keyword});
    final r = data['result'];
    if (r is! Map) return const SearchSuggestion();
    // 联想接口里的歌曲是旧格式（artists / album），没有封面，再批量取一次详情补上；
    // 取不到就用原来的。
    var songs = [for (final s in _list(r['songs'])) ?parseSong(s)];
    if (songs.isNotEmpty) {
      try {
        final detailed = {
          for (final s in await songDetails([for (final s in songs) s.id])) s.id: s,
        };
        songs = [for (final s in songs) detailed[s.id] ?? s];
      } catch (_) {}
    }
    return SearchSuggestion(
      songs: songs,
      artists: [for (final a in _list(r['artists'])) ?_parseArtist(a)],
      albums: [for (final a in _list(r['albums'])) ?_parseAlbum(a)],
      playlists: [for (final p in _list(r['playlists'])) ?_parsePlaylist(p)],
    );
  }

  Future<({List<Song> songs, int total})> searchSongs(
    String keyword, {
    int limit = 30,
    int offset = 0,
  }) async {
    final data = await _api('https://music.163.com/api/cloudsearch/pc', {
      's': keyword,
      'type': '1',
      'limit': '$limit',
      'offset': '$offset',
    });
    final result = data['result'];
    if (result is! Map) return (songs: const <Song>[], total: 0);
    final songs = [for (final s in _list(result['songs'])) ?parseSong(s)];
    return (songs: songs, total: _int(result['songCount']));
  }

  /// 批量取歌曲详情，按 [ids] 的顺序返回；查不到的会被跳过。
  Future<List<Song>> songDetails(List<String> ids) async {
    final byId = <String, Song>{};
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, min(i + 500, ids.length));
      final data = await _api('https://music.163.com/api/v3/song/detail', {
        'c': jsonEncode([
          for (final id in chunk) {'id': int.parse(id), 'v': 0},
        ]),
      });
      for (final s in _list(data['songs'])) {
        if (parseSong(s) case final song?) byId[song.id] = song;
      }
    }
    return [for (final id in ids) ?byId[id]];
  }

  /// 这首歌实际提供的音质档位（与账号权益无关），从低到高。
  Future<List<QualityInfo>> qualities(String songId) async {
    final data = await _api('https://interface.music.163.com/api/song/music/detail/get', {
      'songId': songId,
    });
    final detail = data['data'];
    if (detail is! Map) return const [];
    return [
      for (final q in AudioQuality.values)
        if (detail[q.detailKey] case final Map<Object?, Object?> m)
          QualityInfo(
            quality: q,
            bitrate: _int(m['br']),
            size: _int(m['size']),
            sampleRate: m['sr'] == null ? null : _int(m['sr']),
          ),
    ];
  }

  /// 取播放地址。没有版权、需要购买或会员时返回 null。
  ///
  /// 网易云现在只给安卓端 XEAPI 加密的请求下发无损以上的地址，统一走 XEAPI。
  Future<SongUrl?> songUrl(String songId, AudioQuality quality) async {
    final data = await _xeapi('/api/song/enhance/player/url/v1', {
      'ids': '[$songId]',
      'level': quality.level,
      'encodeType': quality == AudioQuality.dolby ? 'mp4' : 'flac',
      if (quality == AudioQuality.sky) 'immerseType': 'c51',
    });
    final entries = _list(data['data']);
    if (entries.isEmpty) return null;
    final entry = entries.first as Map;
    final url = _str(entry['url']);
    if (url == null) return null;
    final trial = entry['freeTrialInfo'];
    return SongUrl(
      url: url,
      quality: AudioQuality.fromLevel(_str(entry['level'])),
      trial: trial is Map
          ? (
              start: Duration(milliseconds: _int(trial['start'])),
              end: Duration(milliseconds: _int(trial['end'])),
            )
          : null,
    );
  }

  /// 原始歌词文本：`lrc` 逐行原文、`yrc` 逐字原文、`tlyric` 翻译、`romalrc` 罗马音、
  /// `ytlrc` / `yromalrc` 与逐字歌词对齐的翻译 / 罗马音。缺的字段为空串。
  Future<Map<String, String>> lyricTexts(String songId) async {
    final data = await _eapi(
      '/api/song/lyric/v1',
      {
        'id': int.parse(songId),
        'cp': false,
        'lv': -1,
        'tv': -1,
        'rv': -1,
        'yv': -1,
        'ytv': -1,
        'yrv': -1,
      },
      host: 'https://interface.music.163.com',
      encryptedResponse: true,
    );
    String text(String key) => switch (data[key]) {
      final Map<Object?, Object?> m => '${m['lyric'] ?? ''}'.replaceAll('\u0000', '').trim(),
      _ => '',
    };
    return {
      for (final k in const ['lrc', 'yrc', 'tlyric', 'romalrc', 'ytlrc', 'yromalrc']) k: text(k),
    };
  }

  // ---------------------------------------------------------------- 歌单 / 喜欢

  Future<List<Playlist>> userPlaylists(int userId) async {
    final data = await _api('https://music.163.com/api/user/playlist', {
      'uid': '$userId',
      'limit': '1000',
      'offset': '0',
      'includeVideo': 'true',
    });
    return [for (final p in _list(data['playlist'])) ?_parsePlaylist(p)];
  }

  /// 歌单信息和全部歌曲。
  Future<({Playlist playlist, List<Song> tracks})> playlistDetail(String id) async {
    final (:playlist, :ids) = await playlistTrackIds(id);
    final tracks = await songDetails(ids);
    // 没有封面的歌单用第一首歌的封面，和官方客户端一致。
    final cover =
        playlist.coverUrl ?? tracks.where((t) => t.coverUrl != null).firstOrNull?.coverUrl;
    return (playlist: playlist.withCover(cover), tracks: tracks);
  }

  /// 歌单信息和全部歌曲的 id（按歌单顺序）。只一个请求，比取全部歌曲详情快得多，
  /// 用来和本地缓存比对增删。
  Future<({Playlist playlist, List<String> ids})> playlistTrackIds(String id) async {
    final data = await _api('https://music.163.com/api/v6/playlist/detail', {'id': id, 'n': '0'});
    final raw = data['playlist'];
    final playlist = raw is Map ? _parsePlaylist(raw) : null;
    if (playlist == null) throw const ApiException('歌单不存在或无权查看');
    return (
      playlist: playlist,
      ids: [
        for (final t in _list((raw as Map)['trackIds']))
          if (t is Map && t['id'] != null) '${t['id']}',
      ],
    );
  }

  /// 歌单第一首歌的封面：歌单本身没有封面或封面加载失败时用它代替。只取一首，不拉全部歌曲。
  Future<String?> playlistFirstCover(String id) async {
    final data = await _api('https://music.163.com/api/v6/playlist/detail', {'id': id, 'n': '1'});
    final raw = data['playlist'];
    if (raw is! Map) return null;
    for (final t in _list(raw['tracks'])) {
      if (parseSong(t)?.coverUrl case final url?) return url;
    }
    final ids = [
      for (final t in _list(raw['trackIds']).take(1))
        if (t is Map && t['id'] != null) '${t['id']}',
    ];
    if (ids.isEmpty) return null;
    return (await songDetails(ids)).firstOrNull?.coverUrl;
  }

  Future<Set<String>> likedSongIds(int userId) async {
    final data = await _api('https://music.163.com/api/song/like/get', {'uid': '$userId'});
    return {for (final id in _list(data['ids'])) '$id'};
  }

  Future<void> setLiked(String songId, bool liked) => _eapi('/api/radio/like', {
    'alg': 'itembased',
    'trackId': int.parse(songId),
    'like': liked,
    'time': '3',
  });

  /// 往自己的歌单里加歌。网易云对这个接口有风控，异常网络环境下会返回 -462。
  Future<void> addToPlaylist(String playlistId, List<String> songIds) =>
      _manipulateTracks('add', playlistId, songIds);

  /// 从自己的歌单里删歌。
  Future<void> removeFromPlaylist(String playlistId, List<String> songIds) =>
      _manipulateTracks('del', playlistId, songIds);

  /// 和 api-enhanced 的 playlist_tracks 一样先走 EAPI，不通再走明文。
  Future<void> _manipulateTracks(String op, String playlistId, List<String> songIds) {
    final form = {
      'op': op,
      'pid': playlistId,
      'trackIds': jsonEncode([for (final id in songIds) int.parse(id)]),
      'imme': 'true',
    };
    return _withFallback(
      () => _eapi('/api/playlist/manipulate/tracks', form),
      () => _api('https://music.163.com/api/playlist/manipulate/tracks', form),
    );
  }

  /// 收藏 / 取消收藏别人的歌单。和 api-enhanced 的 playlist_subscribe 一样先走 EAPI。
  Future<void> setPlaylistSubscribed(String playlistId, bool subscribed) {
    final path = '/api/playlist/${subscribed ? 'subscribe' : 'unsubscribe'}';
    return _withFallback(
      () => _eapi(path, {'id': playlistId}),
      () => _api('https://music.163.com$path', {'id': playlistId}),
    );
  }

  // ---------------------------------------------------------------- 歌单管理
  //
  // 接口参考 api-enhanced 的 playlist_create / playlist_delete / playlist_*_update /
  // playlist_cover_update，都需要登录。

  /// 新建歌单，返回新歌单（接口没给时为 null）。[private] 为 true 时是隐私歌单。
  /// [shared] 为 true 时是共建歌单（官方叫共享歌单，type 为 SHARED），可以邀请好友一起加歌。
  Future<Playlist?> createPlaylist(String name, {bool private = false, bool shared = false}) async {
    final data = await _weapi('/api/playlist/create', {
      'name': name,
      'privacy': private ? '10' : '0',
      'type': shared ? 'SHARED' : 'NORMAL',
    });
    return _parsePlaylist(data['playlist']);
  }

  /// 删除自己的歌单。
  Future<void> deletePlaylist(String id) => _weapi('/api/playlist/remove', {'ids': '[$id]'});

  /// 改歌单名。
  Future<void> renamePlaylist(String id, String name) =>
      _eapi('/api/playlist/update/name', {'id': id, 'name': name});

  /// 改歌单简介（空字符串表示清空）。
  Future<void> setPlaylistDescription(String id, String desc) =>
      _eapi('/api/playlist/desc/update', {'id': id, 'desc': desc});

  /// 换歌单封面：先把图片传到网易云的图床，再把图片 id 设成封面。返回新封面地址。
  Future<String> setPlaylistCover(String id, List<int> image) async {
    final img = await uploadImage(image);
    await _weapi('/api/playlist/cover/update', {'id': id, 'coverImgId': img.id});
    return img.url;
  }

  /// 上传一张图片（JPEG / PNG）到网易云图床（NOS），返回图片 id 和地址。
  Future<({String id, String url})> uploadImage(List<int> image) async {
    final png = image.length > 4 && image[0] == 0x89 && image[1] == 0x50 && image[2] == 0x4E;
    final ext = png ? 'png' : 'jpg';
    final alloc = await _weapi('/api/nos/token/alloc', {
      'bucket': 'yyimgs',
      'ext': ext,
      'filename': 'cover.$ext',
      'local': 'false',
      'nos_product': '0',
      'return_body': '{"code":200,"size":"\$(ObjectSize)"}',
      'type': 'other',
    });
    final r = alloc['result'];
    if (r is! Map || _str(r['objectKey']) == null || _str(r['token']) == null) {
      throw const ApiException('获取上传凭证失败');
    }
    final key = r['objectKey'] as String;
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('https://nosup-hz1.127.net/yyimgs/$key?offset=0&complete=true&version=1.0'),
            headers: {
              'x-nos-token': r['token'] as String,
              'Content-Type': png ? 'image/png' : 'image/jpeg',
            },
            body: image,
          )
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw ApiException('图片上传失败：$e');
    }
    if (res.statusCode != 200) {
      throw ApiException('图片上传失败：HTTP ${res.statusCode}', code: res.statusCode);
    }
    return (id: '${r['docId']}', url: 'https://p1.music.126.net/$key');
  }

  // ---------------------------------------------------------------- 推荐 / 发现

  /// 每日推荐歌曲（需要登录）。
  Future<List<Song>> dailySongs() async {
    final data = await _api('https://music.163.com/api/v3/discovery/recommend/songs', const {});
    final d = data['data'];
    return [
      if (d is Map)
        for (final s in _list(d['dailySongs'])) ?parseSong(s),
    ];
  }

  /// 私人 FM 的下一批（一次约 3 首，需要登录）。
  Future<List<Song>> personalFm() async {
    final data = await _api('https://music.163.com/api/v1/radio/get', const {});
    return [for (final s in _list(data['data'])) ?parseSong(s)];
  }

  /// 私人 FM 里标记「不喜欢」。和 api-enhanced 的 fm_trash 一样先走 WEAPI，不通再走明文。
  Future<void> fmTrash(String songId) => _withFallback(
    () => _weapi('/api/radio/trash/add?alg=RT&songId=$songId&time=25', {'songId': songId}),
    () => _api('https://music.163.com/api/radio/trash/add?alg=RT&songId=$songId&time=25', {
      'songId': songId,
    }),
  );

  /// 推荐歌单。登录后是每日推荐歌单，未登录是通用推荐。
  Future<List<Playlist>> recommendPlaylists({int limit = 30}) async {
    if (hasLoginCookie) {
      final data = await _api(
        'https://music.163.com/api/v1/discovery/recommend/resource',
        const {},
      );
      final list = [for (final p in _list(data['recommend'])) ?_parseRecommend(p)];
      if (list.isNotEmpty) return list.take(limit).toList();
    }
    final data = await _api('https://music.163.com/api/personalized/playlist', {
      'limit': '$limit',
      'total': 'true',
      'n': '1000',
    });
    return [for (final p in _list(data['result'])) ?_parseRecommend(p)];
  }

  /// 官方首页的推荐：歌曲推荐板块（HOMEPAGE_BLOCK_STYLE_RCMD，「根据你喜爱的歌曲推荐」）
  /// 和雷达歌单板块（HOMEPAGE_BLOCK_MGC_PLAYLIST）。登录后按口味推荐，未登录是通用推荐。
  /// 每次调用歌曲推荐都会换一批。
  Future<HomeFeed> homeFeed() async {
    final data = await _api('https://music.163.com/api/homepage/block/page', {
      'refresh': 'true',
      'cursor': '',
    });
    final d = data['data'];
    final blocks = _list(d is Map ? d['blocks'] : null);
    Map<Object?, Object?>? block(String code) =>
        blocks.firstWhere((b) => b is Map && b['blockCode'] == code, orElse: () => null)
            as Map<Object?, Object?>?;
    String? title(Map<Object?, Object?>? b) {
      final ui = b?['uiElement'];
      final sub = ui is Map ? ui['subTitle'] : null;
      return sub is Map ? _str(sub['title']) : null;
    }

    Iterable<Object?> resources(Map<Object?, Object?>? b) => [
      for (final c in _list(b?['creatives']))
        if (c is Map) ..._list(c['resources']),
    ];

    final songs = block('HOMEPAGE_BLOCK_STYLE_RCMD');
    final radar = block('HOMEPAGE_BLOCK_MGC_PLAYLIST');
    return HomeFeed(
      songTitle: title(songs) ?? _songRcmdTitle,
      songs: [for (final r in resources(songs)) ?_parseSongRcmd(r)],
      radarTitle: title(radar) ?? '雷达歌单',
      radar: [for (final r in resources(radar)) ?_parseRcmdPlaylist(r)],
    );
  }

  static Playlist? _parseRcmdPlaylist(Object? r) {
    if (r is! Map || r['resourceType'] != 'list') return null;
    final id = _str('${r['resourceId'] ?? ''}');
    final ui = r['uiElement'];
    final main = ui is Map ? ui['mainTitle'] : null;
    final image = ui is Map ? ui['image'] : null;
    final ext = r['resourceExtInfo'];
    final name = main is Map ? _str(main['title']) : null;
    if (id == null || name == null) return null;
    return Playlist(
      id: id,
      name: name,
      playCount: ext is Map ? _int(ext['playCount']) : 0,
      coverUrl: image is Map ? _https(_str(image['imageUrl'])) : null,
    );
  }

  static const _songRcmdTitle = '根据你喜爱的歌曲推荐';

  static SongRcmd? _parseSongRcmd(Object? r) {
    if (r is! Map || r['resourceType'] != 'song') return null;
    final ext = r['resourceExtInfo'];
    if (ext is! Map) return null;
    final song = parseSong(ext['song']) ?? parseSong(ext['songData']);
    if (song == null) return null;
    final ui = r['uiElement'];
    final sub = ui is Map ? ui['subTitle'] : null;
    final labels = ui is Map ? _list(ui['labelTexts']) : const [];
    // 推荐理由：优先标签；副标题是热评摘录（songRcmdFromComment）时太长，不当标签用。
    final tag =
        labels.map((e) => _str(e)).nonNulls.firstOrNull ??
        (sub is Map && sub['titleType'] != 'songRcmdFromComment' ? _str(sub['title']) : null);
    final privilege = ext['songPrivilege'];
    final level = privilege is Map ? _str(privilege['playMaxBrLevel']) : null;
    return SongRcmd(
      song: song,
      tag: tag,
      quality: switch (level) {
        'hires' => 'Hi-Res',
        'lossless' => 'SQ',
        _ => null,
      },
    );
  }

  /// 新歌速递：最近一周上架的新歌，约 100 首。[area] 是地区，见 [newSongAreas]。
  Future<List<Song>> newSongExpress({int area = 0}) async {
    final data = await _api('https://music.163.com/api/v1/discovery/new/songs', {
      'areaId': '$area',
      'total': 'true',
    });
    return [for (final s in _list(data['data'])) ?parseSong(s)];
  }

  /// 新歌速递的地区：名称和 areaId。
  static const newSongAreas = [('全部', 0), ('华语', 7), ('欧美', 96), ('日本', 8), ('韩国', 16)];

  /// 官方排行榜。[Playlist.description] 是更新频率。
  Future<List<Playlist>> toplists() async {
    final data = await _api('https://music.163.com/api/toplist', const {});
    return [for (final p in _list(data['list'])) ?_parsePlaylist(p)];
  }

  /// 歌单广场：分类 [cat]（「全部」或分类名）下的热门歌单，按 [offset] 翻页。
  /// 参考 api-enhanced 的 top_playlist。
  Future<({List<Playlist> items, bool more})> playlistSquare({
    String cat = '全部',
    int limit = 30,
    int offset = 0,
  }) async {
    final data = await _weapi('/api/playlist/list', {
      'cat': cat,
      'order': 'hot',
      'limit': limit,
      'offset': offset,
      'total': true,
    });
    final items = [for (final p in _list(data['playlists'])) ?_parsePlaylist(p)];
    return (items: items, more: data['more'] == true);
  }

  /// 精品歌单。翻页用上一页最后一个歌单的 `updateTime`（[before]），第一页传 0。
  /// 参考 api-enhanced 的 top_playlist_highquality。
  Future<({List<Playlist> items, bool more, int lastTime})> highQualityPlaylists({
    String cat = '全部',
    int limit = 30,
    int before = 0,
  }) async {
    final data = await _weapi('/api/playlist/highquality/list', {
      'cat': cat,
      'limit': limit,
      'lasttime': before,
      'total': true,
    });
    final items = [for (final p in _list(data['playlists'])) ?_parsePlaylist(p)];
    return (items: items, more: data['more'] == true, lastTime: _int(data['lasttime']));
  }

  /// 歌单分类：热门标签。参考 api-enhanced 的 playlist_hot。
  Future<List<String>> playlistHotTags() async {
    final data = await _weapi('/api/playlist/hottags', const {});
    return [
      for (final t in _list(data['tags']))
        if (t is Map) ?_str(t['name']),
    ];
  }

  /// 歌单分类：全部分类，按大类（语种、风格……）分组。参考 api-enhanced 的 playlist_catlist。
  Future<List<({String group, List<String> names})>> playlistCategories() async {
    final data = await _weapi('/api/playlist/catalogue', const {});
    final groups = data['categories'];
    final byGroup = <String, List<String>>{};
    for (final c in _list(data['sub'])) {
      if (c is! Map) continue;
      final name = _str(c['name']);
      if (name == null) continue;
      byGroup.putIfAbsent('${c['category']}', () => []).add(name);
    }
    return [
      for (final MapEntry(:key, :value) in byGroup.entries)
        (group: groups is Map ? '${groups[key] ?? key}' : key, names: value),
    ];
  }

  /// 歌曲百科（官方播放页「百科」）。参考 api-enhanced 的 song_wiki_summary。
  Future<SongWiki> songWiki(String id) async {
    final data = await _eapi('/api/song/play/about/block/page', {'songId': id});
    return parseSongWiki(data);
  }

  /// 不展示的百科条目：评论（纯听歌版没有评论）、乐谱（没有乐谱页）。
  static const _skippedWikiItems = {'songComment', 'sheet'};

  /// 解析百科接口的返回。单独拿出来方便测试。
  static SongWiki parseSongWiki(Map<String, Object?> data) {
    final d = data['data'];
    final blocks = _list(d is Map ? d['blocks'] : null);
    Map<Object?, Object?>? block(String code) =>
        blocks.firstWhere((b) => b is Map && b['code'] == code, orElse: () => null)
            as Map<Object?, Object?>?;
    String? title(Object? ui, [String key = 'mainTitle']) {
      if (ui is! Map) return null;
      final t = ui[key];
      return t is Map ? _str(t['title']) : null;
    }

    String? image(Object? ui) {
      if (ui is! Map) return null;
      final first = _list(ui['images']).firstOrNull;
      return first is Map ? _https(_str(first['imageUrl'])) : null;
    }

    final facts = <({String label, List<String> values})>[];
    for (final c in _list(block('SONG_PLAY_ABOUT_SONG_BASIC')?['creatives'])) {
      if (c is! Map || _skippedWikiItems.contains(c['creativeType'])) continue;
      final label = title(c['uiElement']);
      if (label == null) continue;
      final ui = c['uiElement'];
      final values = <String>[
        for (final r in _list(c['resources']))
          if (r is Map) ?title(r['uiElement']),
        if (ui is Map)
          for (final l in _list(ui['textLinks']))
            if (l is Map) ?_str(l['text']),
      ];
      if (values.isNotEmpty) facts.add((label: label, values: values));
    }

    final similar = <SongBrief>[
      for (final c in _list(block('SONG_PLAY_ABOUT_SIMILAR_SONG')?['creatives']))
        if (c is Map)
          for (final r in _list(c['resources']))
            if (r is Map && r['resourceType'] == 'SONG' && _str('${r['resourceId'] ?? ''}') != null)
              if (title(r['uiElement']) case final name?)
                SongBrief(
                  id: '${r['resourceId']}',
                  title: name,
                  artist: switch (r['uiElement']) {
                    final Map<Object?, Object?> ui =>
                      _list(ui['subTitles'])
                          .whereType<Map<Object?, Object?>>()
                          .map((t) => _str(t['title']))
                          .nonNulls
                          .join(' / '),
                    _ => '',
                  },
                  coverUrl: image(r['uiElement']),
                ),
    ];

    final playlists = <Playlist>[
      for (final c in _list(block('SONG_PLAY_ABOUT_RELATED_PLAYLIST')?['creatives']))
        if (c is Map)
          for (final r in _list(c['resources']))
            if (r is Map && r['resourceType'] == 'PLAYLIST' && r['resourceId'] != null)
              if (title(r['uiElement']) case final name?)
                Playlist(
                  id: '${r['resourceId']}',
                  name: name,
                  playCount: switch (r['resourceExt']) {
                    final Map<Object?, Object?> ext => _int(ext['playCount']),
                    _ => 0,
                  },
                  coverUrl: image(r['uiElement']),
                ),
    ];
    return SongWiki(facts: facts, similar: similar, playlists: playlists);
  }

  /// 热搜词。
  Future<List<String>> hotSearches() async {
    final data = await _api('https://music.163.com/api/hotsearchlist/get', const {});
    return [
      for (final h in _list(data['data']))
        if (h is Map) ?_str(h['searchWord']),
    ];
  }

  // ---------------------------------------------------------------- 听歌记录

  /// 听歌排行：[weekly] 为 true 是最近一周，否则是所有时间。
  Future<List<({Song song, int playCount})>> playRecord(int userId, {bool weekly = true}) async {
    final data = await _api('https://music.163.com/api/v1/play/record', {
      'uid': '$userId',
      'type': weekly ? '1' : '0',
    });
    return [
      for (final r in _list(data[weekly ? 'weekData' : 'allData']))
        if (r is Map)
          if (parseSong(r['song']) case final song?) (song: song, playCount: _int(r['playCount'])),
    ];
  }

  /// 最近播放的歌曲（需要登录）。
  Future<List<Song>> recentSongs({int limit = 300}) async {
    final data = await _api('https://music.163.com/api/play-record/song/list', {'limit': '$limit'});
    final d = data['data'];
    return [
      if (d is Map)
        for (final r in _list(d['list']))
          if (r is Map) ?parseSong(r['data']),
    ];
  }

  /// 播放日志（需要登录）。日志接口只认客户端身份：走 EAPI、发到 clientlog 域名、
  /// 设备信息用 macOS 客户端的；网页 `/api/` 明文接口上报会返回成功但不生效。
  ///
  /// [startPlay] 在开始放一首歌时发 `startplay`，让它出现在官方客户端的「最近播放」；
  /// [scrobble] 在听完 / 切走时发 `play`，给听歌排行计数。[sourceId] 是来源歌单 / 专辑 id。
  Future<void> startPlay(String songId, {String? sourceId}) =>
      _playLog('startplay', sourceId, {'id': int.parse(songId), 'type': 'song'});

  /// [seconds] 是实际听了多久。
  Future<void> scrobble(String songId, {required int seconds, String? sourceId}) =>
      _playLog('play', sourceId, {
        'download': 0,
        'end': 'playend',
        'id': int.parse(songId),
        'sourceId': sourceId ?? '',
        'time': seconds,
        'type': 'song',
        'wifi': 0,
        'source': 'list',
      });

  Future<void> _playLog(String action, String? sourceId, Map<String, Object?> json) => _eapi(
    '/api/feedback/weblog',
    {
      'logs': jsonEncode([
        {
          'action': action,
          'json': {...json, 'mainsite': '1', 'mainsiteWeb': '1', 'content': 'id=${sourceId ?? ''}'},
        },
      ]),
    },
    host: 'https://clientlog.music.163.com',
    profile: ClientProfile.osx,
  );

  // ---------------------------------------------------------------- 评论

  /// 一页评论。第一页 [cursor] 传 null，之后传上一页返回的 [CommentPage.cursor]。
  Future<CommentPage> comments(
    String threadId, {
    CommentSort sort = CommentSort.hot,
    int pageNo = 1,
    int pageSize = 20,
    String? cursor,
  }) async {
    final data = await _api('https://music.163.com/api/v2/resource/comments', {
      'threadId': threadId,
      'pageNo': '$pageNo',
      'pageSize': '$pageSize',
      'showInner': 'true',
      'sortType': '${sort.type}',
      'cursor': cursor ?? '0',
    });
    final d = data['data'];
    if (d is! Map) return const CommentPage(comments: [], total: 0, hasMore: false, cursor: '0');
    return CommentPage(
      comments: [for (final c in _list(d['comments'])) ?parseComment(c)],
      total: _int(d['totalCount']),
      hasMore: d['hasMore'] == true,
      cursor: '${d['cursor'] ?? '0'}',
    );
  }

  /// 楼中楼：某条评论下的回复。第一页 [cursor] 传 null。
  Future<CommentPage> floorComments(
    String threadId,
    int parentId, {
    int limit = 20,
    String? cursor,
  }) async {
    final data = await _api('https://music.163.com/api/resource/comment/floor/get', {
      'parentCommentId': '$parentId',
      'threadId': threadId,
      'time': cursor ?? '-1',
      'limit': '$limit',
    });
    final d = data['data'];
    if (d is! Map) return const CommentPage(comments: [], total: 0, hasMore: false, cursor: '-1');
    return CommentPage(
      comments: [for (final c in _list(d['comments'])) ?parseComment(c)],
      total: _int(d['totalCount']),
      hasMore: d['hasMore'] == true,
      cursor: '${d['time'] ?? '-1'}',
    );
  }

  /// 给评论点赞 / 取消点赞（需要登录）。和 api-enhanced 的 comment_like 一样先走 WEAPI。
  Future<void> likeComment(String threadId, int commentId, bool like) {
    final path = '/api/v1/comment/${like ? 'like' : 'unlike'}';
    final form = {'threadId': threadId, 'commentId': '$commentId'};
    return _withFallback(() => _weapi(path, form), () => _api('https://music.163.com$path', form));
  }

  /// 发评论；[replyTo] 不为 null 时是回复那条评论。返回新评论（接口没给时为 null）。
  ///
  /// 和 api-enhanced 的 comment 一样先走 EAPI，不通再走明文。
  /// api-enhanced 还带了易盾 v2 token（要跑网页版 SDK），这里没带。
  Future<Comment?> postComment(String threadId, String content, {int? replyTo}) async {
    final path = '/api/resource/comments/${replyTo == null ? 'add' : 'reply'}';
    final form = {'threadId': threadId, 'content': content, 'commentId': ?replyTo?.toString()};
    final data = await _withFallback(
      () => _eapi(path, form),
      () => _api('https://music.163.com$path', form),
    );
    return parseComment(data['comment']);
  }

  /// 删除自己的评论。先走 EAPI，不通再走明文。
  Future<void> deleteComment(String threadId, int commentId) {
    const path = '/api/resource/comments/delete';
    final form = {'threadId': threadId, 'commentId': '$commentId'};
    return _withFallback(() => _eapi(path, form), () => _api('https://music.163.com$path', form));
  }

  // ---------------------------------------------------------------- 用户

  /// 用户主页资料。这个接口用 GET 会被风控（-462），要用 POST。
  Future<UserDetail> userDetail(int userId) async {
    final data = await _api('https://music.163.com/api/v1/user/detail/$userId', const {});
    final p = data['profile'];
    if (p is! Map) throw const ApiException('用户不存在');
    final artistId = _int(p['artistId']);
    return UserDetail(
      userId: _int(p['userId']),
      nickname: '${p['nickname'] ?? ''}',
      avatarUrl: _https(_str(p['avatarUrl'])),
      backgroundUrl: _https(_str(p['backgroundUrl'])),
      signature: _str('${p['signature'] ?? ''}'.trim()),
      identity: _str(p['description']) ?? _str(p['detailDescription']),
      level: _int(data['level']),
      listenSongs: _int(data['listenSongs']),
      follows: _int(p['follows']),
      followeds: _int(p['followeds']),
      artistId: artistId > 0 ? '$artistId' : null,
      playRecordPublic: data['peopleCanSeeMyPlayRecord'] != false,
      followed: p['followed'] == true,
    );
  }

  // ---------------------------------------------------------------- 用户状态
  //
  // 接口参考 api-enhanced 的 user_social_status*（默认走 EAPI），都需要登录。

  /// [userId] 当前的状态；没设置时返回 null。
  Future<UserStatus?> userStatus(int userId) async {
    final data = await _eapi('/api/social/user/status', {'visitorId': '$userId'});
    return parseUserStatus(data['data']);
  }

  /// 可以设置的状态列表。
  Future<List<UserStatus>> statusOptions() async {
    final data = await _eapi('/api/social/user/status/support', const {});
    final raw = data['data'];
    final list = raw is Map ? raw['list'] : raw;
    return [for (final s in _list(list)) ?parseUserStatus(s)];
  }

  /// 设置自己的状态。返回服务端的提示（例如「将展示7天」），没有为 null。
  Future<String?> setStatus(UserStatus status) async {
    final data = await _eapi('/api/social/user/status/edit', {
      'content': jsonEncode({
        'type': status.type,
        'iconUrl': status.iconUrl,
        'content': status.content,
        'actionUrl': status.actionUrl,
      }),
    });
    return _str(data['data']);
  }

  /// 和我状态相同的人。
  Future<StatusRcmd> sameStatusUsers() async {
    final data = await _eapi('/api/social/user/status/rcmd', const {});
    final d = data['data'];
    if (d is! Map) return const StatusRcmd();
    return StatusRcmd(
      title: _str(d['rcmdTitle']),
      status: parseUserStatus(d['statusContentDTO']),
      users: [
        for (final u in _list(d['userRcmdInfoVOList']))
          if (u is Map && u['userId'] != null)
            StatusUser(
              userId: _int(u['userId']),
              nickname: '${u['nickName'] ?? u['nickname'] ?? ''}'.trim(),
              avatarUrl: _https(_str(u['avatarUrl'])),
              status: parseUserStatus(u['statusContentDTO']),
              tags: [
                for (final t in _list(u['tagRcmdVOList']))
                  if (t is Map) ?_str(t['name']),
              ],
            ),
      ],
    );
  }

  /// 状态有几种包法：直接是 `{type, iconUrl, content}`；或者外面再包一层，
  /// 状态在 `content`（对象或 JSON 字符串）/ `statusContentDTO` 里，歌在 `song`。
  /// 空对象（没设置状态）返回 null。
  static UserStatus? parseUserStatus(Object? raw) {
    if (raw is! Map) return null;
    final dto = raw['statusContentDTO'];
    final inner = dto is Map ? dto : _messageJson(raw['content']);
    final c = inner.isNotEmpty ? inner : raw;
    final content = '${c['content'] ?? ''}'.trim();
    final type = '${c['type'] ?? ''}'.trim();
    if (content.isEmpty && type.isEmpty) return null;
    final song = raw['song'] ?? c['song'];
    return UserStatus(
      type: type,
      content: content,
      iconUrl: _https(_str(c['iconUrl'])),
      actionUrl: _str(c['actionUrl']),
      desc: _str(c['desc']),
      canEdit: c['canEdit'] == true,
      song: song is Map ? parseSong(song) : null,
    );
  }

  // ---------------------------------------------------------------- 关注 / 粉丝

  /// 关注 / 取消关注（需要登录）。
  ///
  /// 网易云对官方 App 以外的关注请求常返回 250「关注异常」（网页版也是），取消关注正常。
  /// PC 客户端没有单独的关注接口，用的也是 `/api/user/follow/{id}`，只是加密方式和身份不同。
  /// 所以关注按顺序试：安卓 XEAPI（带易盾 token）→ PC EAPI → 网页 WEAPI（api-enhanced 的做法），
  /// 服务端拒绝才换下一种；遇到风控（-460 / -462）、登录失效或网络错误立即停，免得越试越被风控。
  /// 取消关注只走 WEAPI。
  Future<void> setFollowed(int userId, bool follow) {
    if (!follow) return _weapi('/api/user/delfollow/$userId', const {});
    final path = '/api/user/follow/$userId';
    return _firstAccepted([
      () async {
        final token = await antiCheatToken();
        await _xeapi(path, const {}, headers: {'X-antiCheatToken': ?token});
      },
      () => _eapi(path, const {}),
      () => _weapi(path, const {}),
    ]);
  }

  /// [userId] 关注的人，按 offset 翻页。
  Future<SocialUserPage> userFollows(int userId, {int offset = 0, int limit = 30}) async {
    final data = await _api('https://music.163.com/api/user/getfollows/$userId', {
      'offset': '$offset',
      'limit': '$limit',
      'order': 'true',
    });
    return SocialUserPage(
      users: [for (final u in _list(data['follow'])) ?parseSocialUser(u)],
      more: data['more'] == true,
    );
  }

  /// [userId] 的粉丝，按 offset 翻页。
  Future<SocialUserPage> userFolloweds(int userId, {int offset = 0, int limit = 30}) async {
    final data = await _eapi('/api/user/getfolloweds/$userId', {
      'userId': '$userId',
      'time': '0',
      'limit': '$limit',
      'offset': '$offset',
      'getcounts': 'true',
    });
    return SocialUserPage(
      users: [for (final u in _list(data['followeds'])) ?parseSocialUser(u)],
      more: data['more'] == true,
    );
  }

  // ---------------------------------------------------------------- 动态

  /// 关注的人的动态（「关注」页，需要登录）。下一页传上一页的 [EventPage.lasttime]。
  Future<EventPage> followFeed({int lasttime = -1, int limit = 20}) async {
    final data = await _api('https://music.163.com/api/v1/event/get', {
      'pagesize': '$limit',
      'lasttime': '$lasttime',
    });
    return _eventPage(data);
  }

  /// [userId] 发的动态。
  Future<EventPage> userEvents(int userId, {int lasttime = -1, int limit = 20}) async {
    final data = await _api('https://music.163.com/api/event/get/$userId', {
      'getcounts': 'true',
      'time': '$lasttime',
      'limit': '$limit',
      'total': 'false',
    });
    return _eventPage(data);
  }

  /// 给动态点赞 / 取消点赞（需要登录）。和 api-enhanced 的 resource_like 一样先走 WEAPI。
  Future<void> likeEvent(String threadId, bool like) {
    final path = '/api/resource/${like ? 'like' : 'unlike'}';
    return _withFallback(
      () => _weapi(path, {'threadId': threadId}),
      () => _api('https://music.163.com$path', {'threadId': threadId}),
    );
  }

  /// 删除自己的动态。和 api-enhanced 的 event_del 一样先走 WEAPI。
  Future<void> deleteEvent(int eventId) => _withFallback(
    () => _weapi('/api/event/delete', {'id': '$eventId'}),
    () => _api('https://music.163.com/api/event/delete', {'id': '$eventId'}),
  );

  /// 发动态（需要登录）。[type] 是附带资源的类型，[id] 是资源 id；纯文字动态不传。
  ///
  /// 接口参考 api-enhanced 的 share_resource：以安卓客户端身份走 XEAPI，带易盾反作弊 token。
  /// 网页端 / PC 身份分享歌曲会被拒（「当前版本不支持分享歌曲」）。
  /// XEAPI 失败（非登录问题）时退回明文接口再试一次，两次都失败报 XEAPI 的错误。
  Future<void> shareEvent(String msg, {ShareType type = ShareType.none, String id = ''}) {
    final form = {'type': type.value, 'msg': msg, 'id': id};
    return _withFallback(() async {
      final token = await antiCheatToken();
      await _xeapi('/api/share/friends/resource', form, headers: {'X-antiCheatToken': ?token});
    }, () => _api('https://music.163.com/api/share/friends/resource', form));
  }

  /// 易盾反作弊 token（每次取新的，不缓存）。取不到返回 null，由服务端决定是否放行。
  Future<String?> antiCheatToken() async {
    try {
      final res = await _client
          .get(Uri.parse('https://ac.dun.163yun.com/v3/b?pn=YD00000558929251'))
          .timeout(_timeout);
      final m = RegExp(r'\(\[(\d+),\d+,"([^"]+)"\]\)').firstMatch(utf8.decode(res.bodyBytes));
      return m != null && m.group(1) == '200' ? m.group(2) : null;
    } catch (_) {
      return null;
    }
  }

  /// 关注动态的列表字段叫 `event`，用户动态叫 `events`。
  EventPage _eventPage(Map<String, Object?> data) => EventPage(
    events: [for (final e in _list(data['events'] ?? data['event'])) ?parseEvent(e)],
    more: data['more'] == true,
    lasttime: _int(data['lasttime']),
  );

  // ---------------------------------------------------------------- 私信

  /// 私信会话列表（需要登录）。
  Future<({List<Conversation> items, bool more})> conversations({
    int offset = 0,
    int limit = 30,
  }) async {
    final data = await _api('https://music.163.com/api/msg/private/users', {
      'offset': '$offset',
      'limit': '$limit',
      'total': 'true',
    });
    return (
      items: [
        for (final m in _list(data['msgs']))
          if (m is Map)
            if (parseSocialUser(m['fromUser']) case final user?)
              Conversation(
                user: user,
                preview: _messagePreview(_messageJson(m['lastMsg'])),
                time: DateTime.fromMillisecondsSinceEpoch(_int(m['lastMsgTime'])),
                unread: _int(m['newMsgCount']),
              ),
      ],
      more: data['more'] == true,
    );
  }

  /// 和 [userId] 的私信记录。[before] 传当前最早一条的时间取更早的，第一页传 null。
  ///
  /// 走网页端的 WEAPI：网页端打开对话就是调这个，服务端会顺带把这个会话标成已读；
  /// 明文 `/api/` 只读记录不清未读，退出对话后红点还在。WEAPI 失败时退回明文接口。
  Future<MessageHistory> messageHistory(int userId, {DateTime? before, int limit = 30}) async {
    final form = {
      'userId': '$userId',
      'limit': '$limit',
      'time': '${before?.millisecondsSinceEpoch ?? 0}',
      'total': 'true',
    };
    final data = await _withFallback(
      () => _weapi('/api/msg/private/history', form),
      () => _api('https://music.163.com/api/msg/private/history', form),
    );
    final messages = [for (final m in _list(data['msgs'])) ?parsePrivateMessage(m)]
      ..sort((a, b) => a.time.compareTo(b.time));
    return MessageHistory(messages: messages, more: data['more'] == true);
  }

  /// 给 [userId] 发一条文字私信。
  Future<void> sendMessage(int userId, String text) =>
      _eapi('/api/msg/private/send', {'type': 'text', 'msg': text, 'userIds': '[$userId]'});

  /// 把一首歌私信给 [userId]，可以附一句话。
  Future<void> sendSong(int userId, String songId, {String text = ''}) => _eapi(
    '/api/msg/private/send',
    {'id': songId, 'msg': text, 'type': 'song', 'userIds': '[$userId]'},
  );

  // ---------------------------------------------------------------- 歌手 / 专辑

  /// 歌手信息和热门歌曲（最多 50 首）。
  Future<({Artist artist, List<Song> hotSongs})> artistDetail(String id) async {
    final data = await _api('https://music.163.com/api/v1/artist/$id', const {});
    final a = data['artist'];
    if (a is! Map) throw const ApiException('歌手不存在');
    return (
      artist: _parseArtist(a)!,
      hotSongs: [for (final s in _list(data['hotSongs'])) ?parseSong(s)],
    );
  }

  /// 关注 / 取消关注歌手。网页端歌手页的「收藏」就是这个接口，
  /// 和 App 里的「关注」是同一件事。参数参考 api-enhanced 的 artist_sub。
  ///
  /// 认证歌手的账号主页上那个「关注」（`/api/user/follow`）会被风控拦下，
  /// 所以有歌手 id 时都走这里。
  Future<void> setArtistFollowed(String artistId, bool follow) => _weapi(
    '/api/artist/${follow ? 'sub' : 'unsub'}',
    {'artistId': artistId, 'artistIds': '[$artistId]'},
  );

  /// 已关注（收藏）的歌手，按 [offset] 翻页。参考 api-enhanced 的 artist_sublist。
  Future<({List<Artist> items, bool more})> followedArtists({
    int limit = 50,
    int offset = 0,
  }) async {
    final data = await _weapi('/api/artist/sublist', {
      'limit': limit,
      'offset': offset,
      'total': true,
    });
    return (
      items: [for (final a in _list(data['data'])) ?_parseArtist(a)],
      more: data['hasMore'] == true,
    );
  }

  /// 歌手的全部歌曲：[byTime] 为 true 按发行时间从新到旧，否则按热度。
  /// 接口单页最多 100 首（再大会返回别人的歌），先取第一页拿到总数，剩下的几页并发取。
  Future<List<Song>> artistAllSongs(String id, {bool byTime = true, int maxSongs = 3000}) async {
    const page = 100;
    Future<({List<Song> songs, int total})> fetch(int offset) async {
      final data = await _api('https://music.163.com/api/v1/artist/songs', {
        'id': id,
        'offset': '$offset',
        'limit': '$page',
        'order': byTime ? 'time' : 'hot',
        'private_cloud': 'true',
        'work_type': '1',
      });
      return (
        songs: [for (final s in _list(data['songs'])) ?parseSong(s)],
        total: _int(data['total']),
      );
    }

    final first = await fetch(0);
    final total = min(first.total, maxSongs);
    final rest = <List<Song>>[];
    // 每批 4 个请求，别一下子打太多。
    final offsets = [for (var o = page; o < total; o += page) o];
    for (var i = 0; i < offsets.length; i += 4) {
      final batch = offsets.sublist(i, min(i + 4, offsets.length));
      rest.addAll([for (final r in await Future.wait(batch.map(fetch))) r.songs]);
    }
    final seen = <String>{};
    return [
      for (final s in [...first.songs, for (final r in rest) ...r])
        // 防御：只留这位歌手参与的歌，并去重。
        if ((s.artists.isEmpty || s.artists.any((a) => a.id == id)) && seen.add(s.id)) s,
    ];
  }

  /// 歌手的详细介绍，分段（标题 + 正文）。
  Future<List<({String title, String text})>> artistIntroduction(String id) async {
    final data = await _api('https://music.163.com/api/artist/introduction', {'id': id});
    return [
      for (final e in _list(data['introduction']))
        if (e is Map && _str(e['txt']) != null)
          (title: _str(e['ti']) ?? '', text: (e['txt'] as String).trim()),
    ];
  }

  /// 歌手头像。同一位歌手只请求一次（歌手选择面板等处用）。
  Future<String?> artistAvatar(String id) => _avatarCache[id] ??= artistDetail(id).then(
    (r) => r.artist.avatarUrl,
    onError: (Object _) {
      _avatarCache.remove(id);
      return null;
    },
  );

  final Map<String, Future<String?>> _avatarCache = {};

  /// 歌手的专辑，按发行时间从新到旧。
  Future<({List<Album> albums, bool more})> artistAlbums(
    String id, {
    int limit = 30,
    int offset = 0,
  }) async {
    final data = await _api('https://music.163.com/api/artist/albums/$id', {
      'limit': '$limit',
      'offset': '$offset',
      'total': 'true',
    });
    return (
      albums: [for (final a in _list(data['hotAlbums'])) ?_parseAlbum(a)],
      more: data['more'] == true,
    );
  }

  /// 专辑信息和曲目。
  Future<({Album album, List<Song> songs})> album(String id) async {
    final data = await _api('https://music.163.com/api/v1/album/$id', const {});
    final album = _parseAlbum(data['album']);
    if (album == null) throw const ApiException('专辑不存在');
    // 专辑接口里的歌曲没有带封面，统一补上专辑封面。
    final songs = [
      for (final s in _list(data['songs']))
        if (parseSong(s) case final song?) song.coverUrl == null ? _withCover(song, album) : song,
    ];
    return (album: album, songs: songs);
  }

  static Song _withCover(Song s, Album a) => Song(
    id: s.id,
    title: s.title,
    artist: s.artist,
    album: s.album.isEmpty ? a.name : s.album,
    duration: s.duration,
    coverUrl: a.coverUrl,
    subtitle: s.subtitle,
    artists: s.artists,
    albumId: s.albumId ?? a.id,
  );

  // ---------------------------------------------------------------- 搜索其他类型

  Future<({List<Playlist> items, int total})> searchPlaylists(
    String keyword, {
    int limit = 30,
    int offset = 0,
  }) async {
    final r = await _cloudSearch(keyword, 1000, limit, offset);
    return (
      items: [for (final p in _list(r['playlists'])) ?_parsePlaylist(p)],
      total: _int(r['playlistCount']),
    );
  }

  Future<({List<Artist> items, int total})> searchArtists(
    String keyword, {
    int limit = 30,
    int offset = 0,
  }) async {
    final r = await _cloudSearch(keyword, 100, limit, offset);
    return (
      items: [for (final a in _list(r['artists'])) ?_parseArtist(a)],
      total: _int(r['artistCount']),
    );
  }

  Future<({List<Album> items, int total})> searchAlbums(
    String keyword, {
    int limit = 30,
    int offset = 0,
  }) async {
    final r = await _cloudSearch(keyword, 10, limit, offset);
    return (
      items: [for (final a in _list(r['albums'])) ?_parseAlbum(a)],
      total: _int(r['albumCount']),
    );
  }

  Future<Map<Object?, Object?>> _cloudSearch(
    String keyword,
    int type,
    int limit,
    int offset,
  ) async {
    final data = await _api('https://music.163.com/api/cloudsearch/pc', {
      's': keyword,
      'type': '$type',
      'limit': '$limit',
      'offset': '$offset',
    });
    final r = data['result'];
    return r is Map ? r : const {};
  }

  // ---------------------------------------------------------------- 解析

  static Song? parseSong(Object? raw) {
    if (raw is! Map || raw['id'] == null) return null;
    final artists = _list(raw['ar'] ?? raw['artists']);
    final album = raw['al'] ?? raw['album'];
    final alias = [
      ..._list(raw['tns']),
      ..._list(raw['alia']),
      // 旧版接口（新歌推荐等）的别名字段。
      ..._list(raw['alias']),
    ].map((e) => '$e').where((e) => e.isNotEmpty);
    return Song(
      id: '${raw['id']}',
      title: '${raw['name'] ?? ''}',
      artist: [
        for (final a in artists)
          if (a is Map && _str(a['name']) != null) a['name'],
      ].join(' / '),
      album: album is Map ? '${album['name'] ?? ''}' : '',
      duration: Duration(milliseconds: _int(raw['dt'] ?? raw['duration'])),
      coverUrl: album is Map ? _https(_str(album['picUrl'])) : null,
      subtitle: alias.isEmpty ? null : alias.first,
      artists: [
        for (final a in artists)
          if (a is Map && _str(a['name']) != null && _int(a['id']) > 0)
            ArtistRef('${a['id']}', '${a['name']}'),
      ],
      albumId: album is Map && _int(album['id']) > 0 ? '${album['id']}' : null,
    );
  }

  static Comment? parseComment(Object? raw) {
    if (raw is! Map || raw['commentId'] == null) return null;
    final user = raw['user'];
    final replied = _list(raw['beReplied']).firstOrNull;
    final repliedUser = replied is Map ? replied['user'] : null;
    final location = raw['ipLocation'];
    return Comment(
      id: _int(raw['commentId']),
      user: CommentUser(
        userId: user is Map ? _int(user['userId']) : 0,
        nickname: user is Map ? '${user['nickname'] ?? ''}' : '',
        avatarUrl: user is Map ? _https(_str(user['avatarUrl'])) : null,
      ),
      content: '${raw['content'] ?? ''}',
      time: DateTime.fromMillisecondsSinceEpoch(_int(raw['time'])),
      likedCount: _int(raw['likedCount']),
      liked: raw['liked'] == true,
      replyCount: _int(raw['replyCount']),
      replyTo: replied is Map && repliedUser is Map
          ? (
              id: _int(replied['beRepliedCommentId']),
              nickname: '${repliedUser['nickname'] ?? ''}',
              // 被回复的评论已删除时 content 为 null。
              content: _str(replied['content']) ?? '该评论已删除',
            )
          : null,
      location: location is Map ? _str(location['location']) : null,
    );
  }

  static SocialUser? parseSocialUser(Object? raw) {
    if (raw is! Map || raw['userId'] == null) return null;
    final detail = raw['avatarDetail'];
    final types = {_int(raw['userType']), if (detail is Map) _int(detail['userType'])};
    return SocialUser(
      userId: _int(raw['userId']),
      nickname: '${raw['remarkName'] ?? raw['nickname'] ?? ''}'.trim(),
      avatarUrl: _https(_str(raw['avatarUrl'])),
      signature: _str('${raw['signature'] ?? ''}'.trim()),
      followed: raw['followed'] == true,
      mutual: raw['mutual'] == true,
      // userType 4 音乐人、2 明星 / 艺人；有绑定歌手（artistId）的也算。
      musician: types.contains(4) || types.contains(2) || _int(raw['artistId']) > 0,
      followeds: _int(raw['followeds']),
    );
  }

  /// 动态正文、分享的资源都在 `json` 字段（一段 JSON 字符串）里。
  static UserEvent? parseEvent(Object? raw) {
    if (raw is! Map) return null;
    final user = parseSocialUser(raw['user']);
    if (user == null) return null;
    final j = _messageJson(raw['json']);
    final info = raw['info'];
    final thread = info is Map ? info['commentThread'] : null;
    final forwarded = j['event'];
    return UserEvent(
      id: _int(raw['id'] ?? raw['eventId']),
      user: user,
      time: DateTime.fromMillisecondsSinceEpoch(_int(raw['eventTime'])),
      type: _int(raw['type']),
      text: '${j['msg'] ?? ''}'.trim(),
      title: _str('${j['title'] ?? ''}'.trim()),
      pics: [
        for (final p in _list(raw['pics']))
          if (p is Map)
            ?_https(_str(p['originUrl']) ?? _str(p['pcRectangleUrl']) ?? _str(p['squareUrl'])),
      ],
      song: parseSong(j['song']),
      playlist: _parsePlaylist(j['playlist']),
      album: _parseAlbum(j['album']),
      forwarded: forwarded is Map ? parseEvent(forwarded) : null,
      threadId:
          _str(raw['threadId']) ??
          (info is Map ? _str(info['threadId']) : null) ??
          (thread is Map ? _str(thread['id']) : null),
      likedCount: info is Map ? _int(info['likedCount']) : 0,
      liked: info is Map && info['liked'] == true,
      commentCount: info is Map ? _int(info['commentCount']) : 0,
      shareCount: info is Map ? _int(info['shareCount']) : 0,
    );
  }

  static PrivateMessage? parsePrivateMessage(Object? raw) {
    if (raw is! Map) return null;
    final from = raw['fromUser'];
    final j = _messageJson(raw['msg']);
    final pic = j['picInfo'];
    return PrivateMessage(
      id: _int(raw['id']),
      fromUserId: from is Map ? _int(from['userId']) : 0,
      time: DateTime.fromMillisecondsSinceEpoch(_int(raw['time'])),
      text: '${j['msg'] ?? ''}',
      song: parseSong(j['song']),
      playlist: _parsePlaylist(j['playlist']),
      album: _parseAlbum(j['album']),
      imageUrl: pic is Map ? _https(_str(pic['picUrl']) ?? _str(pic['url'])) : null,
    );
  }

  /// 私信 / 动态里嵌的 JSON 字符串，解析失败时返回空表。
  static Map<Object?, Object?> _messageJson(Object? raw) {
    if (raw is Map) return raw;
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final v = jsonDecode(raw);
      return v is Map ? v : const {};
    } on FormatException {
      return const {};
    }
  }

  static String _messagePreview(Map<Object?, Object?> j) {
    final text = '${j['msg'] ?? ''}'.trim();
    if (text.isNotEmpty) return text;
    String? name(Object? v) => v is Map ? _str(v['name']) : null;
    if (name(j['song']) case final n?) return '[歌曲] $n';
    if (name(j['playlist']) case final n?) return '[歌单] $n';
    if (name(j['album']) case final n?) return '[专辑] $n';
    if (j['picInfo'] != null) return '[图片]';
    return _str(j['title']) ?? '[消息]';
  }

  static Playlist? _parsePlaylist(Object? raw) {
    if (raw is! Map || raw['id'] == null) return null;
    final creator = raw['creator'];
    return Playlist(
      id: '${raw['id']}',
      name: '${raw['name'] ?? ''}',
      playCount: _int(raw['playCount']),
      trackCount: _int(raw['trackCount']),
      coverUrl: _https(_str(raw['coverImgUrl'])),
      creator: creator is Map ? _str(creator['nickname']) : null,
      creatorId: creator is Map ? _int(creator['userId']) : null,
      // 排行榜放更新频率，普通歌单放简介。
      description: _str(raw['updateFrequency']) ?? _str('${raw['description'] ?? ''}'.trim()),
      subscribed: raw['subscribed'] == true,
      isLikedList: _int(raw['specialType']) == 5,
      // 共建歌单：字段名没有公开文档，几个可能的都认（普通歌单的 sharedUsers 是 null）。
      shared:
          raw['sharedUsers'] is List || raw['playlistType'] == 'SHARED' || raw['type'] == 'SHARED',
      sharedUsers: [for (final u in _list(raw['sharedUsers'])) ?parseSocialUser(u)],
    );
  }

  /// 推荐歌单接口的字段名和歌单详情不一样（picUrl / playcount）。
  static Playlist? _parseRecommend(Object? raw) {
    if (raw is! Map || raw['id'] == null) return null;
    final creator = raw['creator'];
    return Playlist(
      id: '${raw['id']}',
      name: '${raw['name'] ?? ''}',
      playCount: _int(raw['playcount'] ?? raw['playCount']),
      trackCount: _int(raw['trackCount']),
      coverUrl: _https(_str(raw['picUrl'])),
      creator: creator is Map ? _str(creator['nickname']) : null,
      creatorId: creator is Map ? _int(creator['userId']) : null,
    );
  }

  static Artist? _parseArtist(Object? raw) {
    if (raw is! Map || raw['id'] == null) return null;
    return Artist(
      id: '${raw['id']}',
      name: '${raw['name'] ?? ''}',
      avatarUrl: _https(_artistImage(raw)),
      description: _str(raw['briefDesc']),
      songCount: _int(raw['musicSize']),
      albumCount: _int(raw['albumSize']),
      accountId: _int(raw['accountId']) > 0 ? _int(raw['accountId']) : null,
      followed: raw['followed'] == true,
    );
  }

  /// 默认头像（灰色人像）的图片 id。img1v1Url 是它时说明没有方形头像，用 picUrl。
  static const _defaultAvatarId = '5639395138885805';

  static String? _artistImage(Map<Object?, Object?> raw) {
    final square = _str(raw['img1v1Url']);
    final pic = _str(raw['picUrl']);
    if (square != null && !square.contains(_defaultAvatarId)) return square;
    if (pic != null && !pic.contains(_defaultAvatarId)) return pic;
    return square ?? pic;
  }

  static Album? _parseAlbum(Object? raw) {
    if (raw is! Map || raw['id'] == null) return null;
    final artists = _list(raw['artists']);
    final main = raw['artist'];
    final names = [
      for (final a in artists)
        if (a is Map) ?_str(a['name']),
    ];
    final publish = _int(raw['publishTime']);
    return Album(
      id: '${raw['id']}',
      name: '${raw['name'] ?? ''}',
      artist: names.isNotEmpty
          ? names.join(' / ')
          : main is Map
          ? '${main['name'] ?? ''}'
          : '',
      // 联想接口里的专辑只有 picId，没有 picUrl。
      coverUrl: _https(_str(raw['picUrl'])) ?? imageUrlFromId(raw['picId']),
      publishTime: publish > 0 ? DateTime.fromMillisecondsSinceEpoch(publish) : null,
      size: _int(raw['size']),
      description: _str(raw['description']) ?? _str(raw['briefDesc']),
    );
  }

  // ---------------------------------------------------------------- 传输
  //
  // 每种传输方式固定一种客户端身份（[ClientProfile]），UA、Cookie、EAPI 加密头三处一致：
  // - 明文 `/api/`、EAPI：PC 客户端；
  // - 播放日志（EAPI 发到 clientlog）：macOS 客户端；
  // - WEAPI：网页端；
  // - XEAPI：安卓客户端。
  // 所有方式共用同一个设备号 [deviceId]。用户 Cookie 里的系统 / 版本字段会被身份覆盖，
  // 免得 UA 说是 PC、Cookie 又说是安卓。

  /// 某种身份下的 Cookie：用户 Cookie（去掉身份字段）+ 身份字段。
  Map<String, String> _cookieFor(ClientProfile profile, {bool anonymous = false}) => {
    if (!anonymous)
      for (final e in _cookies.entries)
        if (!ClientProfile.keys.contains(e.key)) e.key: e.value,
    ...profile.fields(deviceId),
  };

  Map<String, String> _headers(ClientProfile profile, {bool anonymous = false}) => {
    'User-Agent': profile.userAgent,
    'Referer': 'https://music.163.com/',
    'Cookie': encodeCookie(_cookieFor(profile, anonymous: anonymous)),
  };

  // ---- 一起听 ----
  //
  // 接口参考 api-enhanced 的 listentogether_*（以及 NeteaseCloudMusicApi issue #1676 的分析），都需要登录。
  // 官方客户端靠长连接实时同步；公开接口只有「主机上报」这一侧，加入方只能轮询房间状态和播放列表。

  /// 创建一起听房间，返回房间号。
  Future<String> listenTogetherCreate() async {
    final data = await _eapi('/api/listen/together/room/create', {'refer': 'songplay_more'});
    final room = _obj(_obj(data['data'])['roomInfo']);
    final id = '${room['roomId'] ?? ''}';
    if (id.isEmpty) throw const ApiException('没有拿到房间号');
    return id;
  }

  /// 房间能不能加入（status 为 AVAILABLE、joinable 为 true）。
  Future<bool> listenTogetherCheck(String roomId) async {
    final data = await _eapi('/api/listen/together/room/check', {'roomId': roomId});
    final d = _obj(data['data']);
    return d['joinable'] != false && (d['status'] == null || d['status'] == 'AVAILABLE');
  }

  /// 接受邀请，加入别人的房间。
  Future<void> listenTogetherAccept(String roomId, String inviterId) => _eapi(
    '/api/listen/together/play/invitation/accept',
    {'refer': 'inbox_invite', 'roomId': roomId, 'inviterId': inviterId},
  );

  /// 当前账号的一起听状态：是否在房间里、房间号、房间里的人。
  Future<ListenTogetherStatus> listenTogetherStatus() async {
    final data = await _weapi('/api/listen/together/status/get', const {});
    final d = _obj(data['data']);
    final room = _obj(d['roomInfo']);
    return ListenTogetherStatus(
      inRoom: d['inRoom'] == true,
      roomId: _str('${room['roomId'] ?? ''}'),
      creatorId: _int(room['creatorId']),
      users: [
        for (final u in _list(room['roomUsers']))
          if (u is Map)
            SocialUser(
              userId: _int(u['userId']),
              nickname: _str(u['nickname']) ?? '',
              avatarUrl: _https(_str(u['avatarUrl'])),
            ),
      ],
    );
  }

  /// 房间的快照：播放列表（歌曲 id，按显示顺序）和最后一条播放指令。
  ///
  /// 加入方靠定时拉这个接口跟上房主：指令里有当前歌曲、播放状态、发指令时的进度，
  /// 以及服务器收到指令的时间（`serverSeq`，毫秒时间戳），据此推算现在的进度。
  /// 字段参考开源项目 Enji（together.rs）和 MeloX-Android 的实现。
  Future<ListenTogetherSnapshot> listenTogetherSnapshot(String roomId) async {
    final data = await _eapi('/api/listen/together/sync/playlist/get', {'roomId': roomId});
    final d = _obj(data['data']);
    final list = _obj(_obj(d['playlist'])['displayList']);
    final c = _obj(d['playCommand']);
    final song = '${c['targetSongId'] ?? c['songId'] ?? ''}';
    final status = '${c['playStatus'] ?? ''}'.toUpperCase();
    return ListenTogetherSnapshot(
      songIds: [for (final id in _list(list['result'])) '$id'],
      command: song.isEmpty || song == '0' || (status != 'PLAY' && status != 'PAUSE')
          ? null
          : ListenTogetherCommand(
              songId: song,
              playing: status == 'PLAY',
              progress: Duration(milliseconds: _int(c['progress']).clamp(0, 1 << 31)),
              serverTime: _int(c['serverSeq']),
              clientSeq: _int(c['clientSeq']),
              userId: _int(c['userId']),
            ),
    );
  }

  /// 主机上报整个播放列表（REPLACE）。[version] 每次加一。
  Future<void> listenTogetherSyncList(
    String roomId, {
    required int userId,
    required int version,
    required List<String> songIds,
    String playMode = 'ORDER_LOOP',
  }) => _eapi('/api/listen/together/sync/list/command/report', {
    'roomId': roomId,
    'playlistParam': jsonEncode({
      'commandType': 'REPLACE',
      'version': [
        {'userId': userId, 'version': version},
      ],
      'anchorSongId': '',
      'anchorPosition': -1,
      'randomList': songIds,
      'displayList': songIds,
      'playMode': playMode,
    }),
  });

  /// 主机上报播放指令：[command] 为 PLAY / PAUSE / GOTO / SEEK。
  Future<void> listenTogetherCommand(
    String roomId, {
    required String command,
    required String songId,
    required bool playing,
    required Duration progress,
    required int clientSeq,
    String formerSongId = '-1',
  }) => _eapi('/api/listen/together/play/command/report', {
    'roomId': roomId,
    'commandInfo': jsonEncode({
      'commandType': command,
      'progress': progress.inMilliseconds,
      'playStatus': playing ? 'PLAY' : 'PAUSE',
      'formerSongId': formerSongId,
      'targetSongId': songId,
      'clientSeq': clientSeq,
    }),
  });

  /// 心跳：每首歌开始时和之后定时上报当前歌曲与进度。
  Future<void> listenTogetherHeartbeat(
    String roomId, {
    required String songId,
    required bool playing,
    required Duration progress,
  }) => _eapi('/api/listen/together/heartbeat', {
    'roomId': roomId,
    'songId': songId,
    'playStatus': playing ? 'PLAY' : 'PAUSE',
    'progress': progress.inMilliseconds,
  });

  /// 结束房间（主机）或退出。
  Future<void> listenTogetherEnd(String roomId) =>
      _eapi('/api/listen/together/end/v2', {'roomId': roomId});

  static String _buildver() => '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';

  /// 以 PC 客户端身份发一个明文 `/api/` 请求。
  Future<Map<String, Object?>> _api(
    String url,
    Map<String, String> form, {
    bool anonymous = false,
  }) async {
    final res = await _post(Uri.parse(url), form, ClientProfile.pc, anonymous: anonymous);
    return _check(_decodeJson(utf8.decode(res.bodyBytes)));
  }

  /// 发一个 EAPI 加密请求，默认 PC 客户端身份。
  ///
  /// 加密头和 api-enhanced 一致：设备字段 + `requestId`，登录态（`MUSIC_U` / `__csrf`）也放进去。
  Future<Map<String, Object?>> _eapi(
    String apiPath,
    Map<String, Object?> params, {
    String host = 'https://interface3.music.163.com',
    bool encryptedResponse = false,
    ClientProfile profile = ClientProfile.pc,
  }) async {
    final header = {
      ...profile.fields(deviceId),
      'versioncode': '140',
      'buildver': _buildver(),
      'resolution': '1920x1080',
      'requestId': '${20000000 + _random.nextInt(10000000)}',
      'MUSIC_U': ?_str(_cookies['MUSIC_U']),
      '__csrf': ?_str(_cookies['__csrf']),
    };
    final payload = jsonEncode({
      ...params,
      if (encryptedResponse) 'e_r': true,
      'header': jsonEncode(header),
    });
    final url = Uri.parse('$host${apiPath.replaceFirst('/api/', '/eapi/')}');
    final res = await _post(url, {'params': EapiCrypto.encrypt(apiPath, payload)}, profile);
    final String body;
    try {
      body = encryptedResponse ? EapiCrypto.decrypt(res.bodyBytes) : utf8.decode(res.bodyBytes);
    } catch (_) {
      throw const ApiException('接口返回无法解密');
    }
    return _check(_decodeJson(body));
  }

  /// 以网页端身份发一个 WEAPI 加密请求（带 `csrf_token`）。
  Future<Map<String, Object?>> _weapi(String apiPath, Map<String, Object?> params) async {
    final body = jsonEncode({...params, 'csrf_token': _cookies['__csrf'] ?? ''});
    final res = await _post(
      Uri.parse('https://music.163.com${apiPath.replaceFirst('/api/', '/weapi/')}'),
      WeapiCrypto.encrypt(body, random: _random),
      ClientProfile.web,
    );
    return _check(_decodeJson(utf8.decode(res.bodyBytes)));
  }

  /// 先试 [primary]，服务端报错时用 [fallback] 再试；两次都失败报 [primary] 的错误。
  ///
  /// 用于和 api-enhanced 对齐传输方式的写操作：新方式不通时退回原来能用的方式。
  static Future<T> _withFallback<T>(Future<T> Function() primary, Future<T> Function() fallback) =>
      _firstAccepted([primary, fallback]);

  /// 按顺序试 [tries]，返回第一个成功的结果；都失败时报第一个带错误码的错误。
  ///
  /// 登录失效、网络错误和风控（-460 / -462）不往下试：前者重试没用，网络错误时服务端可能已经处理过，
  /// 风控时多试只会让账号更像异常。
  static Future<T> _firstAccepted<T>(List<Future<T> Function()> tries) async {
    ApiException? first;
    for (final attempt in tries) {
      try {
        return await attempt();
      } on ApiException catch (e) {
        // 停下时报让它停下的那个错误（要登录、风控、断网），用户才知道该做什么。
        if (e.needsLogin || e.network || e.riskControl) rethrow;
        // 优先报服务端给了错误码的那个（比如公钥没取到时，报后面接口的「关注异常」）。
        if (first == null || (first.code == null && e.code != null)) first = e;
      }
    }
    throw first!;
  }

  // ---------------------------------------------------------------- XEAPI

  /// XEAPI 的服务端公钥（首次用到时取，失效或设备号变化时重取）。
  Future<XeapiPublicKey>? _xeapiKey;

  Future<XeapiPublicKey> _xeapiPublicKey() => _xeapiKey ??= _fetchXeapiKey().then(
    (k) => k,
    onError: (Object e, StackTrace s) {
      _xeapiKey = null; // 失败了下次重试。
      Error.throwWithStackTrace(e, s);
    },
  );

  Future<XeapiPublicKey> _fetchXeapiKey() async {
    final nonce = List.generate(16, (_) => _random.nextInt(10)).join();
    final timestamp = '${DateTime.now().millisecondsSinceEpoch}';
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('https://interface.music.163.com/api/bsr/sk/get'),
            headers: {
              'User-Agent': ClientProfile.android.userAgent,
              'Cookie': encodeCookie({'deviceId': deviceId}),
            },
            body: XeapiCrypto.registerForm(deviceId: deviceId, nonce: nonce, timestamp: timestamp),
          )
          .timeout(_timeout);
    } catch (e) {
      throw ApiException('网络请求失败：$e', network: true);
    }
    final data = _check(_decodeJson(utf8.decode(res.bodyBytes)))['data'];
    if (data is! Map ||
        data['encryptedData'] is! String ||
        XeapiCrypto.sign('${data['timestamp']}', nonce) != data['signature']) {
      throw const ApiException('获取加密公钥失败');
    }
    try {
      return XeapiCrypto.decryptPublicKey(data['encryptedData'] as String);
    } on FormatException {
      throw const ApiException('获取加密公钥失败');
    }
  }

  /// 以安卓客户端身份发一个 XEAPI 加密请求。
  Future<Map<String, Object?>> _xeapi(
    String apiPath,
    Map<String, String> form, {
    Map<String, String> headers = const {},
  }) async {
    final key = await _xeapiPublicKey();
    const profile = ClientProfile.android;
    final buildver = _buildver();
    final cookie = {..._cookieFor(profile), 'buildver': buildver, 'sDeviceId': deviceId};
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(
              'https://interface3.music.163.com${apiPath.replaceFirst('/api/', '/xeapi/')}',
            ),
            headers: {
              'User-Agent': profile.userAgent,
              'X-Client-Enc-State': 'ENCRYPTED',
              'x-aeapi': 'true',
              'x-deviceid': deviceId,
              'x-sdeviceid': deviceId,
              'x-os': profile.os,
              'x-osver': profile.osver,
              'x-appver': profile.appver,
              'x-buildver': buildver,
              'x-music-u': ?_str(_cookies['MUSIC_U']),
              'Cookie': encodeCookie(cookie),
              ...headers,
            },
            body: XeapiCrypto.encrypt(form, key, os: profile.os),
          )
          .timeout(_timeout);
    } catch (e) {
      throw ApiException('网络请求失败：$e', network: true);
    }
    if (res.statusCode != 200) throw ApiException('HTTP ${res.statusCode}', code: res.statusCode);
    final String body;
    try {
      body = XeapiCrypto.decrypt(res.bodyBytes);
    } catch (_) {
      _xeapiKey = null; // 可能是公钥过期，下次重取。
      throw const ApiException('接口返回无法解密');
    }
    return _check(_decodeJson(body));
  }

  Future<http.Response> _post(
    Uri url,
    Map<String, String> form,
    ClientProfile profile, {
    bool anonymous = false,
  }) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            url,
            headers: _headers(profile, anonymous: anonymous),
            body: form,
          )
          .timeout(_timeout);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('网络请求失败：$e', network: true);
    }
    if (res.statusCode != 200) throw ApiException('HTTP ${res.statusCode}', code: res.statusCode);
    return res;
  }

  static Map<String, Object?> _decodeJson(String body) {
    try {
      final v = jsonDecode(body);
      if (v is Map<String, Object?>) return v;
    } on FormatException {
      // 落到下面统一报错。
    }
    throw const ApiException('接口返回格式错误');
  }

  static Map<String, Object?> _check(Map<String, Object?> data) {
    final code = data['code'];
    if (code is int && code != 200) {
      final msg = _str(data['message']) ?? _str(data['msg']) ?? '接口返回错误';
      // 风控时 message 只有「关注异常」，具体原因（「您操作太快啦」）在弹窗字段里。
      final dialog = data['dialog'];
      final detail = dialog is Map ? _str(dialog['subtitle']) : null;
      throw ApiException(detail == null ? msg : '$msg：$detail', code: code);
    }
    return data;
  }

  static List<Object?> _list(Object? v) => v is List ? v : const [];
  static Map<Object?, Object?> _obj(Object? v) => v is Map ? v : const {};
  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  static String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

  /// 网易云图片地址有时是 http，统一换成 https。
  static String? _https(String? url) => url?.replaceFirst(RegExp('^http:'), 'https:');
}

/// 由图片 id 算出图片地址（网易云的 encrypt_id：id 与固定密钥异或后取 MD5，再做 URL 安全的 Base64）。
String? imageUrlFromId(Object? picId) {
  final id = '${picId ?? ''}';
  if (id.isEmpty || id == '0' || int.tryParse(id) == null) return null;
  const key = '3go8&\$8*3*3h0k(2)2';
  final bytes = [
    for (var i = 0; i < id.length; i++) id.codeUnitAt(i) ^ key.codeUnitAt(i % key.length),
  ];
  final enc = base64Encode(crypto.md5.convert(bytes).bytes)
      .replaceAll('/', '_')
      .replaceAll('+', '-');
  return 'https://p1.music.126.net/$enc/$id.jpg';
}

/// 去掉裁剪参数，取原图。
String originalImage(String url) {
  final q = url.indexOf('?');
  return q < 0 ? url : url.substring(0, q);
}

/// 网易云图片按尺寸裁剪：`?param=200y200`。
String sizedImage(String url, int px) => '$url${url.contains('?') ? '&' : '?'}param=${px}y$px';

/// 动态附带的资源类型。
enum ShareType {
  none('noresource'),
  song('song'),
  playlist('playlist');

  const ShareType(this.value);

  final String value;
}

enum QrStatus { expired, waiting, scanned, confirmed }

class QrCheck {
  const QrCheck({required this.status, this.nickname, this.avatarUrl, this.cookies = const {}});

  final QrStatus status;

  /// 已扫码（802）时返回扫码账号的昵称和头像。
  final String? nickname;
  final String? avatarUrl;

  /// 登录成功（803）时网易云下发的 Cookie。
  final Map<String, String> cookies;
}

class SearchSuggestion {
  const SearchSuggestion({
    this.songs = const [],
    this.artists = const [],
    this.albums = const [],
    this.playlists = const [],
  });

  final List<Song> songs;
  final List<Artist> artists;
  final List<Album> albums;
  final List<Playlist> playlists;

  bool get isEmpty => songs.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty;
}
