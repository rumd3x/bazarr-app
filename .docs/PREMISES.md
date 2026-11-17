# Premises

- Android only, Flutter, package `com.rumd3x.bazarr`.
- No login, no database, no backend. State is `shared_preferences` only (server config, cached series/movies lists, demo flag).
- Connects to Bazarr with a primary URL, an optional secondary URL (failover) and the API key sent as `X-API-KEY` (images use the same header).
- Bazarr's image proxy (`/images/...`) ignores the API key (it needs a UI login when auth is enabled), so posters/fanart come from public keyless services by ID (`ArtworkResolver`: Sonarr skyhook TVDB mirror then TVmaze for series; Radarr API TMDB mirror for movies), with Bazarr's own proxy as last fallback. No username/password is stored. Only public IDs are sent to those services.
- Demo mode ships fictional data (`DemoServer`, a `MockClient`) so store reviewers can use the app without a server.
- Bottom navigation: Series / Movies / History / Jobs / More.
- Cleartext HTTP is permitted (LAN servers). Only the INTERNET permission is requested.
- Unofficial: not affiliated with the Bazarr project. Logo comes from the open-source Bazarr repository.
- `PRIVACY_POLICY.txt` must stay accurate.
