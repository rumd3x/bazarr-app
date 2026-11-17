import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';

/// Bazarr's job queue and scheduled tasks.
class JobsScreen extends StatelessWidget {
  /// True while the Jobs tab is the one being shown.
  final bool active;
  const JobsScreen({super.key, this.active = false});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Jobs'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Queue'),
            Tab(text: 'Tasks'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _QueueTab(active: active),
          const _TasksTab(),
        ],
      ),
    ),
  );
}

class _QueueTab extends StatefulWidget {
  final bool active;
  const _QueueTab({required this.active});

  @override
  State<_QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends State<_QueueTab>
    with AutomaticKeepAliveClientMixin {
  final _key = GlobalKey<AsyncBodyState<List<Json>>>();
  Timer? _timer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (widget.active) _key.currentState?.reload(silent: true);
    });
  }

  @override
  void didUpdateWidget(_QueueTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _key.currentState?.reload(silent: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _act(Future<void> Function(BazarrApi api) action) async {
    final state = context.read<AppState>();
    try {
      await action(state.api!);
      await _key.currentState?.reload(silent: true);
      state.refreshActiveJobs();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _clear(String queue) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear $queue jobs?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) _act((api) => api.emptyJobs(queue));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AsyncBody<List<Json>>(
      key: _key,
      load: (api) => api.jobs(),
      builder: (context, jobs) {
        if (jobs.isEmpty) {
          return const EmptyView(Icons.work_history_outlined, 'No jobs');
        }
        const groups = [
          ('running', 'Running', null),
          ('pending', 'Pending', 'pending'),
          ('failed', 'Failed', 'failed'),
          ('completed', 'Completed', 'completed'),
        ];
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          children: [
            for (final (status, label, queue) in groups)
              ..._group(
                jobs.where((j) => j['status'] == status).toList(),
                label,
                queue,
              ),
          ],
        );
      },
    );
  }

  List<Widget> _group(List<Json> jobs, String label, String? queue) {
    if (jobs.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 0, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$label (${jobs.length})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            if (queue != null)
              TextButton(
                onPressed: () => _clear(queue),
                child: const Text('Clear'),
              ),
          ],
        ),
      ),
      for (final j in jobs) _JobCard(job: j, onAction: _act),
    ];
  }
}

class _JobCard extends StatelessWidget {
  final Json job;
  final Future<void> Function(Future<void> Function(BazarrApi api)) onAction;
  const _JobCard({required this.job, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final status = '${job['status']}';
    final id = job['job_id'] as int;
    final value = (job['progress_value'] as num?)?.toInt() ?? 0;
    final max = (job['progress_max'] as num?)?.toInt() ?? 0;
    final message = '${job['progress_message'] ?? ''}';
    final last = '${job['last_run_time'] ?? ''}';
    final (icon, color) = switch (status) {
      'running' => (Icons.autorenew, Colors.lightBlueAccent),
      'pending' => (Icons.schedule, Colors.amber),
      'failed' => (Icons.error_outline, Colors.redAccent),
      _ => (Icons.check_circle_outline, Colors.greenAccent.shade400),
    };
    final lastDate = parseDate(last);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${job['job_name']}'),
                  if (message.isNotEmpty)
                    Text(message, style: Theme.of(context).textTheme.bodySmall),
                  if (status == 'running') ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: job['is_progress'] == true && max > 0
                          ? value / max
                          : null,
                    ),
                    if (job['is_progress'] == true && max > 0)
                      Text(
                        '$value / $max',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                  if (last.isNotEmpty && last != 'null')
                    Text(
                      lastDate == null ? last : _ago(lastDate),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => onAction(
                (api) =>
                    v == 'delete' ? api.deleteJob(id) : api.jobAction(id, v),
              ),
              itemBuilder: (_) => [
                if (status == 'pending') ...const [
                  PopupMenuItem(value: 'force_start', child: Text('Start now')),
                  PopupMenuItem(value: 'move_top', child: Text('Move to top')),
                  PopupMenuItem(
                    value: 'move_bottom',
                    child: Text('Move to bottom'),
                  ),
                ],
                const PopupMenuItem(value: 'delete', child: Text('Remove')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }
}

class _TasksTab extends StatefulWidget {
  const _TasksTab();

  @override
  State<_TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<_TasksTab>
    with AutomaticKeepAliveClientMixin {
  final _key = GlobalKey<AsyncBodyState<List<Json>>>();

  @override
  bool get wantKeepAlive => true;

  Future<void> _run(Json t) async {
    final state = context.read<AppState>();
    try {
      await state.api!.runTask('${t['job_id']}');
      if (!mounted) return;
      toast(context, '${t['name']} queued');
      state.refreshActiveJobs();
      _key.currentState?.reload(silent: true);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AsyncBody<List<Json>>(
      key: _key,
      load: (api) => api.tasks(),
      builder: (context, tasks) => tasks.isEmpty
          ? const EmptyView(Icons.event_repeat, 'No tasks')
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: tasks.length,
              itemBuilder: (_, i) {
                final t = tasks[i];
                final running = t['job_running'] == true;
                return Card(
                  child: ListTile(
                    leading: Icon(
                      running ? Icons.autorenew : Icons.event_repeat,
                      color: running ? Colors.lightBlueAccent : null,
                    ),
                    title: Text('${t['name']}'),
                    subtitle: Text(
                      'Every ${t['interval']} · next ${t['next_run_in']}',
                    ),
                    trailing: IconButton.filledTonal(
                      tooltip: 'Run now',
                      onPressed: running ? null : () => _run(t),
                      icon: const Icon(Icons.play_arrow),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
