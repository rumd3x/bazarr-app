import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'artwork.dart';
import 'settings.dart';

class AppState extends ChangeNotifier {
  final SettingsStore store;
  ServerConfig? config;
  BazarrApi? api;
  final artwork = ArtworkResolver();
  bool loaded = false;

  /// Jobs that are running or waiting in the queue (Jobs tab badge).
  int activeJobs = 0;

  AppState(this.store);

  Future<void> init() async {
    config = await store.load();
    if (config != null) api = BazarrApi(config!);
    loaded = true;
    notifyListeners();
  }

  Future<void> setConfig(ServerConfig c) async {
    await store.save(c);
    config = await store.load();
    api?.dispose();
    api = config == null ? null : BazarrApi(config!);
    activeJobs = 0;
    notifyListeners();
  }

  Future<void> reset() async {
    await store.clear();
    final p = await SharedPreferences.getInstance();
    await p.remove(_kSeries);
    await p.remove(_kMovies);
    await artwork.clear();
    api?.dispose();
    api = null;
    config = null;
    activeJobs = 0;
    notifyListeners();
  }

  /// Refreshes the number of active jobs (Jobs tab badge).
  Future<void> refreshActiveJobs() async {
    final client = api;
    if (client == null) return;
    try {
      final jobs = await client.jobs();
      final n = jobs
          .where((j) => j['status'] == 'running' || j['status'] == 'pending')
          .length;
      if (n != activeJobs && api == client) {
        activeJobs = n;
        notifyListeners();
      }
    } catch (_) {}
  }

  // Local cache of the libraries so they open instantly / offline.
  static const _kSeries = 'cache_series';
  static const _kMovies = 'cache_movies';

  static const _slimKeys = [
    'sonarrSeriesId',
    'radarrId',
    'title',
    'year',
    'monitored',
    'poster',
    'ended',
    'profileId',
    'episodeFileCount',
    'episodeMissingCount',
    'subtitles',
    'missing_subtitles',
    'lastAired',
  ];

  Future<List<Json>?> cachedSeries() => _read(_kSeries);
  Future<List<Json>?> cachedMovies() => _read(_kMovies);
  Future<void> cacheSeries(List<Json> list) => _write(_kSeries, list);
  Future<void> cacheMovies(List<Json> list) => _write(_kMovies, list);

  Future<List<Json>?> _read(String key) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(key);
    if (s == null) return null;
    try {
      return (jsonDecode(s) as List).map((e) => Json.from(e as Map)).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, List<Json> list) async {
    final p = await SharedPreferences.getInstance();
    // Drop bulky fields not needed for the list view.
    final slim = [
      for (final i in list)
        {
          for (final k in _slimKeys)
            if (i.containsKey(k)) k: i[k],
        },
    ];
    await p.setString(key, jsonEncode(slim));
  }
}
