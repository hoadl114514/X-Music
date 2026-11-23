import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../shell/player_bar.dart';
import '../../state/account_controller.dart';
import '../login_page.dart';
import '../search_page.dart';
import 'track_list_view.dart';

/// 音乐库里的「艺人」：已关注（收藏）的歌手，滑到底自动加载下一页。
class FollowedArtistsPage extends StatefulWidget {
  const FollowedArtistsPage({super.key});

  @override
  State<FollowedArtistsPage> createState() => _FollowedArtistsPageState();
}

class _FollowedArtistsPageState extends State<FollowedArtistsPage> {
  static const _pageSize = 50;

  final _items = <Artist>[];
  bool _more = true;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && AccountScope.read(context).isLoggedIn) _loadMore();
    });
  }

  Future<void> _loadMore() async {
    if (_loading || !_more) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await AppScope.of(context).api
          .followedArtists(limit: _pageSize, offset: _items.length);
      if (!mounted) return;
      setState(() {
        _items.addAll(r.items);
        _more = r.more && r.items.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _more = true;
    });
    await _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    if (!AccountScope.of(context).isLoggedIn) {
      return const LoginPrompt(message: '登录后查看已关注的艺人');
    }
    final error = _error;
    if (error != null && _items.isEmpty) return ErrorState(error: error, onRetry: _loadMore);
    if (_items.isEmpty) {
      return _loading
          ? const Center(child: CircularProgressIndicator())
          : const Center(child: Text('还没有关注艺人'));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 400) _loadMore();
        return false;
      },
      child: RefreshIndicator(
        onRefresh: _reload,
        child: ListView.builder(
          padding: EdgeInsets.only(top: 8, bottom: 24 + floatingBarsInset(context)),
          itemCount: _items.length + 1,
          itemBuilder: (context, i) {
            if (i < _items.length) return ArtistTile(artist: _items[i]);
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: error != null
                    ? TextButton(onPressed: _loadMore, child: const Text('加载失败，点击重试'))
                    : _loading
                    ? const CircularProgressIndicator()
                    : const SizedBox.shrink(),
              ),
            );
          },
        ),
      ),
    );
  }
}
