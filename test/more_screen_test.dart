import 'dart:async';

import 'package:bazarr_app/screens/more_screen.dart';
import 'package:bazarr_app/services/api.dart';
import 'package:bazarr_app/services/app_state.dart';
import 'package:bazarr_app/services/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('connection settings stay accessible when server details fail', (
    tester,
  ) async {
    const config = ServerConfig(
      primaryUrl: 'http://bazarr',
      secondaryUrl: '',
      apiKey: 'test-key',
    );
    final response = Completer<http.Response>();
    final api = BazarrApi(config, client: MockClient((_) => response.future));
    final state = AppState(SettingsStore())
      ..config = config
      ..api = api;
    addTearDown(api.dispose);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: MoreScreen()),
      ),
    );
    final settings = find.byTooltip('Connection settings');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(settings.hitTestable(), findsOneWidget);

    response.complete(http.Response('Server unavailable', 500));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(find.text('Connection'), findsOneWidget);
    expect(find.text(config.primaryUrl), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });
}
