import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';
import 'services/app_state.dart';
import 'services/settings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(SettingsStore())..init(),
      child: const BazarrApp(),
    ),
  );
}

class BazarrApp extends StatelessWidget {
  const BazarrApp({super.key});

  static const _brand = Color(0xFFB44FC4);

  ThemeData _theme(Brightness b) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: _brand, brightness: b),
    appBarTheme: const AppBarTheme(centerTitle: false),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'Bazarr',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: !state.loaded
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : state.api == null
          ? const SetupScreen()
          : const HomeScreen(),
    );
  }
}
