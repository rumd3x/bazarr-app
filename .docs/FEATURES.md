# Features

- **Setup**: primary/secondary URL + API key, validated via `/system/status`; "Try demo".
- **Series / Movies**: grid/list, search, filters, subtitle-coverage progress, pull to refresh, cached lists. Series detail shows seasons and episodes with subtitle chips; actions menu (scan disk, search missing/wanted, sync, language profile).
- **Media screen** (episode or movie): Request an automatic search for a missing language with **Auto search**, view History, or search providers and download a selected result manually.
- **Subtitle tools**: External subtitles support searchable preview with rendered and raw views, sync, deletion and translation. Bazarr applies color, frame-rate conversion, timing offsets, two-point fit, and cleanup for HI tags, style tags, emoji, OCR, common errors, uppercase and RTL to SRT files. Sync lets you confirm an automatic, audio, embedded subtitle or external subtitle reference, a maximum offset, framerate correction and its quality thresholds, and golden-section search. Embedded tracks with a Bazarr subtitle ID support extraction and translation.
- **History**: Series/Movies tabs, paginated.
- **Jobs**: Queue (auto-refresh while active; force start, move top/bottom, delete, clear queues) and Tasks (run now). Tab badge shows active jobs.
- **More**: version, wanted counters, health issues, providers (reset), Sonarr/Radarr connection status, system info, disconnect & clear data. Connection settings are in the top bar and remain available while server details load or fail. Saving a connection reloads server details.
- **Artwork**: posters/fanart resolved by TVDB/TMDB/IMDb ID from public keyless services (cached in `shared_preferences` as `cache_artwork`).
