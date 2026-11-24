import 'dart:convert';

import 'package:bazarr_app/screens/media_screen.dart';
import 'package:bazarr_app/screens/subtitle_tools.dart';
import 'package:bazarr_app/services/api.dart';
import 'package:bazarr_app/services/app_state.dart';
import 'package:bazarr_app/services/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

const _config = ServerConfig(
  primaryUrl: 'http://primary',
  secondaryUrl: 'http://secondary',
  apiKey: 'test',
);

const _external = {
  'id': 21,
  'name': 'English',
  'path': '/tv/episode.en.srt',
  'code2': 'en',
  'forced': true,
};

void main() {
  testWidgets(
    'episode sync waits for confirmation and sends selected options',
    (tester) async {
      final patches = <http.Request>[];
      final api = BazarrApi(
        _config,
        client: MockClient((request) async {
          if (request.method == 'PATCH') {
            patches.add(request);
            return http.Response('', 204);
          }
          if (request.url.path == '/api/subtitles') {
            expect(request.url.queryParameters, {
              'subtitlesPath': _external['path'],
              'sonarrEpisodeId': '12',
            });
            return http.Response(
              jsonEncode({
                'data': {
                  'audio_tracks': [
                    {'name': 'English', 'stream': 'a:0'},
                  ],
                  'embedded_subtitles_tracks': [null],
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'subtitles': [_external],
                },
              ],
            }),
            200,
          );
        }),
      );
      final state = AppState(SettingsStore())..api = api;
      addTearDown(api.dispose);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(
            home: MediaScreen(ref: MediaRef.episode(5, 12), title: 'Episode'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> openSync() async {
        await tester.tap(find.byTooltip('Subtitle tools for English forced'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sync'));
        await tester.pumpAndSettle();
        expect(find.text('Sync subtitle'), findsOneWidget);
      }

      await openSync();
      expect(patches, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(patches, isEmpty);

      await openSync();
      await tester.tap(find.text('Automatic'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Audio · English (a:0)').last);
      await tester.pumpAndSettle();
      final offset = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Maximum offset (seconds)',
      );
      await tester.tap(offset);
      await tester.pumpAndSettle();
      await tester.tap(find.text('120').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();
      final patch = patches.single;
      expect(patch.url.path, '/api/subtitles');
      expect(patch.url.queryParameters, {'action': 'sync'});
      expect(patch.bodyFields, {
        'type': 'episode',
        'id': '12',
        'language': 'en',
        'path': _external['path'],
        'subtitles_id': '21',
        'forced': 'True',
        'hi': 'False',
        'reference': 'a:0',
        'max_offset_seconds': '120',
        'no_fix_framerate': 'False',
        'gss': 'False',
      });
    },
  );

  test('embedded translation uses the track ID and target language', () async {
    final api = BazarrApi(
      _config,
      client: MockClient((request) async {
        expect(request.url.queryParameters, {'action': 'translate'});
        expect(request.bodyFields, {
          'type': 'movie',
          'id': '9',
          'language': 'es',
          'subtitles_id': '21',
          'forced': 'False',
          'hi': 'True',
          'original_format': 'True',
        });
        return http.Response('', 204);
      }),
    );
    addTearDown(api.dispose);

    await api.applySubtitleTool(
      const MediaRef.movie(9),
      {'id': 21, 'code2': 'en', 'hi': true},
      'translate',
      options: {'language': 'es', 'original_format': 'True'},
    );
  });

  testWidgets('preview renders subtitle formatting and can show raw cues', (
    tester,
  ) async {
    const raw = '<i><font color="#FF0000">Ready</font></i>';
    await tester.pumpWidget(
      MaterialApp(
        home: SubtitleCueScreen(
          title: 'Preview',
          load: () async => [
            {'index': 1, 'content': raw},
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final preview = tester.widget<Text>(find.text('Ready'));
    final span = (preview.textSpan as TextSpan).children!.single as TextSpan;
    expect(span.style?.fontStyle, FontStyle.italic);
    expect(span.style?.color, const Color(0xffff0000));
    await tester.tap(find.text('Raw'));
    await tester.pumpAndSettle();
    expect(find.text(raw), findsOneWidget);
  });

  testWidgets('two-point fit rejects reversed target times and uses both cues', (
    tester,
  ) async {
    final api = BazarrApi(ServerConfig.demo);
    addTearDown(api.dispose);
    SubtitleToolRequest? request;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            child: const Text('Fit'),
            onPressed: () async {
              request = await showDialog<SubtitleToolRequest>(
                context: context,
                builder: (_) => SubtitleToolDialog(
                  tool: SubtitleTool.fit,
                  api: api,
                  media: const MediaRef.episode(5, 12),
                  subtitle: _external,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fit'));
    await tester.pumpAndSettle();

    final times = find.byType(TextFormField);
    await tester.enterText(times.first, '00:00:06.500');
    await tester.enterText(times.last, '5');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('The last cue must follow the first'),
      findsOneWidget,
    );
    expect(request, isNull);

    await tester.enterText(times.last, '15.250');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(
      request?.action,
      'two_point_fit(rh=0,rm=0,rs=0,rms=5250,oh=0,om=0,os=0,oms=6500,from=8750,to=8000)',
    );
  });

  test('subtitle edits are not repeated on the secondary URL', () async {
    final hosts = <String>[];
    final api = BazarrApi(
      _config,
      client: MockClient((request) async {
        hosts.add(request.url.host);
        throw http.ClientException('Response lost');
      }),
    );
    addTearDown(api.dispose);
    await expectLater(
      api.applySubtitleTool(
        const MediaRef.episode(5, 12),
        _external,
        'shift_offset(h=0,m=0,s=0,ms=500)',
      ),
      throwsA(isA<ApiException>()),
    );
    expect(hosts, ['primary']);
  });

  test(
    'demo mode serves subtitle references, cues, and translation options',
    () async {
      final api = BazarrApi(ServerConfig.demo);
      addTearDown(api.dispose);
      final movie = (await api.movies()).first;
      final subtitle = (movie['subtitles'] as List).first as Json;
      final id = movie['radarrId'] as int;
      final path = subtitle['path'] as String;
      final references = await api.subtitleReferences(MediaRef.movie(id), path);
      expect(references['audio_tracks'], isNotEmpty);
      expect(references['embedded_subtitles_tracks'], isNotEmpty);
      expect(await api.subtitleContents(path), hasLength(3));
      expect(await api.enabledLanguages(), isNotEmpty);
      expect((await api.subtitleTranslator())['type'], 'google_translate');
      await api.applySubtitleTool(
        MediaRef.movie(id),
        subtitle,
        'translate',
        options: {'language': 'pt', 'original_format': 'True'},
      );
      final updated = (await api.movieById(id))!;
      expect(
        (updated['subtitles'] as List).any((sub) => sub['code2'] == 'pt'),
        isTrue,
      );
    },
  );
}
