# Architecture

- `lib/main.dart`: app entry, theme, routing between setup and home.
- `lib/services/`: `settings.dart` (ServerConfig/SettingsStore), `api.dart` (`BazarrApi`: failover, `X-API-KEY`, `ListPage`, `MediaRef`), `demo_client.dart`, `app_state.dart` (provider state, active-jobs badge, list cache).
- `lib/screens/`: `home_screen` (5 tabs), `library_screen` (shared series/movies), `series_detail_screen`, `movie_detail_screen`, `media_screen` (shared episode/movie), `history_screen`, `jobs_screen`, `more_screen`, `setup_screen`.
- `lib/widgets/common.dart`: shared widgets and helpers.
- JSON is kept as `Map<String, dynamic>`; no generated models.

## API notes (base `/api`)
- Lists return `{data:[...], total}`; status/health/jobs/tasks/providers return `{data: ...}`; `/badges` is flat; `/system/languages/profiles` is a plain list.
- Subtitle search: `GET /providers/episodes?episodeid=` or `/providers/movies?radarrid=`; download via POST on the same path.
- Auto-download/delete: `PATCH`/`DELETE /episodes/subtitles` or `/movies/subtitles`.
- Subtitle tools use `PATCH /subtitles` with an `action` query parameter and a form containing media and subtitle identifiers and tool-specific options. These file mutations use one server URL so a lost response cannot trigger the same edit on the fallback URL. `GET /subtitles` returns sync reference tracks, `GET /subtitles/contents` returns timed cues, and translation uses enabled languages from `GET /system/languages` and the configured translator from `GET /system/settings`.
- Jobs actions: `force_start`, `move_top`, `move_bottom`; queues: pending, failed, completed.
- History action type is inferred from the description (the int `action` is unreliable).
