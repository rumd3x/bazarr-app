import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'media_screen.dart';

/// Subtitle history for series (episodes) and movies.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Series'),
            Tab(text: 'Movies'),
          ],
        ),
      ),
      body: const TabBarView(
        children: [_HistoryList(movies: false), _HistoryList(movies: true)],
      ),
    ),
  );
}

class _HistoryList extends StatefulWidget {
  final bool movies;
  const _HistoryList({required this.movies});

  @override
  State<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryList>
    with AutomaticKeepAliveClientMixin {
  static const _pageSize = 50;
  final _items = <Json>[];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<ListPage> _fetch(int start) {
    final api = context.read<AppState>().api!;
    return widget.movies
        ? api.movieHistory(start: start, length: _pageSize)
        : api.episodeHistory(start: start, length: _pageSize);
  }

  Future<void> _refresh() async {
    try {
      final page = await _fetch(0);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _total = page.total;
        _error = null;
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

  Future<void> _more() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetch(_items.length);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _total = page.total;
      });
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) {
      return ErrorView(
        error: _error!,
        onRetry: () {
          setState(() => _loading = true);
          _refresh();
        },
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: _items.isEmpty
          ? const EmptyView(Icons.history, 'No history yet')
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: _items.length + (_items.length < _total ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _items.length) {
                  return Padding(
                    padding: const EdgeInsets.all(8),
                    child: Center(
                      child: _loadingMore
                          ? const CircularProgressIndicator()
                          : OutlinedButton(
                              onPressed: _more,
                              child: Text(
                                'Load more (${_total - _items.length})',
                              ),
                            ),
                    ),
                  );
                }
                return HistoryTile(_items[i], movie: widget.movies);
              },
            ),
    );
  }
}

enum _Kind { download, upgrade, manual, sync, translate, delete, other }

_Kind _kindOf(Json h) {
  final d = '${h['description']}'.toLowerCase();
  if (d.contains('delet')) return _Kind.delete;
  if (d.contains('upgrad')) return _Kind.upgrade;
  if (d.contains('translat')) return _Kind.translate;
  if (d.contains('sync')) return _Kind.sync;
  if (d.contains('manual') || d.contains('upload')) return _Kind.manual;
  if (d.contains('download')) return _Kind.download;
  return _Kind.other;
}

/// One history entry. When [showMedia] is false the entry is shown inside the
/// media's own History tab, so the title is not repeated.
class HistoryTile extends StatelessWidget {
  final Json item;
  final bool movie;
  final bool showMedia;
  const HistoryTile(
    this.item, {
    super.key,
    required this.movie,
    this.showMedia = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kind = _kindOf(item);
    final (icon, color) = switch (kind) {
      _Kind.download => (Icons.download_done, Colors.greenAccent.shade400),
      _Kind.upgrade => (Icons.upgrade, Colors.lightBlueAccent),
      _Kind.manual => (Icons.touch_app, Colors.amber),
      _Kind.sync => (Icons.sync, Colors.tealAccent),
      _Kind.translate => (Icons.translate, Colors.purpleAccent),
      _Kind.delete => (Icons.delete_outline, Colors.redAccent),
      _Kind.other => (Icons.subtitles_outlined, cs.onSurfaceVariant),
    };
    final lang = item['language'] is Map
        ? languageLabel(Json.from(item['language'] as Map))
        : null;
    final title = movie
        ? '${item['title']}'
        : '${item['seriesTitle']} · ${item['episode_number'] ?? ''}';
    final provider = '${item['provider'] ?? ''}';
    final score = '${item['score'] ?? ''}';
    final blacklisted = item['blacklisted'] == true;

    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          showMedia ? title : lang ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!movie &&
                showMedia &&
                '${item['episodeTitle'] ?? ''}'.isNotEmpty)
              Text(
                '${item['episodeTitle']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            Text('${item['description'] ?? ''}'),
            const SizedBox(height: 2),
            Wrap(
              spacing: 8,
              children: [
                if (showMedia && lang != null) _Meta(Icons.language, lang),
                if (provider.isNotEmpty) _Meta(Icons.cloud_outlined, provider),
                if (score.isNotEmpty && score != 'null')
                  _Meta(Icons.percent, score),
                if (item['upgradable'] == true)
                  const _Meta(Icons.upgrade, 'Upgradable'),
                if (blacklisted) const _Meta(Icons.block, 'Blacklisted'),
              ],
            ),
          ],
        ),
        trailing: Text(
          '${item['timestamp'] ?? ''}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        isThreeLine: true,
        onTap: !showMedia ? null : () => _open(context),
      ),
    );
  }

  void _open(BuildContext context) {
    final MediaRef ref;
    final String title;
    final String? subtitle;
    if (movie) {
      final id = item['radarrId'];
      if (id is! int) return;
      ref = MediaRef.movie(id);
      title = '${item['title']}';
      subtitle = null;
    } else {
      final id = item['sonarrEpisodeId'];
      final sid = item['sonarrSeriesId'];
      if (id is! int || sid is! int) return;
      ref = MediaRef.episode(sid, id);
      title = '${item['seriesTitle']}';
      subtitle = '${item['episode_number'] ?? ''} ${item['episodeTitle'] ?? ''}'
          .trim();
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaScreen(ref: ref, title: title, subtitle: subtitle),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Meta(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: c)),
      ],
    );
  }
}
