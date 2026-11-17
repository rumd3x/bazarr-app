import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'movie_detail_screen.dart';
import 'series_detail_screen.dart';

enum _Filter { all, monitored, missing }

/// Library of series or movies with search, filters and subtitle progress.
class LibraryScreen extends StatefulWidget {
  final bool movies;
  const LibraryScreen({super.key, required this.movies});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Json> _all = [];
  bool _loading = true;
  Object? _error;
  String _query = '';
  bool _searching = false;
  bool _grid = true;
  _Filter _filter = _Filter.all;

  bool get _movies => widget.movies;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final state = context.read<AppState>();
    final cached = await (_movies
        ? state.cachedMovies()
        : state.cachedSeries());
    if (cached != null && mounted) {
      setState(() {
        _all = cached;
        _loading = false;
      });
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    final state = context.read<AppState>();
    try {
      final list = await (_movies ? state.api!.movies() : state.api!.series());
      if (_movies) {
        state.cacheMovies(list);
      } else {
        state.cacheSeries(list);
      }
      if (!mounted) return;
      setState(() {
        _all = list;
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

  /// Number of missing subtitle languages (movies) or episodes with missing
  /// subtitles (series).
  int _missing(Json i) => _movies
      ? jsonList(i['missing_subtitles']).length
      : (i['episodeMissingCount'] as num?)?.toInt() ?? 0;

  List<Json> get _visible {
    final q = _query.toLowerCase();
    final list = _all.where((s) {
      if (q.isNotEmpty && !'${s['title']}'.toLowerCase().contains(q)) {
        return false;
      }
      switch (_filter) {
        case _Filter.all:
          return true;
        case _Filter.monitored:
          return s['monitored'] == true;
        case _Filter.missing:
          return _missing(s) > 0;
      }
    }).toList();
    list.sort(
      (a, b) => '${a['title']}'.toLowerCase().compareTo(
        '${b['title']}'.toLowerCase(),
      ),
    );
    return list;
  }

  Future<void> _open(Json item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _movies
            ? MovieDetailScreen(movie: item)
            : SeriesDetailScreen(series: item),
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    final label = _movies ? 'Movies' : 'Series';
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Filter library…',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v),
              )
            : Text('$label (${_all.length})'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _query = '';
            }),
          ),
          IconButton(
            icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _grid = !_grid),
          ),
          PopupMenuButton<_Filter>(
            icon: Badge(
              isLabelVisible: _filter != _Filter.all,
              smallSize: 8,
              child: const Icon(Icons.filter_list),
            ),
            initialValue: _filter,
            onSelected: (f) => setState(() => _filter = f),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Filter.all, child: Text('All')),
              PopupMenuItem(value: _Filter.monitored, child: Text('Monitored')),
              PopupMenuItem(
                value: _Filter.missing,
                child: Text('Missing subtitles'),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null && _all.isEmpty)
          ? ErrorView(error: _error!, onRetry: _refresh)
          : RefreshIndicator(
              onRefresh: _refresh,
              child: items.isEmpty
                  ? EmptyView(
                      _movies
                          ? Icons.movie_outlined
                          : Icons.video_library_outlined,
                      'No ${label.toLowerCase()} found',
                    )
                  : _grid
                  ? _buildGrid(items)
                  : _buildList(items),
            ),
    );
  }

  Widget _buildGrid(List<Json> items) => GridView.builder(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 160,
      childAspectRatio: 0.62,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
    ),
    itemCount: items.length,
    itemBuilder: (_, i) {
      final s = items[i];
      final missing = _missing(s);
      return GestureDetector(
        onTap: () => _open(s),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Poster(s, icon: _movies ? Icons.movie : Icons.tv),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ProgressBar(s, movies: _movies, thick: true),
              ),
              if (missing > 0)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$missing',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (s['monitored'] != true)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    Icons.bookmark_border,
                    size: 20,
                    color: Colors.white70,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _buildList(List<Json> items) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
    itemCount: items.length,
    itemBuilder: (_, i) {
      final s = items[i];
      return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(s),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                height: 92,
                child: Poster(s, icon: _movies ? Icons.movie : Icons.tv),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${s['title']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${s['year'] ?? ''}'
                        '${s['monitored'] == true ? '' : ' · Unmonitored'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      if (_movies)
                        SubtitleChips(
                          have: jsonList(s['subtitles']),
                          missing: jsonList(s['missing_subtitles']),
                        )
                      else
                        _ProgressBar(s, movies: false),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Subtitle coverage: for series the share of episodes with no missing
/// subtitles, for movies whether anything is missing.
class _ProgressBar extends StatelessWidget {
  final Json item;
  final bool movies;
  final bool thick;
  const _ProgressBar(this.item, {required this.movies, this.thick = false});

  @override
  Widget build(BuildContext context) {
    final int total;
    final int missing;
    if (movies) {
      final have = jsonList(item['subtitles']).length;
      missing = jsonList(item['missing_subtitles']).length;
      total = have + missing;
    } else {
      total = (item['episodeFileCount'] as num?)?.toInt() ?? 0;
      missing = (item['episodeMissingCount'] as num?)?.toInt() ?? 0;
    }
    final done = (total - missing).clamp(0, total);
    final color = total == 0
        ? Colors.grey
        : missing == 0
        ? Colors.green
        : (item['monitored'] == true ? Colors.redAccent : Colors.grey);
    final bar = LinearProgressIndicator(
      value: total == 0 ? 0 : done / total,
      minHeight: thick ? 5 : 6,
      color: color,
      backgroundColor: Colors.black38,
    );
    if (thick) return bar;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(borderRadius: BorderRadius.circular(4), child: bar),
        ),
        const SizedBox(width: 8),
        Text('$done/$total', style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
