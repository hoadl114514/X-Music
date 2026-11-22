import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/playlist_card.dart';
import '../library/track_list_view.dart';
import '../search_page.dart';
import '../../shell/player_bar.dart';

/// 发现：热搜 + 官方排行榜。
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  late Future<(List<String>, List<Playlist>)> _future = _load();

  Future<(List<String>, List<Playlist>)> _load() async {
    final api = AppScope.of(context).api;
    // 热搜失败不影响榜单。
    final hot = api.hotSearches().catchError((Object _) => <String>[]);
    final tops = await api.toplists();
    return (await hot, tops);
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future.catchError((_) => (const <String>[], const <Playlist>[]));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<String>, List<Playlist>)>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(error: snap.error!, onRetry: _reload);
        final data = snap.data;
        if (data == null) return const Center(child: CircularProgressIndicator());
        final (hot, tops) = data;
        return RefreshIndicator(
          onRefresh: _reload,
          child: CustomScrollView(
            slivers: [
              if (hot.isNotEmpty) ...[
                const _Title('热搜'),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (i, w) in hot.indexed)
                          ActionChip(
                            avatar: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: i < 3 ? context.colors.accent : context.colors.textMuted,
                              ),
                            ),
                            label: Text(w),
                            onPressed: () => SearchPage.open(context, w),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const _Title('排行榜'),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + floatingBarsInset(context)),
                sliver: SliverPlaylistGrid(playlists: tops),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      sliver: SliverToBoxAdapter(child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
    );
  }
}
