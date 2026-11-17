import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bazarr_app/services/api.dart';
import 'package:bazarr_app/services/artwork.dart';
import 'package:bazarr_app/services/settings.dart';

void main() {
  test('normalizeUrl adds scheme and strips trailing slash', () {
    expect(
      ServerConfig.normalizeUrl('192.168.1.2:6767/'),
      'http://192.168.1.2:6767',
    );
    expect(ServerConfig.normalizeUrl(''), '');
  });

  test('falls back to secondary URL and sends API key', () async {
    String? key;
    Uri? last;
    final api = BazarrApi(
      const ServerConfig(
        primaryUrl: 'http://primary',
        secondaryUrl: 'http://secondary',
        apiKey: 'abc',
      ),
      client: MockClient((req) async {
        if (req.url.host == 'primary') throw http.ClientException('down');
        key = req.headers['X-API-KEY'];
        last = req.url;
        return http.Response('{"data":{"bazarr_version":"1.5"}}', 200);
      }),
    );
    final status = await api.systemStatus();
    expect(status['bazarr_version'], '1.5');
    expect(key, 'abc');
    expect(last!.path, '/api/system/status');
  });

  test('demo mode serves the main lists', () async {
    final api = BazarrApi(ServerConfig.demo);
    expect(await api.series(), isNotEmpty);
    expect(await api.movies(), isNotEmpty);
    expect(await api.jobs(), isNotEmpty);
    expect(await api.tasks(), isNotEmpty);
    expect((await api.movieHistory()).items, isNotEmpty);
  });

  test('artwork falls back from Sonarr mirror to TVmaze by id', () async {
    final seen = <String>[];
    final art = ArtworkResolver(
      client: MockClient((req) async {
        seen.add(req.url.host);
        if (req.url.host == 'api.tvmaze.com') {
          return http.Response('{"image":{"original":"https://x/p.jpg"}}', 200);
        }
        return http.Response('', 404);
      }),
    );
    final url = await art.resolve({
      'sonarrSeriesId': 1,
      'tvdbId': 42,
    }, 'poster');
    expect(url, 'https://x/p.jpg');
    expect(seen, ['skyhook.sonarr.tv', 'api.tvmaze.com']);
    expect(ArtworkResolver.keyFor({'radarrId': 1, 'imdbId': 'tt1'}), 'm:|tt1');
    expect(ArtworkResolver.keyFor({'sonarrSeriesId': 1}), isNull);
  });
}
