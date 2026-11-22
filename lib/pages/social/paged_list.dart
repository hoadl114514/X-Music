import 'package:flutter/material.dart';

import '../../api/netease_api.dart';
import '../../theme/app_theme.dart';
import '../library/track_list_view.dart';
import '../login_page.dart';
import '../../shell/player_bar.dart';

/// 一页数据和下一页的游标（offset、lasttime 之类，由调用方决定）。
typedef PageResult<T> = ({List<T> items, bool more, Object? next});

/// 第一页 [cursor] 为 null。
typedef PageLoader<T> = Future<PageResult<T>> Function(Object? cursor);

/// 滚到底自动加载下一页的列表，支持下拉刷新。关注 / 粉丝、动态、私信会话共用。
class PagedListView<T> extends StatefulWidget {
  const PagedListView({
    super.key,
    required this.load,
    required this.itemBuilder,
    this.header = const [],
    this.filter,
    this.empty = '这里什么都没有',
    this.loginHint = '登录后查看',
    this.separated = false,
  });

  final PageLoader<T> load;

  /// [remove] 把这一项从列表里去掉（例如删除了自己的动态）。
  final Widget Function(BuildContext context, T item, VoidCallback remove) itemBuilder;

  /// 列表上方的固定内容，跟着一起滚动。
  final List<Widget> header;

  /// 只显示满足条件的项（不影响翻页）。
  final bool Function(T item)? filter;
  final String empty;

  /// 接口要求登录（301）时的提示。
  final String loginHint;

  /// 项之间画分隔线。
  final bool separated;

  @override
  State<PagedListView<T>> createState() => PagedListViewState<T>();
}

class PagedListViewState<T> extends State<PagedListView<T>> {
  final _items = <T>[];
  Object? _next;
  bool _more = true;
  bool _loading = false;
  Object? _error;

  /// 防止刷新后旧请求的结果混进来。
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  /// 清空重新加载。
  Future<void> refresh() async {
    _generation++;
    setState(() {
      _items.clear();
      _next = null;
      _more = true;
      _loading = false;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_more) return;
    final gen = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.load(_next);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _next = page.next;
        // 接口说还有、但这页是空的：停下，免得一直空转。
        _more = page.more && page.items.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 600) _loadMore();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.filter;
    final visible = filter == null ? _items : _items.where(filter).toList();
    final error = _error;
    // 筛掉太多、一屏不满时滚动触发不了加载，直接接着取下一页。
    if (!_loading && error == null && _more && _items.isNotEmpty && visible.length < 8) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadMore();
      });
    }
    final Widget? footer;
    if (error != null && _items.isEmpty) {
      footer = error is ApiException && error.needsLogin
          ? _LoginHint(text: widget.loginHint)
          : SizedBox(
              height: 240,
              child: ErrorState(error: error, onRetry: _loadMore),
            );
    } else if (error != null) {
      footer = Center(
        child: TextButton(onPressed: _loadMore, child: const Text('加载失败，点击重试')),
      );
    } else if (_loading || (_more && visible.isEmpty)) {
      footer = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (visible.isEmpty) {
      footer = Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(widget.empty, style: TextStyle(color: context.colors.textMuted)),
        ),
      );
    } else {
      footer = null;
    }

    final head = widget.header.length;
    final count = head + visible.length + (footer == null ? 0 : 1);
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: RefreshIndicator(
        onRefresh: refresh,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: 16 + floatingBarsInset(context)),
          itemCount: count,
          itemBuilder: (context, i) {
            if (i < head) return widget.header[i];
            final j = i - head;
            if (j >= visible.length) return footer!;
            final item = visible[j];
            final child = widget.itemBuilder(
              context,
              item,
              () => setState(() => _items.remove(item)),
            );
            if (!widget.separated || j == 0) return child;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Divider(height: 1, indent: 16, endIndent: 16, color: context.colors.border),
                child,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LoginHint extends StatelessWidget {
  const _LoginHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Text(text, style: TextStyle(color: context.colors.textSecondary)),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => LoginPage.open(context), child: const Text('去登录')),
        ],
      ),
    );
  }
}
