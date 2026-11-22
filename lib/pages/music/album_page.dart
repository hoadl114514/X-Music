import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../library/track_list_view.dart';
import 'nav.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key, required this.albumId, this.name});

  final String albumId;

  /// 加载完之前先显示的名字。
  final String? name;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  Album? _album;

  Future<List<Song>> _load() async {
    final r = await AppScope.of(context).api.album(widget.albumId);
    if (mounted) setState(() => _album = r.album);
    return r.songs;
  }

  @override
  Widget build(BuildContext context) {
    final a = _album;
    final title = a?.name ?? widget.name ?? '专辑';
    return SubPage(
      title: '专辑',
      body: TrackListView(
        load: _load,
        queueTitle: '专辑：$title',
        sourceId: widget.albumId,
        header: (context, tracks, playAll) => CollectionHeader(
          title: title,
          seed: widget.albumId,
          coverUrl: a?.coverUrl,
          icon: Icons.album_rounded,
          lines: [
            if (a != null && a.artist.isNotEmpty) a.artist,
            if (a?.publishTime case final t?)
              '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} 发行'
                  '${a!.size > 0 ? ' · ${a.size} 首' : ''}',
          ],
          onPlayAll: playAll,
        ),
      ),
    );
  }
}
