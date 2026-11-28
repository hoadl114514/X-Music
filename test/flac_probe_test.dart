import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/audio/flac_probe.dart';
import 'package:netease_client/data/models.dart';

import 'support/fakes.dart';

/// 造一个 FLAC 文件头：可选 ID3 标签 + "fLaC" + STREAMINFO。
Uint8List _flac({required int bits, int sampleRate = 96000, int channels = 2, int id3 = 0}) {
  final info = Uint8List(34);
  final bps = bits - 1;
  final ch = channels - 1;
  info[10] = sampleRate >> 12 & 0xff;
  info[11] = sampleRate >> 4 & 0xff;
  info[12] = (sampleRate & 0x0f) << 4 | ch << 1 | bps >> 4;
  info[13] = (bps & 0x0f) << 4;
  return Uint8List.fromList([
    if (id3 > 0) ...[
      0x49, 0x44, 0x33, 4, 0, 0, //
      id3 >> 21 & 0x7f, id3 >> 14 & 0x7f, id3 >> 7 & 0x7f, id3 & 0x7f,
      ...List.filled(id3, 0),
    ],
    0x66, 0x4c, 0x61, 0x43, // fLaC
    0x80, 0, 0, 34, // 最后一个块，STREAMINFO，长度 34
    ...info,
  ]);
}

void main() {
  test('读出 16 bit 和 24 bit', () {
    expect(FlacProbe.bitDepthAt(_flac(bits: 16, sampleRate: 44100), 0), 16);
    expect(FlacProbe.bitDepthAt(_flac(bits: 24, sampleRate: 192000), 0), 24);
  });

  test('跳过开头的 ID3 标签', () {
    final b = _flac(bits: 24, id3: 300);
    final skip = FlacProbe.id3Length(b)!;
    expect(skip, 310);
    expect(FlacProbe.bitDepthAt(b, skip), 24);
  });

  test('不是 FLAC 时返回 null', () {
    final mp3 = Uint8List.fromList([0xff, 0xfb, 0x90, 0x64, ...List.filled(40, 0)]);
    expect(FlacProbe.bitDepthAt(mp3, 0), isNull);
  });

  test('ID3 标签超过首段时按偏移补取', () async {
    final file = _flac(bits: 24, id3: 70000);
    final ranges = <String>[];
    final probe = FlacProbe(
      client: MockClient((req) async {
        final r = req.headers['Range']!;
        ranges.add(r);
        final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(r)!;
        final from = int.parse(m[1]!);
        final to = int.parse(m[2]!).clamp(0, file.length - 1);
        return http.Response.bytes(file.sublist(from, to + 1), 206);
      }),
    );
    expect(await probe.bitDepth('https://x/a.flac'), 24);
    expect(ranges, hasLength(2));
  });

  test('打开音质列表时读出无损档位深，降档时不标', () async {
    final f = await fakeServices();
    f.backend.qualityMap['1'] = [
      AudioQuality.exhigh,
      AudioQuality.lossless,
      AudioQuality.hires,
      AudioQuality.jymaster,
    ];
    f.backend.accountMax = AudioQuality.hires;
    f.backend.bitDepths['https://x/1/lossless'] = 16;
    f.backend.bitDepths['https://x/1/hires'] = 24;
    final player = f.services.player;
    await player.playQueue([song('1')], title: 't');
    await player.pause();
    await player.probeBitDepths();
    expect(player.bitDepthOf(AudioQuality.lossless), 16);
    expect(player.bitDepthOf(AudioQuality.hires), 24);
    expect(player.bitDepthOf(AudioQuality.jymaster), isNull, reason: '服务端降到了 Hi-Res');
    expect(player.bitDepthOf(AudioQuality.exhigh), isNull, reason: '有损档没有位深');

    final before = f.backend.urlRequests.length;
    await player.probeBitDepths();
    expect(f.backend.urlRequests.length, before, reason: '每档只读一次');
  });
}
