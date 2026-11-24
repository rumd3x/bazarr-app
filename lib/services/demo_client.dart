import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

typedef _J = Map<String, dynamic>;

/// In-memory fake Bazarr server used by demo mode. It answers the same
/// endpoints as the real API, so every screen works without a server.
class DemoServer {
  static const url = 'http://demo.bazarr.local';

  final DateTime _now = DateTime.now();
  final List<_J> _series = [];
  final Map<int, List<_J>> _episodes = {};
  final List<_J> _movies = [];
  final List<_J> _history = [];
  final List<_J> _movieHistory = [];
  final List<_J> _jobs = [];
  final List<_J> _tasks = [];
  var _nextId = 1000;

  DemoServer() {
    _seed();
  }

  http.Client client() => MockClient(_handle);

  static _J _lang(
    String name,
    String code2, {
    bool forced = false,
    bool hi = false,
  }) => {
    'name': name,
    'code2': code2,
    'code3': code2 == 'en' ? 'eng' : (code2 == 'pt' ? 'por' : 'spa'),
    'forced': forced,
    'hi': hi,
  };

  static const _providers = [
    'OpenSubtitles.com',
    'Subscene',
    'Podnapisi',
    'Addic7ed',
  ];

  static const _seriesSpecs = [
    (
      'Starfall Station',
      2021,
      3,
      8,
      'A crew of engineers keeps a failing deep-space station alive while uncovering why its original builders vanished.',
    ),
    (
      'The Lighthouse Files',
      2018,
      4,
      6,
      'A retired detective reopens cold cases from a remote island lighthouse, one tape recording at a time.',
    ),
    (
      'Midnight Kitchen',
      2022,
      2,
      10,
      'Chefs compete after dark in a hidden kitchen where the only rule is that every dish must tell a story.',
    ),
    (
      'Northern Lines',
      2020,
      2,
      8,
      'Rail workers in a snowbound country keep a single line open through one impossible winter.',
    ),
    (
      'Paper Kingdoms',
      2019,
      3,
      6,
      'Rival cartographers redraw the borders of an empire that exists only on their maps.',
    ),
  ];

  static const _movieSpecs = [
    (
      'Echoes of Tomorrow',
      2023,
      'A physicist receives messages from her future self, each one more worrying than the last.',
    ),
    (
      'The Quiet Harbor',
      2019,
      'A fishing town hides a secret that the new harbor master is determined to uncover.',
    ),
    (
      'Neon Drift',
      2024,
      'A courier races across a rain-soaked megacity with a package everyone wants.',
    ),
    (
      'Salt & Embers',
      2017,
      'Two estranged siblings reunite to scatter their father\'s ashes across three deserts.',
    ),
    (
      'Glass Orchard',
      2021,
      'An architect designs a greenhouse that slowly starts to grow back.',
    ),
    (
      'Last Train to Aurora',
      2022,
      'Strangers on an overnight train discover they share the same recurring dream.',
    ),
  ];

  void _seed() {
    final rnd = Random(7);
    var epId = 1;
    for (var i = 0; i < _seriesSpecs.length; i++) {
      final s = _seriesSpecs[i];
      final id = i + 1;
      final eps = <_J>[];
      for (var season = 1; season <= s.$3; season++) {
        for (var e = 1; e <= s.$4; e++) {
          final missing = rnd.nextInt(5) == 0;
          final noSubs = rnd.nextInt(9) == 0;
          eps.add({
            'sonarrEpisodeId': epId++,
            'sonarrSeriesId': id,
            'season': season,
            'episode': e,
            'title': 'Episode ${season}x$e',
            'monitored': true,
            'path': '/tv/${s.$1}/Season $season/${s.$1} - S${season}E$e.mkv',
            'sceneName':
                '${s.$1.replaceAll(' ', '.')}.S0${season}E${e.toString().padLeft(2, '0')}.1080p.WEB.x264',
            'audio_language': [
              {'name': 'English', 'code2': 'en', 'code3': 'eng'},
            ],
            'subtitles': noSubs
                ? []
                : [
                    {
                      ..._lang('English', 'en'),
                      'path': '/tv/${s.$1}/S${season}E$e.en.srt',
                      'file_size': 51200 + rnd.nextInt(30000),
                    },
                    if (!missing)
                      {
                        ..._lang('Portuguese', 'pt'),
                        'path': '/tv/${s.$1}/S${season}E$e.pt.srt',
                        'file_size': 48000 + rnd.nextInt(30000),
                      },
                    if (season == 1 && e == 1)
                      {..._lang('Spanish', 'es'), 'id': epId + 10000},
                  ],
            'missing_subtitles': [
              if (missing || noSubs) _lang('Portuguese', 'pt'),
              if (noSubs) _lang('English', 'en'),
            ],
          });
        }
      }
      _episodes[id] = eps;
      final missingCount = eps
          .where((e) => (e['missing_subtitles'] as List).isNotEmpty)
          .length;
      _series.add({
        'sonarrSeriesId': id,
        'title': s.$1,
        'year': '${s.$2}',
        'overview': s.$5,
        'monitored': true,
        'ended': i == 1,
        'path': '/tv/${s.$1}',
        'poster': null,
        'fanart': null,
        'profileId': 1,
        'seriesType': 'standard',
        'tags': [],
        'tvdbId': 1000 + id,
        'imdbId': 'tt00000$id',
        'audio_language': [
          {'name': 'English', 'code2': 'en', 'code3': 'eng'},
        ],
        'episodeFileCount': eps.length,
        'episodeMissingCount': missingCount,
        'lastAired': _now.subtract(Duration(days: 3 + i * 9)).toIso8601String(),
      });
    }

    for (var i = 0; i < _movieSpecs.length; i++) {
      final m = _movieSpecs[i];
      final missing = i % 3 == 0;
      _movies.add({
        'radarrId': i + 1,
        'title': m.$1,
        'year': '${m.$2}',
        'overview': m.$3,
        'monitored': i != 4,
        'path': '/movies/${m.$1} (${m.$2})/${m.$1}.mkv',
        'sceneName': '${m.$1.replaceAll(' ', '.')}.${m.$2}.1080p.BluRay.x264',
        'poster': null,
        'fanart': null,
        'profileId': 1,
        'tags': [],
        'tmdbId': 2000 + i,
        'imdbId': 'tt01000$i',
        'audio_language': [
          {'name': 'English', 'code2': 'en', 'code3': 'eng'},
        ],
        'subtitles': [
          {
            ..._lang('English', 'en'),
            'path': '/movies/${m.$1}.en.srt',
            'file_size': 70000 + i * 1500,
          },
          if (!missing)
            {
              ..._lang('Portuguese', 'pt'),
              'path': '/movies/${m.$1}.pt.srt',
              'file_size': 68000 + i * 1300,
            },
          if (i == 0) {..._lang('Spanish', 'es'), 'id': 20001},
        ],
        'missing_subtitles': [if (missing) _lang('Portuguese', 'pt')],
      });
    }

    for (var i = 0; i < 40; i++) {
      final when = _now.subtract(Duration(hours: i * 7 + 1));
      final lang = i % 4 == 3 ? 'Portuguese' : 'English';
      final code = lang == 'English' ? 'en' : 'pt';
      final provider = _providers[i % _providers.length];
      final desc = i % 9 == 8
          ? '$lang subtitles synced.'
          : i % 7 == 6
          ? '$lang subtitles upgraded from $provider with a score of ${90 + i % 9}%.'
          : '$lang subtitles downloaded from $provider with a score of ${88 + i % 11}%.';
      final base = {
        'id': i + 1,
        'action': i % 9 == 8 ? 5 : (i % 7 == 6 ? 3 : 1),
        'description': desc,
        'language': _lang(lang, code),
        'provider': provider,
        'score': '${88 + i % 11}%',
        'timestamp': '${i * 7 + 1} hours ago',
        'parsed_timestamp': when.toIso8601String(),
        'blacklisted': false,
        'upgradable': i % 7 == 6,
        'matches': ['series', 'year', 'season', 'episode'],
        'dont_matches': [],
        'subs_id': 'demo$i',
        'subtitles_path': '/demo/$i.$code.srt',
      };
      if (i.isEven) {
        final s = _series[i % _series.length];
        final eps = _episodes[s['sonarrSeriesId']]!;
        final e = eps[i % eps.length];
        _history.add({
          ...base,
          'seriesTitle': s['title'],
          'episodeTitle': e['title'],
          'episode_number': '${e['season']}x${e['episode']}',
          'sonarrSeriesId': s['sonarrSeriesId'],
          'sonarrEpisodeId': e['sonarrEpisodeId'],
          'monitored': true,
        });
      } else {
        final m = _movies[i % _movies.length];
        _movieHistory.add({
          ...base,
          'title': m['title'],
          'radarrId': m['radarrId'],
          'monitored': true,
          'path': m['path'],
        });
      }
    }

    _jobs.addAll([
      _job(
        3,
        'Searching for missing Series subtitles',
        'running',
        progress: (4, 12),
        message: 'Starfall Station - 1x4',
      ),
      _job(4, 'Updating Series from Sonarr', 'pending'),
      _job(5, 'Downloading wanted Movies subtitles', 'pending'),
      _job(2, 'Updating Movies from Radarr', 'completed', ago: 25),
      _job(1, 'Checking for new Bazarr releases', 'completed', ago: 90),
      _job(0, 'Syncing subtitles for Neon Drift', 'failed', ago: 180),
    ]);

    _tasks.addAll([
      _task(
        'update_series',
        'Update Series Metadata from Sonarr',
        '1 minute',
        'in 52 seconds',
      ),
      _task(
        'update_movies',
        'Update Movie Metadata from Radarr',
        '5 minutes',
        'in 3 minutes',
      ),
      _task(
        'wanted_search_missing_subtitles_series',
        'Search for Missing Series Subtitles',
        '6 hours',
        'in 2 hours',
      ),
      _task(
        'wanted_search_missing_subtitles_movies',
        'Search for Missing Movies Subtitles',
        '6 hours',
        'in 2 hours',
      ),
      _task(
        'upgrade_subtitles',
        'Upgrade Previously Downloaded Subtitles',
        '12 hours',
        'in 7 hours',
      ),
      _task(
        'backup',
        'Backup Database and Configuration File',
        'Daily',
        'in 5 hours',
      ),
    ]);
  }

  _J _job(
    int id,
    String name,
    String status, {
    (int, int)? progress,
    String? message,
    int? ago,
  }) => {
    'job_id': id,
    'job_name': name,
    'status': status,
    'last_run_time': ago == null
        ? null
        : _now.subtract(Duration(minutes: ago)).toIso8601String(),
    'is_progress': progress != null,
    'is_signalr': false,
    'progress_value': progress?.$1 ?? 0,
    'progress_max': progress?.$2 ?? 0,
    'progress_message': message ?? '',
  };

  _J _task(String id, String name, String interval, String next) => {
    'job_id': id,
    'name': name,
    'interval': interval,
    'next_run_in': next,
    'next_run_time': null,
    'job_running': false,
  };

  int _missingTotal(Iterable<_J> items) =>
      items.fold(0, (a, e) => a + (e['missing_subtitles'] as List).length);

  void _refreshSeriesCounts(int id) {
    final eps = _episodes[id]!;
    _series.firstWhere(
      (s) => s['sonarrSeriesId'] == id,
    )['episodeMissingCount'] = eps
        .where((e) => (e['missing_subtitles'] as List).isNotEmpty)
        .length;
  }

  Future<http.Response> _handle(http.Request r) async {
    final path = r.url.path.replaceFirst('/api', '');
    final q = r.url.queryParametersAll;
    String? one(String k) => q[k]?.first;
    int? oneInt(String k) => int.tryParse(one(k) ?? '');
    List<int> ids(String k) => [
      for (final v in q[k] ?? const <String>[]) ?int.tryParse(v),
    ];

    _J? media({int? episode, int? movie}) => movie != null
        ? _movies.where((m) => m['radarrId'] == movie).firstOrNull
        : _episodes.values
              .expand((episodes) => episodes)
              .where((e) => e['sonarrEpisodeId'] == episode)
              .firstOrNull;

    http.Response json(Object? body, [int code = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      code,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    http.Response ok() => http.Response('', 204);
    http.Response page(List<_J> all) {
      final start = oneInt('start') ?? 0;
      final length = oneInt('length') ?? -1;
      final slice = length > 0 ? all.skip(start).take(length).toList() : all;
      return json({'data': slice, 'total': all.length});
    }

    final m = r.method;
    switch ('$m $path') {
      case 'GET /system/status':
        return json({
          'data': {
            'bazarr_version': '1.6.2',
            'package_version': '',
            'sonarr_version': '4.0.14',
            'radarr_version': '5.21.1',
            'operating_system': 'Linux-demo',
            'python_version': '3.12.3',
            'database_engine': 'SQLite 3.46',
            'bazarr_directory': '/opt/bazarr',
            'bazarr_config_directory': '/config',
            'timezone': 'UTC',
            'cpu_cores': 4,
          },
        });
      case 'GET /system/health':
        return json({
          'data': [
            {
              'object': 'Subscene',
              'issue': 'Provider is throttled: too many requests.',
            },
          ],
        });
      case 'GET /badges':
        return json({
          'episodes': _missingTotal(_episodes.values.expand((e) => e)),
          'movies': _missingTotal(_movies),
          'providers': 1,
          'status': 1,
          'sonarr_signalr': 'LIVE',
          'radarr_signalr': 'LIVE',
          'announcements': 0,
        });
      case 'GET /providers':
        return json({
          'data': [
            for (var i = 0; i < _providers.length; i++)
              {
                'name': _providers[i],
                'status': i == 1 ? 'Throttled' : 'Good',
                'retry': i == 1 ? '14 minutes' : '-',
              },
          ],
        });
      case 'POST /providers':
        return ok();
      case 'GET /system/languages':
        return json([
          {..._lang('English', 'en'), 'enabled': true},
          {..._lang('Portuguese', 'pt'), 'enabled': true},
          {..._lang('Spanish', 'es'), 'enabled': true},
        ]);
      case 'GET /system/settings':
        return json({
          'translator': {'translator_type': 'google_translate'},
        });
      case 'GET /system/languages/profiles':
        return json([
          {
            'profileId': 1,
            'name': 'English + Portuguese',
            'cutoff': null,
            'items': [
              {'id': 1, 'language': 'en', 'forced': 'False', 'hi': 'False'},
              {'id': 2, 'language': 'pt', 'forced': 'False', 'hi': 'False'},
            ],
          },
          {
            'profileId': 2,
            'name': 'English only',
            'cutoff': null,
            'items': [
              {'id': 1, 'language': 'en', 'forced': 'False', 'hi': 'False'},
            ],
          },
        ]);
      case 'GET /series':
        final want = ids('seriesid[]');
        return json({
          'data': want.isEmpty
              ? _series
              : _series
                    .where((s) => want.contains(s['sonarrSeriesId']))
                    .toList(),
          'total': _series.length,
        });
      case 'PATCH /series':
        return ok();
      case 'POST /series':
        for (final id in ids('seriesid')) {
          _series.firstWhere((s) => s['sonarrSeriesId'] == id)['profileId'] =
              int.tryParse(one('profileid') ?? '');
        }
        return ok();
      case 'GET /episodes':
        final sids = ids('seriesid[]');
        final eids = ids('episodeid[]');
        return json({
          'data': [
            for (final e in _episodes.values.expand((e) => e))
              if (sids.contains(e['sonarrSeriesId']) ||
                  eids.contains(e['sonarrEpisodeId']))
                e,
          ],
        });
      case 'GET /movies':
        final want = ids('radarrid[]');
        return json({
          'data': want.isEmpty
              ? _movies
              : _movies.where((s) => want.contains(s['radarrId'])).toList(),
          'total': _movies.length,
        });
      case 'PATCH /movies':
        return ok();
      case 'POST /movies':
        for (final id in ids('radarrid')) {
          _movies.firstWhere((s) => s['radarrId'] == id)['profileId'] =
              int.tryParse(one('profileid') ?? '');
        }
        return ok();
      case 'GET /episodes/history':
        final id = oneInt('episodeid');
        return page(
          id == null
              ? _history
              : _history.where((h) => h['sonarrEpisodeId'] == id).toList(),
        );
      case 'GET /movies/history':
        final id = oneInt('radarrid');
        return page(
          id == null
              ? _movieHistory
              : _movieHistory.where((h) => h['radarrId'] == id).toList(),
        );
      case 'GET /providers/episodes':
      case 'GET /providers/movies':
        await Future<void>.delayed(const Duration(milliseconds: 900));
        return json({'data': _searchResults()});
      case 'POST /providers/episodes':
      case 'POST /providers/movies':
      case 'PATCH /episodes/subtitles':
      case 'PATCH /movies/subtitles':
        await Future<void>.delayed(const Duration(milliseconds: 600));
        _download(
          m == 'POST' ? null : one('language'),
          oneInt('episodeid'),
          oneInt('radarrid'),
          one('forced'),
          one('hi'),
        );
        return ok();
      case 'DELETE /episodes/subtitles':
      case 'DELETE /movies/subtitles':
        final item = media(
          episode: oneInt('episodeid'),
          movie: oneInt('radarrid'),
        );
        if (item == null) return json('Media not found', 404);
        (item['subtitles'] as List).removeWhere(
          (sub) => sub['path'] == one('path'),
        );
        return ok();
      case 'GET /subtitles':
        final item = media(
          episode: oneInt('sonarrEpisodeId'),
          movie: oneInt('radarrMovieId'),
        );
        if (item == null) return json('Media not found', 404);
        return json({
          'data': {
            'audio_tracks': [
              {'stream': 'a:0', 'name': 'English', 'language': 'en'},
            ],
            'embedded_subtitles_tracks': [
              for (final sub in item['subtitles'] as List)
                if (sub['path'] == null)
                  {
                    'stream': 's:0',
                    'name': sub['name'],
                    'language': sub['code2'],
                  },
            ],
            'external_subtitles_tracks': [
              for (final sub in item['subtitles'] as List)
                if (sub['path'] case final String path
                    when path != one('subtitlesPath'))
                  {
                    'name': path.split('/').last,
                    'path': path,
                    'language': sub['code2'],
                  },
            ],
          },
        });
      case 'GET /subtitles/contents':
        return json({'data': _subtitleCues()});
      case 'PATCH /subtitles':
        final form = r.bodyFields;
        final id = int.tryParse(form['id'] ?? '');
        final isMovie = form['type'] == 'movie';
        final item = isMovie ? media(movie: id) : media(episode: id);
        if (item == null) return json('Media not found', 404);
        final action = one('action');
        if (action == 'translate' || action == 'extract') {
          _download(
            form['language'],
            isMovie ? null : id,
            isMovie ? id : null,
            form['forced'],
            form['hi'],
          );
        }
        return ok();
      case 'GET /system/jobs':
        return json({'data': _jobs});
      case 'POST /system/jobs':
        final job = _jobs.firstWhere(
          (j) => j['job_id'] == oneInt('id'),
          orElse: () => {},
        );
        if (job.isNotEmpty && one('action') == 'force_start') {
          job['status'] = 'running';
        }
        return ok();
      case 'DELETE /system/jobs':
        _jobs.removeWhere((j) => j['job_id'] == oneInt('id'));
        return ok();
      case 'PATCH /system/jobs':
        _jobs.removeWhere((j) => j['status'] == one('queueName'));
        return ok();
      case 'GET /system/tasks':
        return json({'data': _tasks});
      case 'POST /system/tasks':
        final t = _tasks.firstWhere(
          (t) => t['job_id'] == one('taskid'),
          orElse: () => {},
        );
        if (t.isNotEmpty) {
          _jobs.insert(0, _job(_nextId++, '${t['name']}', 'pending'));
        }
        return ok();
    }
    return json({
      'message': 'Not found in demo: ${r.method} ${r.url.path}',
    }, 404);
  }

  List<_J> _searchResults() => [
    for (var i = 0; i < 6; i++)
      {
        'provider': _providers[i % _providers.length].toLowerCase().replaceAll(
          '.com',
          '',
        ),
        'subtitle': 'demo-sub-$i',
        'language': i < 4 ? 'en' : 'pt',
        'hearing_impaired': i == 2 ? 'True' : 'False',
        'forced': 'False',
        'original_format': 'False',
        'score': 96 - i * 7,
        'orig_score': 96 - i * 7,
        'release_info': ['Release.Group.1080p.WEB.x264-DEMO${i + 1}'],
        'uploader': 'uploader${i + 1}',
        'url': null,
        'matches': [
          'series',
          'year',
          'season',
          'episode',
          if (i < 3) 'release_group',
        ],
        'dont_matches': [if (i >= 3) 'release_group'],
      },
  ];

  List<_J> _subtitleCues() {
    _J time(int seconds, [int ms = 0]) => {
      'hours': 0,
      'minutes': 0,
      'seconds': seconds,
      'total_seconds': seconds,
      'microseconds': ms * 1000,
    };
    return [
      for (final (index, line) in [
        'We should leave before sunrise.',
        'Where are we going?',
        'I’ll tell you on the way.',
      ].indexed)
        {
          'index': index + 1,
          'content': line,
          'start': time(5 + index * 4, 250),
          'end': time(7 + index * 4, 750),
        },
    ];
  }

  void _download(
    String? language,
    int? episodeId,
    int? radarrId,
    String? forced,
    String? hi,
  ) {
    final targets = radarrId != null
        ? _movies.where((m) => m['radarrId'] == radarrId)
        : _episodes.values
              .expand((e) => e)
              .where((e) => e['sonarrEpisodeId'] == episodeId);
    for (final t in targets) {
      final missing = t['missing_subtitles'] as List;
      final code =
          language ?? (missing.isEmpty ? 'en' : missing.first['code2']);
      missing.removeWhere((l) => l['code2'] == code);
      final subs = t['subtitles'] as List;
      if (!subs.any((s) => s['code2'] == code && s['path'] != null)) {
        subs.add({
          ..._lang(
            switch (code) {
              'en' => 'English',
              'es' => 'Spanish',
              _ => 'Portuguese',
            },
            '$code',
            forced: forced == 'True',
            hi: hi == 'True',
          ),
          'path': '/demo/${_nextId++}.$code.srt',
          'file_size': 52000,
        });
      }
      if (episodeId != null) _refreshSeriesCounts(t['sonarrSeriesId'] as int);
    }
  }
}
