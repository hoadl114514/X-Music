import 'package:flutter/material.dart';

import '../../api/netease_api.dart';
import '../../app/app.dart';
import '../../theme/app_theme.dart';
import '../library/track_list_view.dart';
import 'nav.dart';

/// 新歌速递：按地区列出最近一周上架的新歌。首页「新歌精选」的标题点进来。
class NewSongsPage extends StatefulWidget {
  const NewSongsPage({super.key});

  static Future<void> open(BuildContext context) => SubPage.push(context, const NewSongsPage());

  @override
  State<NewSongsPage> createState() => _NewSongsPageState();
}

class _NewSongsPageState extends State<NewSongsPage> {
  var _area = NeteaseApi.newSongAreas.first;

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    final area = _area;
    return SubPage(
      title: '新歌速递',
      body: TrackListView(
        load: () => api.newSongExpress(area: area.$2),
        reloadKey: area,
        queueTitle: '新歌速递 · ${area.$1}',
        header: (context, tracks, playAll) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CollectionHeader(
              title: '新歌速递',
              seed: 'new-songs',
              icon: Icons.fiber_new_rounded,
              lines: const ['最近一周上架的新歌'],
              onPlayAll: playAll,
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  for (final a in NeteaseApi.newSongAreas)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(a.$1),
                        selected: a == area,
                        selectedColor: AppColors.accent.withValues(alpha: 0.25),
                        onSelected: (_) => setState(() => _area = a),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
