import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/app_state.dart';

class Poster extends StatefulWidget {
  final Json item;
  final double? width;
  final double? height;
  final IconData icon;

  /// Which image of the item to show: `poster` or `fanart`.
  final String field;
  const Poster(
    this.item, {
    super.key,
    this.width,
    this.height,
    this.icon = Icons.tv,
    this.field = 'poster',
  });

  @override
  State<Poster> createState() => _PosterState();
}

class _PosterState extends State<Poster> {
  Future<String?>? _url;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _url ??= context.read<AppState>().artwork.resolve(
      widget.item,
      widget.field,
    );
  }

  @override
  void didUpdateWidget(Poster old) {
    super.didUpdateWidget(old);
    if (old.item != widget.item || old.field != widget.field) {
      _url = context.read<AppState>().artwork.resolve(
        widget.item,
        widget.field,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api!;
    final cs = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: widget.width,
      height: widget.height,
      color: cs.surfaceContainerHighest,
      child: Icon(widget.icon, color: cs.onSurfaceVariant),
    );
    if (api.isDemo) {
      return _DemoPoster(widget.item, widget.width, widget.height);
    }
    Widget image(String url, {Map<String, String>? headers}) =>
        CachedNetworkImage(
          imageUrl: url,
          httpHeaders: headers,
          width: widget.width,
          height: widget.height,
          fit: BoxFit.cover,
          placeholder: (_, _) => placeholder,
          errorWidget: (_, _, _) => placeholder,
        );
    return FutureBuilder<String?>(
      future: _url,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) return placeholder;
        final external = snap.data;
        if (external != null) return image(external);
        // No public artwork found: Bazarr's own proxy works when it has no auth.
        final own = api.imageUrl(widget.item[widget.field]);
        return own == null ? placeholder : image(own, headers: api.headers);
      },
    );
  }
}

class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyView(this.icon, this.text, {super.key});

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      SizedBox(
        height: 360,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text),
          ],
        ),
      ),
    ],
  );
}

/// Loads data with pull-to-refresh, loading and error states.
class AsyncBody<T> extends StatefulWidget {
  final Future<T> Function(BazarrApi api) load;
  final Widget Function(BuildContext context, T data) builder;
  const AsyncBody({super.key, required this.load, required this.builder});

  @override
  State<AsyncBody<T>> createState() => AsyncBodyState<T>();
}

class AsyncBodyState<T> extends State<AsyncBody<T>> {
  T? _data;
  Object? _error;
  var _loaded = false;
  var _token = 0;

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// Reloads the data. A [silent] reload keeps showing the current content
  /// (no spinner, errors ignored) — used for background refreshes.
  Future<void> reload({bool silent = false}) async {
    final token = ++_token;
    if (!silent || !_loaded) {
      setState(() {
        _loaded = false;
        _error = null;
      });
    }
    try {
      final data = await widget.load(context.read<AppState>().api!);
      if (!mounted || token != _token) return;
      setState(() {
        _data = data;
        _error = null;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted || token != _token || (silent && _data != null)) return;
      setState(() {
        _error = e;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(error: _error!, onRetry: reload);
    return RefreshIndicator(
      onRefresh: reload,
      child: widget.builder(context, _data as T),
    );
  }
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

String formatBytes(num bytes) {
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
}

/// "English", "English HI" or "English forced" for a Bazarr language object.
String languageLabel(Json l) {
  final name = '${l['name'] ?? l['code2'] ?? '?'}';
  if (l['hi'] == true || '${l['hi']}'.toLowerCase() == 'true') {
    return '$name HI';
  }
  if (l['forced'] == true || '${l['forced']}'.toLowerCase() == 'true') {
    return '$name forced';
  }
  return name;
}

/// Parses the Bazarr date strings; returns null when they are not ISO dates.
DateTime? parseDate(Object? v) => v is String ? DateTime.tryParse(v) : null;

class SectionHeader extends StatelessWidget {
  final String text;
  const SectionHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

/// Compact subtitle summary: green chips for the downloaded languages and
/// red chips for the missing ones.
class SubtitleChips extends StatelessWidget {
  final List<Json> have;
  final List<Json> missing;
  const SubtitleChips({super.key, required this.have, required this.missing});

  @override
  Widget build(BuildContext context) {
    Widget chip(String text, Color color, IconData icon) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(text, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
    if (have.isEmpty && missing.isEmpty) {
      return Text(
        'No subtitles',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final s in have)
          chip(languageLabel(s), Colors.greenAccent.shade400, Icons.check),
        for (final s in missing)
          chip(languageLabel(s), Colors.redAccent, Icons.close),
      ],
    );
  }
}

List<Json> jsonList(Object? v) => (v is List ? v : const [])
    .whereType<Map>()
    .map((e) => Json.from(e))
    .toList();

/// Poster stand-in for demo mode, where there are no remote images.
class _DemoPoster extends StatelessWidget {
  final Json item;
  final double? width;
  final double? height;
  const _DemoPoster(this.item, this.width, this.height);

  @override
  Widget build(BuildContext context) {
    final title = '${item['title'] ?? '?'}';
    final big = (height ?? 120) > 100;
    final hue = (title.codeUnits.fold<int>(0, (a, b) => a * 31 + b) % 360)
        .toDouble();
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue, 0.55, 0.38).toColor(),
            HSLColor.fromAHSL(1, (hue + 40) % 360, 0.6, 0.18).toColor(),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Text(
          big || title.isEmpty ? title : title[0],
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.92),
            fontSize: big ? 18 : 22,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
      ),
    );
  }
}
