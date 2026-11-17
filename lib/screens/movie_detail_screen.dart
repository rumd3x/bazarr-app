import 'package:flutter/material.dart';

import '../services/api.dart';
import 'media_screen.dart';

/// Movie details: a [MediaScreen] preloaded with the library item.
class MovieDetailScreen extends StatelessWidget {
  final Json movie;
  const MovieDetailScreen({super.key, required this.movie});

  @override
  Widget build(BuildContext context) => MediaScreen(
    ref: MediaRef.movie(movie['radarrId'] as int),
    title: '${movie['title']}',
    subtitle: '${movie['year'] ?? ''}',
    initial: movie['path'] == null ? null : movie,
  );
}
