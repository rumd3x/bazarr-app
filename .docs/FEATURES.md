# Features

- **Setup**: primary/secondary URL + API key, validated via `/system/status`; "Try demo".
- **Series / Movies**: grid/list, search, filters, subtitle-coverage progress, pull to refresh, cached lists. Series detail shows seasons and episodes with subtitle chips; actions menu (scan disk, search missing/wanted, sync, language profile).
- **Media screen** (episode or movie): Subtitles (delete, sync, auto-download per language), History, and manual provider Search/download.
- **History**: Series/Movies tabs, paginated.
- **Jobs**: Queue (auto-refresh while active; force start, move top/bottom, delete, clear queues) and Tasks (run now). Tab badge shows active jobs.
- **More**: version, wanted counters, health issues, providers (reset), Sonarr/Radarr connection status, system info, connection settings, disconnect & clear data.
- **Artwork**: posters/fanart resolved by TVDB/TMDB/IMDb ID from public keyless services (cached in `shared_preferences` as `cache_artwork`).
