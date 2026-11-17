import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Resolves poster/fanart URLs from public, keyless metadata services using
/// the IDs Bazarr already returns. Bazarr's own `/images/...` proxy ignores the
/// API key (it needs a UI login), so it cannot be used from an API-key-only
/// client. Providers are tried in order until one returns artwork:
/// - series: Sonarr's TVDB mirror (`skyhook.sonarr.tv`, by `tvdbId`), then
///   TVmaze (by `tvdbId`, then `imdbId`; poster only).
/// - movies: Radarr's TMDB mirror (`api.radarr.video`, by `tmdbId`, then
///   `imdbId`).
///
/// Only public media IDs are sent (never the server URL or API key).
class ArtworkResolver {
  static const _prefsKey = 'cache_artwork';
  static const _timeout = Duration(seconds: 15);

  final http.Client _client;
  final Map<String, Map<String, String>> _cache = {};
  final Map<String, Future<Map<String, String>>> _inflight = {};
  Future<void>? _loaded;

  ArtworkResolver({http.Client? client}) : _client = client ?? http.Client();

  /// The lookup key for an item (`m|s` + ids), or null without any usable ID.
  static String? keyFor(Map<String, dynamic> item) {
    String id(String k) {
      final v = item[k];
      return v == null || '$v' == '0' ? '' : '$v';
    }

    final movie = item['radarrId'] != null;
    final ids = movie
        ? '${id('tmdbId')}|${id('imdbId')}'
        : '${id('tvdbId')}|${id('imdbId')}';
    return ids == '|' ? null : '${movie ? 'm' : 's'}:$ids';
  }

  /// Returns the artwork URL for [field] (`poster` or `fanart`), or null.
  Future<String?> resolve(Map<String, dynamic> item, String field) async {
    final key = keyFor(item);
    if (key == null) return null;
    await (_loaded ??= _load());
    var art = _cache[key];
    if (art == null) {
      art = await (_inflight[key] ??= _fetch(key));
      _inflight.remove(key);
    }
    return art[field];
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
      if (raw == null) return;
      (jsonDecode(raw) as Map).forEach((k, v) {
        _cache['$k'] = {
          for (final e in (v as Map).entries) '${e.key}': '${e.value}',
        };
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefsKey, jsonEncode(_cache));
    } catch (_) {}
  }

  Future<void> clear() async {
    _cache.clear();
    final p = await SharedPreferences.getInstance();
    await p.remove(_prefsKey);
  }

  Future<Map<String, String>> _fetch(String key) async {
    final movie = key.startsWith('m:');
    final ids = key.substring(2).split('|');
    final primary = ids[0], imdb = ids.length > 1 ? ids[1] : '';
    final urls = movie
        ? [
            if (primary.isNotEmpty)
              'https://api.radarr.video/v1/movie/$primary',
            if (imdb.isNotEmpty) 'https://api.radarr.video/v1/movie/imdb/$imdb',
          ]
        : [
            if (primary.isNotEmpty)
              'https://skyhook.sonarr.tv/v1/tvdb/shows/en/$primary',
            if (primary.isNotEmpty)
              'https://api.tvmaze.com/lookup/shows?thetvdb=$primary',
            if (imdb.isNotEmpty)
              'https://api.tvmaze.com/lookup/shows?imdb=$imdb',
          ];
    for (final url in urls) {
      final art = await _get(url);
      if (art.isNotEmpty) {
        // Only cache successful lookups so transient failures are retried.
        _cache[key] = art;
        await _save();
        return art;
      }
    }
    return {};
  }

  Future<Map<String, String>> _get(String url) async {
    final art = <String, String>{};
    try {
      final res = await _client.get(Uri.parse(url)).timeout(_timeout);
      if (res.statusCode != 200) return art;
      var j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is List && j.isNotEmpty) j = j.first;
      if (j is! Map) return art;
      final images = j['images'] ?? j['Images'];
      if (images is List) {
        for (final i in images.whereType<Map>()) {
          final type = '${i['coverType'] ?? i['CoverType']}'.toLowerCase();
          final u = '${i['url'] ?? i['Url'] ?? ''}';
          if (u.isEmpty) continue;
          if (type == 'poster') art.putIfAbsent('poster', () => _size(u, 500));
          if (type == 'fanart') art.putIfAbsent('fanart', () => _size(u, 780));
        }
      }
      final tvmaze = j['image'];
      if (tvmaze is Map && tvmaze['original'] != null) {
        art.putIfAbsent('poster', () => '${tvmaze['original']}');
      }
    } catch (_) {}
    return art;
  }

  /// TMDB serves resized variants; TVDB only has the original.
  static String _size(String url, int w) =>
      url.replaceFirst('/t/p/original/', '/t/p/w$w/');
}
