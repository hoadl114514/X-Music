import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/api/netease_api.dart';

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
}
