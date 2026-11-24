import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'history_screen.dart';
import 'subtitle_tools.dart';

/// Lets the user pick a languages profile. Returns `null` when cancelled and
/// `-1` when "no profile" was chosen.
Future<int?> chooseProfile(BuildContext context, int? current) async {
  final api = context.read<AppState>().api!;
  List<Json> profiles;
  try {
    profiles = await api.languageProfiles();
  } catch (e) {
    if (context.mounted) toast(context, '$e');
    return null;
  }
  if (!context.mounted) return null;
  return showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Languages profile'),
      children: [
        for (final p in [
          {'profileId': -1, 'name': 'None'},
          ...profiles,
        ])
          ListTile(
            leading: Icon(
              p['profileId'] == (current ?? -1)
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            title: Text('${p['name']}'),
            onTap: () => Navigator.pop(ctx, p['profileId'] as int),
          ),
      ],
    ),
  );
}

/// Details of one episode or movie: subtitle files (with the missing ones),
/// history and a manual search across the subtitle providers.
class MediaScreen extends StatefulWidget {
  final MediaRef ref;
  final String title;
  final String? subtitle;

  /// Already known data (e.g. from the library list) shown while loading.
  final Json? initial;
  final int initialTab;

  const MediaScreen({
    super.key,
    required this.ref,
    required this.title,
    this.subtitle,
    this.initial,
    this.initialTab = 0,
  });

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  Json? _item;
  Object? _error;
  int _historyVersion = 0;
  bool _applyingSubtitleTool = false;

  // Manual search state lives here so it survives tab switches.
  List<Json>? _results;
  Object? _searchError;
  bool _searching = false;
  String? _downloading;

  BazarrApi get _api => context.read<AppState>().api!;
  MediaRef get _ref => widget.ref;

  @override
  void initState() {
    super.initState();
    _item = widget.initial;
    _load();
  }

  Future<void> _load() async {
    try {
      final item = await (_ref.isMovie
          ? _api.movieById(_ref.id)
          : _api.episodeById(_ref.id));
      if (!mounted) return;
      setState(() {
        _item = item ?? _item;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
      });
    }
  }

  Future<void> _run(Future<void> Function() action, String ok) async {
    try {
      await action();
      if (!mounted) return;
      toast(context, ok);
      setState(() => _historyVersion++);
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final r = await _api.searchSubtitles(_ref);
      r.sort(
        (a, b) =>
            ((b['score'] as num?) ?? 0).compareTo((a['score'] as num?) ?? 0),
      );
      if (!mounted) return;
      setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _searchError = e);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _download(Json result) async {
    setState(
      () => _downloading = '${result['provider']}:${result['subtitle']}',
    );
    try {
      await _api.downloadSubtitle(_ref, result);
      if (!mounted) return;
      toast(context, 'Subtitle downloaded');
      setState(() => _historyVersion++);
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  Future<void> _delete(Json sub) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete subtitle?'),
        content: Text('${languageLabel(sub)} subtitle file will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() => _api.deleteSubtitle(_ref, sub), 'Subtitle deleted');
  }

  Future<void> _useSubtitleTool(SubtitleTool tool, Json subtitle) async {
    if (_applyingSubtitleTool) return;
    if (tool == SubtitleTool.preview) {
      final path = subtitle['path'] as String;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => SubtitleCueScreen(
            title: subtitleFileName(path),
            load: () => _api.subtitleContents(path),
          ),
        ),
      );
      return;
    }

    setState(() => _applyingSubtitleTool = true);
    try {
      if (tool == SubtitleTool.delete) {
        await _delete(subtitle);
        return;
      }
      final SubtitleToolRequest? request = switch (tool) {
        SubtitleTool.sync ||
        SubtitleTool.color ||
        SubtitleTool.frameRate ||
        SubtitleTool.offset ||
        SubtitleTool.fit ||
        SubtitleTool.translate => await showDialog<SubtitleToolRequest>(
          context: context,
          builder: (_) => SubtitleToolDialog(
            tool: tool,
            api: _api,
            media: _ref,
            subtitle: subtitle,
          ),
        ),
        _ => (action: tool.action!, options: const <String, String>{}),
      };
      if (request == null || !mounted) return;

      final success = switch (tool) {
        SubtitleTool.sync => 'Subtitle sync requested',
        SubtitleTool.translate => 'Subtitle translation requested',
        SubtitleTool.extract => 'Subtitle extraction requested',
        _ => 'Subtitle updated',
      };
      await _run(() async {
        await _api.applySubtitleTool(
          _ref,
          subtitle,
          request.action,
          options: request.options,
        );
        if (mounted) context.read<AppState>().refreshActiveJobs();
      }, success);
    } finally {
      if (mounted) setState(() => _applyingSubtitleTool = false);
    }
  }

  Future<void> _movieAction(String action, String ok) =>
      _run(() => _api.movieAction(_ref.id, action), ok);

  Future<void> _changeProfile() async {
    final id = await chooseProfile(context, _item?['profileId'] as int?);
    if (id == null) return;
    await _run(
      () => _api.setMovieProfile(_ref.id, id < 0 ? null : id),
      'Profile updated',
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                Text(
                  widget.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
            ],
          ),
          actions: [
            if (_ref.isMovie)
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'scan':
                      _movieAction('scan-disk', 'Disk scan started');
                    case 'missing':
                      _movieAction(
                        'search-missing',
                        'Searching missing subtitles',
                      );
                    case 'sync':
                      _movieAction('sync', 'Synced with Radarr');
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
                  PopupMenuItem(value: 'sync', child: Text('Sync with Radarr')),
                  PopupMenuItem(
                    value: 'profile',
                    child: Text('Languages profile'),
                  ),
                ],
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Subtitles'),
              Tab(text: 'History'),
              Tab(text: 'Search'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildSubtitles(item),
            _MediaHistory(key: ValueKey(_historyVersion), media: _ref),
            _buildSearch(),
          ],
        ),
      ),
    );
  }

  Widget _buildSubtitles(Json? item) {
    if (item == null) {
      if (_error != null) {
        return ErrorView(
          error: _error!,
          onRetry: () {
            setState(() => _error = null);
            _load();
          },
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final have = jsonList(item['subtitles']);
    final missing = jsonList(item['missing_subtitles']);
    final audio = jsonList(
      item['audio_language'],
    ).map((l) => '${l['name']}').join(', ');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_ref.isMovie) _MovieHeader(item),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ('${item['path'] ?? ''}'.isNotEmpty)
                    _Info(Icons.folder_outlined, '${item['path']}'),
                  if ('${item['sceneName'] ?? ''}'.isNotEmpty &&
                      item['sceneName'] != null)
                    _Info(Icons.movie_filter_outlined, '${item['sceneName']}'),
                  if (audio.isNotEmpty)
                    _Info(Icons.volume_up_outlined, 'Audio: $audio'),
                  if (item['monitored'] != null)
                    _Info(
                      item['monitored'] == true
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      item['monitored'] == true ? 'Monitored' : 'Unmonitored',
                    ),
                ],
              ),
            ),
          ),
          const SectionHeader('Subtitles'),
          if (have.isEmpty)
            const Card(child: ListTile(title: Text('No subtitles found')))
          else
            for (final s in have) _subtitleTile(s),
          if (missing.isNotEmpty) const SectionHeader('Missing'),
          for (final l in missing)
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.subtitles_off_outlined,
                  color: Colors.redAccent,
                ),
                title: Text(languageLabel(l)),
                subtitle: const Text('Not downloaded'),
                trailing: FilledButton.tonalIcon(
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Auto search'),
                  onPressed: () => _run(
                    () => _api.autoDownload(_ref, l),
                    'Subtitle search requested',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _subtitleTile(Json s) {
    final path = '${s['path'] ?? ''}';
    final embedded = path.isEmpty;
    final size = s['file_size'];
    final tools = embedded
        ? [
            if (s['id'] case final int id when id > 0) ...[
              SubtitleTool.translate,
              SubtitleTool.extract,
            ],
          ]
        : [
            for (final tool in SubtitleTool.values)
              if (tool != SubtitleTool.extract) tool,
          ];
    return Card(
      child: ListTile(
        leading: Icon(
          embedded ? Icons.video_file_outlined : Icons.subtitles,
          color: Colors.greenAccent.shade400,
        ),
        title: Text(languageLabel(s)),
        subtitle: Text(
          embedded
              ? 'Embedded in the video'
              : '${subtitleFileName(path)}${size is num ? ' · ${formatBytes(size)}' : ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: tools.isEmpty
            ? null
            : PopupMenuButton<SubtitleTool>(
                tooltip: 'Subtitle tools for ${languageLabel(s)}',
                enabled: !_applyingSubtitleTool,
                onSelected: (tool) => _useSubtitleTool(tool, s),
                itemBuilder: (_) => [
                  for (final tool in tools)
                    PopupMenuItem(value: tool, child: Text(tool.label)),
                ],
              ),
      ),
    );
  }

  Widget _buildSearch() {
    if (_searching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Searching providers…'),
          ],
        ),
      );
    }
    if (_searchError != null) {
      return ErrorView(error: _searchError!, onRetry: _search);
    }
    final results = _results;
    if (results == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.manage_search, size: 56),
            const SizedBox(height: 12),
            const Text('Search all providers for subtitles'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _search,
              icon: const Icon(Icons.search),
              label: const Text('Search'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _search,
      child: results.isEmpty
          ? const EmptyView(Icons.subtitles_off_outlined, 'No subtitles found')
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: results.length,
              itemBuilder: (_, i) => _resultCard(results[i]),
            ),
    );
  }

  Widget _resultCard(Json r) {
    final cs = Theme.of(context).colorScheme;
    final score = (r['score'] as num?)?.toInt() ?? 0;
    final color = score >= 90
        ? Colors.green
        : score >= 70
        ? Colors.orange
        : Colors.redAccent;
    final release = (r['release_info'] is List)
        ? (r['release_info'] as List).join(' · ')
        : '${r['release_info'] ?? ''}';
    final matches = (r['matches'] as List?)?.length ?? 0;
    final misses = (r['dont_matches'] as List?)?.length ?? 0;
    final busy = _downloading == '${r['provider']}:${r['subtitle']}';
    final tags = [
      '${r['language']}'.toUpperCase(),
      if ('${r['hearing_impaired']}'.toLowerCase() == 'true') 'HI',
      if ('${r['forced']}'.toLowerCase() == 'true') 'Forced',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    '$score%',
                    style: TextStyle(fontWeight: FontWeight.bold, color: color),
                  ),
                  Text(tags.join(' '), style: const TextStyle(fontSize: 10)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    release.isEmpty ? '${r['provider']}' : release,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${r['provider']} · ${r['uploader'] ?? '—'} · '
                    '$matches matches${misses > 0 ? ', $misses misses' : ''}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Download',
              onPressed: _downloading != null ? null : () => _download(r),
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
            ),
          ],
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Info(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}

class _MovieHeader extends StatelessWidget {
  final Json movie;
  const _MovieHeader(this.movie);

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          height: 150,
          child: Poster(movie, icon: Icons.movie),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${movie['title']} (${movie['year'] ?? ''})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  '${movie['overview'] ?? ''}',
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _MediaHistory extends StatelessWidget {
  final MediaRef media;
  const _MediaHistory({super.key, required this.media});

  @override
  Widget build(BuildContext context) => AsyncBody<ListPage>(
    load: (api) => media.isMovie
        ? api.movieHistory(length: 100, radarrId: media.id)
        : api.episodeHistory(length: 100, episodeId: media.id),
    builder: (context, page) => page.items.isEmpty
        ? const EmptyView(Icons.history, 'No history for this item')
        : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: page.items.length,
            itemBuilder: (_, i) => HistoryTile(
              page.items[i],
              movie: media.isMovie,
              showMedia: false,
            ),
          ),
  );
}
