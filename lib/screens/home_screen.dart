import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import 'history_screen.dart';
import 'jobs_screen.dart';
import 'library_screen.dart';
import 'more_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  void _startPolling() {
    final state = context.read<AppState>();
    state.refreshActiveJobs();
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => state.refreshActiveJobs(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _startPolling();
    } else if (s == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jobs = context.select<AppState, int>((s) => s.activeJobs);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const LibraryScreen(movies: false),
          const LibraryScreen(movies: true),
          const HistoryScreen(),
          JobsScreen(active: _index == 3),
          const MoreScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library),
            label: 'Series',
          ),
          const NavigationDestination(
            icon: Icon(Icons.movie_outlined),
            selectedIcon: Icon(Icons.movie),
            label: 'Movies',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: jobs > 0,
              label: Text('$jobs'),
              child: const Icon(Icons.work_history_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: jobs > 0,
              label: Text('$jobs'),
              child: const Icon(Icons.work_history),
            ),
            label: 'Jobs',
          ),
          const NavigationDestination(
            icon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
