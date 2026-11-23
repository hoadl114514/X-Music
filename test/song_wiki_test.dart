import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/api/netease_api.dart';
import 'package:netease_client/data/models.dart';

void main() {
  // 真实接口返回（截短了相似歌曲和相关歌单）。
  final raw =
      jsonDecode(File('test/fixtures/song_wiki.json').readAsStringSync()) as Map<String, Object?>;

  test('song wiki parses facts, similar songs and related playlists', () {
    final wiki = NeteaseApi.parseSongWiki(raw);
    final facts = {for (final f in wiki.facts) f.label: f.values};
    expect(facts['曲风'], ['流行-华语流行']);
    expect(facts['推荐标签'], containsAll(['思念', '浪漫']));
    expect(facts['语种'], ['国语']);
    expect(facts['BPM'], ['69']);
    expect(facts['获奖成就'], isNotEmpty);
    // 乐谱、评论不展示。
    expect(facts.keys, isNot(contains('乐谱')));

    expect(wiki.similar, hasLength(3));
    expect(wiki.similar.first.id, '288820');
    expect(wiki.similar.first.artist, contains('周杰伦'));
    expect(wiki.similar.first.coverUrl, startsWith('https://'));

    expect(wiki.playlists, hasLength(2));
    expect(wiki.playlists.first.id, '59373897');
    expect(wiki.playlists.first.playCount, 880876);
  });

  test('an empty response gives an empty wiki', () {
    expect(NeteaseApi.parseSongWiki({'code': 200}).isEmpty, isTrue);
  });

  test('more similar songs are appended without duplicates', () {
    final wiki = NeteaseApi.parseSongWiki(raw).withMoreSimilar(const [
      SongBrief(id: '288820', title: '重复的'),
      SongBrief(id: '1', title: '新的'),
    ]);
    expect(wiki.similar, hasLength(4));
    expect(wiki.similar.last.title, '新的');
  });

  test('artist profile combines head info, fans and latest album', () {
    final p = NeteaseApi.parseArtistProfile(
      {
        'code': 200,
        'data': {
          'artist': {
            'id': 102939,
            'name': 'Tame Impala',
            'cover': 'http://p4.music.126.net/a.jpg',
            'avatar': 'http://p3.music.126.net/b.jpg',
            'briefDesc': ' 迷幻音乐项目 ',
            'musicSize': 675,
            'albumSize': 53,
          },
        },
      },
      {
        'code': 200,
        'data': {'isFollow': true, 'fansCnt': 67905},
      },
      const Album(id: '9', name: '新专辑', artist: 'Tame Impala'),
    );
    expect(p.artist.id, '102939');
    expect(p.artist.description, '迷幻音乐项目');
    expect(p.coverUrl, 'https://p4.music.126.net/a.jpg');
    expect(p.artist.avatarUrl, 'https://p3.music.126.net/b.jpg');
    expect(p.fans, 67905);
    expect(p.followed, isTrue);
    expect(p.latestAlbum?.id, '9');

    final bare = NeteaseApi.parseArtistProfile(
      {
        'data': {
          'artist': {'id': 1, 'name': 'X'},
        },
      },
      null,
      null,
    );
    expect(bare.fans, isNull);
    expect(bare.followed, isFalse);
  });
}
