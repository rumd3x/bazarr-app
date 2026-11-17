import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'setup_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: AsyncBody<List<dynamic>>(
        load: (api) => Future.wait([
          api.systemStatus(),
          api.health(),
          api.badges(),
          api.providers(),
        ]),
        builder: (context, data) {
          final status = data[0] as Json;
          final health = data[1] as List<Json>;
          final badges = data[2] as Json;
          final providers = data[3] as List<Json>;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: ListTile(
                  leading: Image.asset('assets/branding/logo.png', width: 36),
                  title: Text('Bazarr ${status['bazarr_version']}'),
                  subtitle: Text(
                    state.config?.isDemo == true
                        ? 'Demo mode · sample data'
                        : '${state.api?.activeBase ?? state.config?.primaryUrl}',
                  ),
                ),
              ),
              const SectionHeader('Wanted subtitles'),
              Row(
                children: [
                  Expanded(
                    child: _Counter(
                      Icons.video_library_outlined,
                      'Episodes',
                      '${badges['episodes'] ?? 0}',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Counter(
                      Icons.movie_outlined,
                      'Movies',
                      '${badges['movies'] ?? 0}',
                    ),
                  ),
                ],
              ),
              const SectionHeader('Health'),
              if (health.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.check_circle, color: Colors.green),
                    title: Text('All good'),
                  ),
                )
              else
                for (final h in health)
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.warning_amber,
                        color: Colors.orange,
                      ),
                      title: Text('${h['issue']}'),
                      subtitle: Text('${h['object']}'),
                    ),
                  ),
              const SectionHeader('Providers'),
              _ProvidersCard(providers: providers),
              const SectionHeader('Connections'),
              Card(
                child: Column(
                  children: [
                    _StatusTile(
                      'Sonarr',
                      '${status['sonarr_version'] ?? ''}',
                      '${badges['sonarr_signalr'] ?? ''}',
                    ),
                    _StatusTile(
                      'Radarr',
                      '${status['radarr_version'] ?? ''}',
                      '${badges['radarr_signalr'] ?? ''}',
                    ),
                  ],
                ),
              ),
              const SectionHeader('System'),
              Card(
                child: Column(
                  children: [
                    for (final e in {
                      'Operating system': status['operating_system'],
                      'Python': status['python_version'],
                      'Database': status['database_engine'],
                      'Timezone': status['timezone'],
                      'CPU cores': status['cpu_cores'],
                      'Config directory': status['bazarr_config_directory'],
                    }.entries)
                      if (e.value != null && '${e.value}'.isNotEmpty)
                        ListTile(
                          dense: true,
                          title: Text(e.key),
                          trailing: Flexible(
                            child: Text(
                              '${e.value}',
                              textAlign: TextAlign.end,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
              const SectionHeader('App'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.settings_ethernet),
                      title: const Text('Connection settings'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SetupScreen(editing: true),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('Disconnect & clear data'),
                      onTap: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Disconnect?'),
                            content: const Text(
                              'Saved URLs, API key and cache will be removed.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Disconnect'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) state.reset();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Unofficial app — not affiliated with Bazarr',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Counter(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ],
      ),
    ),
  );
}

class _StatusTile extends StatelessWidget {
  final String name;
  final String version;
  final String signalr;
  const _StatusTile(this.name, this.version, this.signalr);

  @override
  Widget build(BuildContext context) {
    final down = signalr == 'DOWN';
    return ListTile(
      leading: Icon(
        down ? Icons.link_off : Icons.link,
        color: down ? Colors.redAccent : Colors.greenAccent.shade400,
      ),
      title: Text(name),
      subtitle: Text(version.isEmpty ? 'Not configured' : 'v$version'),
      trailing: Text(down ? 'Disconnected' : 'Connected'),
    );
  }
}

class _ProvidersCard extends StatelessWidget {
  final List<Json> providers;
  const _ProvidersCard({required this.providers});

  @override
  Widget build(BuildContext context) {
    if (providers.isEmpty) {
      return const Card(child: ListTile(title: Text('No providers enabled')));
    }
    return Card(
      child: Column(
        children: [
          for (final p in providers)
            ListTile(
              dense: true,
              leading: Icon(
                p['status'] == 'Good' ? Icons.check_circle : Icons.pause_circle,
                size: 20,
                color: p['status'] == 'Good' ? Colors.green : Colors.orange,
              ),
              title: Text('${p['name']}'),
              subtitle: p['retry'] == null || p['retry'] == '-'
                  ? null
                  : Text('Retry in ${p['retry']}'),
              trailing: Text('${p['status']}'),
            ),
          if (providers.any((p) => p['status'] != 'Good'))
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset providers'),
                onPressed: () async {
                  try {
                    await context.read<AppState>().api!.resetProviders();
                    if (context.mounted) toast(context, 'Providers reset');
                  } catch (e) {
                    if (context.mounted) toast(context, '$e');
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
