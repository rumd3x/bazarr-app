import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'demo_client.dart';
import 'settings.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

typedef Json = Map<String, dynamic>;

/// One page of a paginated Bazarr list (`{"data": [...], "total": n}`).
class ListPage {
  final List<Json> items;
  final int total;
  const ListPage(this.items, this.total);
}

/// Bazarr API client. Tries the primary URL first and falls back to the
/// secondary URL when the primary is unreachable.
class BazarrApi {
  final ServerConfig config;
  final http.Client _client;
  static const _timeout = Duration(seconds: 15);

  /// Searching the subtitle providers can take minutes.
  static const searchTimeout = Duration(minutes: 5);

  String? _activeBase;

  BazarrApi(this.config, {http.Client? client})
    : _client =
          client ?? (config.isDemo ? DemoServer().client() : http.Client());

  bool get isDemo => config.isDemo;

  List<String> get _bases => [
    ?_activeBase,
    for (final u in [config.primaryUrl, config.secondaryUrl])
      if (u.isNotEmpty && u != _activeBase) u,
  ];

  String? get activeBase => _activeBase;

  Map<String, String> get headers => {
    'X-API-KEY': config.apiKey,
    'Accept': 'application/json',
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
  };

  /// Absolute URL for an image path returned by Bazarr (e.g. `/images/...`).
  String? imageUrl(Object? path) {
    final p = path is String ? path : '';
    if (p.isEmpty) return null;
    if (p.startsWith('http')) return p;
    final base = _activeBase ?? config.primaryUrl;
    return '$base${p.startsWith('/') ? '' : '/'}$p';
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Duration timeout = _timeout,
  }) async {
    Object? lastError;
    for (final base in _bases) {
      try {
        final uri = Uri.parse('$base/api$path').replace(
          queryParameters: query?.map(
            (k, val) =>
                MapEntry(k, val is List ? [for (final e in val) '$e'] : '$val'),
          ),
        );
        final req = http.Request(method, uri)..headers.addAll(headers);
        final res = await http.Response.fromStream(
          await _client.send(req).timeout(timeout),
        );
        _activeBase = base;
        if (res.statusCode == 401) {
          throw ApiException('Invalid API key', 401);
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw ApiException(_errorMessage(res), res.statusCode);
        }
        if (res.body.isEmpty) return null;
        return jsonDecode(utf8.decode(res.bodyBytes));
      } on ApiException {
        rethrow;
      } on Exception catch (e) {
        lastError = e;
      }
    }
    throw ApiException('Could not reach Bazarr (${lastError ?? 'no URL'})');
  }

  String _errorMessage(http.Response res) {
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is String && j.isNotEmpty) return j;
      if (j is Map && j['message'] != null) return j['message'].toString();
    } catch (_) {}
    return 'Request failed (${res.statusCode})';
  }

  // ---- System ----
  Future<Json> systemStatus() async {
    final r = await _send('GET', '/system/status');
    return Json.from((r is Map ? r['data'] : null) as Map? ?? const {});
  }

  Future<List<Json>> health() async =>
      _data(await _send('GET', '/system/health'));

  Future<Json> badges() async =>
      Json.from(await _send('GET', '/badges') as Map? ?? const {});

  Future<List<Json>> providers() async =>
      _data(await _send('GET', '/providers'));

  Future<void> resetProviders() =>
      _send('POST', '/providers', query: {'action': 'reset'});

  Future<List<Json>> languageProfiles() async =>
      _list(await _send('GET', '/system/languages/profiles'));

  // ---- Series ----
  Future<List<Json>> series() async =>
      _data(await _send('GET', '/series', timeout: searchTimeout));

  Future<Json?> seriesById(int id) async {
    final l = _data(
      await _send(
        'GET',
        '/series',
        query: {
          'seriesid[]': [id],
        },
      ),
    );
    return l.isEmpty ? null : l.first;
  }

  Future<void> seriesAction(int id, String action) => _send(
    'PATCH',
    '/series',
    query: {'seriesid': id, 'action': action},
    timeout: searchTimeout,
  );

  Future<void> setSeriesProfile(int id, int? profileId) => _send(
    'POST',
    '/series',
    query: {
      'seriesid': [id],
      'profileid': [profileId ?? 'none'],
    },
  );

  Future<List<Json>> episodes(int seriesId) async => _data(
    await _send(
      'GET',
      '/episodes',
      query: {
        'seriesid[]': [seriesId],
      },
    ),
  );

  Future<Json?> episodeById(int episodeId) async {
    final l = _data(
      await _send(
        'GET',
        '/episodes',
        query: {
          'episodeid[]': [episodeId],
        },
      ),
    );
    return l.isEmpty ? null : l.first;
  }

  Future<ListPage> episodeHistory({
    int start = 0,
    int length = 50,
    int? episodeId,
  }) => _page('/episodes/history', {
    'start': start,
    'length': length,
    'episodeid': ?episodeId,
  });

  // ---- Movies ----
  Future<List<Json>> movies() async =>
      _data(await _send('GET', '/movies', timeout: searchTimeout));

  Future<Json?> movieById(int id) async {
    final l = _data(
      await _send(
        'GET',
        '/movies',
        query: {
          'radarrid[]': [id],
        },
      ),
    );
    return l.isEmpty ? null : l.first;
  }

  Future<void> movieAction(int id, String action) => _send(
    'PATCH',
    '/movies',
    query: {'radarrid': id, 'action': action},
    timeout: searchTimeout,
  );

  Future<void> setMovieProfile(int id, int? profileId) => _send(
    'POST',
    '/movies',
    query: {
      'radarrid': [id],
      'profileid': [profileId ?? 'none'],
    },
  );

  Future<ListPage> movieHistory({
    int start = 0,
    int length = 50,
    int? radarrId,
  }) => _page('/movies/history', {
    'start': start,
    'length': length,
    'radarrid': ?radarrId,
  });

  // ---- Subtitles ----
  /// Searches the providers for subtitles of an episode or a movie.
  Future<List<Json>> searchSubtitles(MediaRef m) async => _data(
    await _send(
      'GET',
      m.isMovie ? '/providers/movies' : '/providers/episodes',
      query: m.isMovie ? {'radarrid': m.id} : {'episodeid': m.id},
      timeout: searchTimeout,
    ),
  );

  Future<void> downloadSubtitle(MediaRef m, Json result) => _send(
    'POST',
    m.isMovie ? '/providers/movies' : '/providers/episodes',
    query: {
      if (m.isMovie)
        'radarrid': m.id
      else ...{
        'seriesid': m.seriesId,
        'episodeid': m.id,
      },
      'hi': _bool(result['hearing_impaired']),
      'forced': _bool(result['forced']),
      'original_format': _bool(result['original_format']),
      'provider': result['provider'],
      'subtitle': result['subtitle'],
    },
    timeout: searchTimeout,
  );

  /// Automatically searches and downloads one missing/wanted language.
  Future<void> autoDownload(MediaRef m, Json language) => _send(
    'PATCH',
    m.isMovie ? '/movies/subtitles' : '/episodes/subtitles',
    query: {
      if (m.isMovie)
        'radarrid': m.id
      else ...{
        'seriesid': m.seriesId,
        'episodeid': m.id,
      },
      'language': language['code2'],
      'forced': _bool(language['forced']),
      'hi': _bool(language['hi']),
    },
    timeout: searchTimeout,
  );

  Future<void> deleteSubtitle(MediaRef m, Json subtitle) => _send(
    'DELETE',
    m.isMovie ? '/movies/subtitles' : '/episodes/subtitles',
    query: {
      if (m.isMovie)
        'radarrid': m.id
      else ...{
        'seriesid': m.seriesId,
        'episodeid': m.id,
      },
      'language': subtitle['code2'],
      'forced': _bool(subtitle['forced']),
      'hi': _bool(subtitle['hi']),
      'path': subtitle['path'],
    },
  );

  Future<void> syncSubtitle(MediaRef m, Json subtitle) => _send(
    'PATCH',
    '/subtitles',
    query: {
      'action': 'sync',
      'type': m.isMovie ? 'movie' : 'episode',
      'id': m.id,
      'language': subtitle['code2'],
      'path': subtitle['path'],
      'forced': _bool(subtitle['forced']),
      'hi': _bool(subtitle['hi']),
    },
    timeout: searchTimeout,
  );

  // ---- Jobs & tasks ----
  Future<List<Json>> jobs() async => _data(await _send('GET', '/system/jobs'));

  Future<void> jobAction(int id, String action) =>
      _send('POST', '/system/jobs', query: {'id': id, 'action': action});

  Future<void> deleteJob(int id) =>
      _send('DELETE', '/system/jobs', query: {'id': id});

  Future<void> emptyJobs(String queue) =>
      _send('PATCH', '/system/jobs', query: {'queueName': queue});

  Future<List<Json>> tasks() async =>
      _data(await _send('GET', '/system/tasks'));

  Future<void> runTask(String id) =>
      _send('POST', '/system/tasks', query: {'taskid': id});

  // ---- Helpers ----
  Future<ListPage> _page(String path, Map<String, dynamic> query) async {
    final r = await _send('GET', path, query: query);
    return ListPage(_data(r), (r is Map ? r['total'] as int? : null) ?? 0);
  }

  static String _bool(Object? v) =>
      (v == true || '$v'.toLowerCase() == 'true') ? 'True' : 'False';

  List<Json> _data(dynamic r) => _list(r is Map ? r['data'] : r);

  List<Json> _list(dynamic v) =>
      (v as List? ?? const []).map((e) => Json.from(e as Map)).toList();

  void dispose() => _client.close();
}

/// Identifies the episode or movie a subtitle operation applies to.
class MediaRef {
  final bool isMovie;

  /// Episode id (`sonarrEpisodeId`) or movie id (`radarrId`).
  final int id;

  /// Series id (`sonarrSeriesId`), only for episodes.
  final int? seriesId;

  const MediaRef.episode(this.seriesId, this.id) : isMovie = false;
  const MediaRef.movie(this.id) : isMovie = true, seriesId = null;
}
