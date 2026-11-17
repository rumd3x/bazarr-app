import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'media_screen.dart';

class SeriesDetailScreen extends StatefulWidget {
  final Json series;
  const SeriesDetailScreen({super.key, required this.series});

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  late Json _series;
  List<Json> _episodes = [];
  bool _loading = true;
  Object? _error;

  BazarrApi get _api => context.read<AppState>().api!;
  int get _id => _series['sonarrSeriesId'] as int;

  @override
  void initState() {
    super.initState();
    _series = widget.series;
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.seriesById(_id),
        _api.episodes(_id),
      ]);
      if (!mounted) return;
      setState(() {
        _series = (results[0] as Json?) ?? _series;
        _episodes = results[1] as List<Json>;
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

  Future<void> _run(Future<void> Function() action, String ok) async {
    try {
      await action();
      if (!mounted) return;
      toast(context, ok);
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _changeProfile() async {
    final id = await chooseProfile(context, _series['profileId'] as int?);
    if (id == null) return;
    await _run(
      () => _api.setSeriesProfile(_id, id < 0 ? null : id),
      'Profile updated',
    );
  }

  Map<int, List<Json>> get _bySeason {
    final map = <int, List<Json>>{};
    for (final e in _episodes) {
      map.putIfAbsent((e['season'] as num?)?.toInt() ?? 0, () => []).add(e);
    }
    for (final l in map.values) {
      l.sort(
        (a, b) => ((a['episode'] as num?) ?? 0).compareTo(
          (b['episode'] as num?) ?? 0,
        ),
      );
    }
    return map;
  }

  String _code(Json e) {
    String two(Object? n) => '$n'.padLeft(2, '0');
    return 'S${two(e['season'])}E${two(e['episode'])}';
  }

  @override
  Widget build(BuildContext context) {
    final bySeason = _bySeason;
    final seasons = bySeason.keys.toList()..sort((a, b) => b.compareTo(a));
    final monitored = _series['monitored'] == true;
    final overview = '${_series['overview'] ?? ''}';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 220,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  '${_series['title']}',
                  style: const TextStyle(shadows: [Shadow(blurRadius: 8)]),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Poster(_series, field: 'fanart'),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'scan':
                        _run(
                          () => _api.seriesAction(_id, 'scan-disk'),
                          'Disk scan started',
                        );
                      case 'missing':
                        _run(
                          () => _api.seriesAction(_id, 'search-missing'),
                          'Searching missing subtitles',
                        );
                      case 'sync':
                        _run(
                          () => _api.seriesAction(_id, 'sync'),
                          'Synced with Sonarr',
                        );
                      case 'profile':
                        _changeProfile();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'scan', child: Text('Scan disk')),
                    PopupMenuItem(
                      value: 'missing',
                      child: Text('Search missing subtitles'),
                    ),
                    PopupMenuItem(
                      value: 'sync',
                      child: Text('Sync with Sonarr'),
                    ),
                    PopupMenuItem(
                      value: 'profile',
                      child: Text('Languages profile'),
                    ),
                  ],
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text('${_series['year'] ?? ''}'),
                        Text(_series['ended'] == true ? 'Ended' : 'Continuing'),
                        Text(monitored ? 'Monitored' : 'Unmonitored'),
                        Text('${_series['episodeFileCount'] ?? 0} episodes'),
                        Text(
                          '${_series['episodeMissingCount'] ?? 0} missing subtitles',
                          style: TextStyle(
                            color:
                                ((_series['episodeMissingCount'] as num?) ??
                                        0) >
                                    0
                                ? Colors.redAccent
                                : Colors.greenAccent.shade400,
                          ),
                        ),
                      ],
                    ),
                    if (overview.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        overview,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorView(
                  error: _error!,
                  onRetry: () {
                    setState(() => _loading = true);
                    _load();
                  },
                ),
              )
            else
              SliverList.builder(
                itemCount: seasons.length,
                itemBuilder: (_, i) {
                  final n = seasons[i];
                  final eps = bySeason[n]!;
                  final missing = eps
                      .where((e) => jsonList(e['missing_subtitles']).isNotEmpty)
                      .length;
                  return Card(
                    margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: ExpansionTile(
                      initiallyExpanded: i == 0,
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: Text(n == 0 ? 'Specials' : 'Season $n'),
                      subtitle: Text(
                        '${eps.length - missing}/${eps.length} with subtitles',
                      ),
                      children: [for (final e in eps) _episodeTile(e)],
                    ),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _episodeTile(Json e) => ListTile(
    dense: true,
    title: Text(
      '${_code(e)} · ${e['title']}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SubtitleChips(
        have: jsonList(e['subtitles']),
        missing: jsonList(e['missing_subtitles']),
      ),
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () async {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MediaScreen(
            ref: MediaRef.episode(_id, e['sonarrEpisodeId'] as int),
            title: '${_series['title']}',
            subtitle: '${_code(e)} ${e['title']}',
            initial: e,
          ),
        ),
      );
      _load();
    },
  );
}
