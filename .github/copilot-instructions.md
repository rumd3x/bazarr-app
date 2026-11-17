# Project instructions

- **Always read the documentation in `.docs/` before acting** (start with `.docs/README.md` and `.docs/PREMISES.md`).
- **Always keep the documentation updated**: any change to behavior, features, architecture, premises, commands or dependencies must update the matching file in `.docs/` (and `README.md` when user-facing) in the same change.
- Bazarr API docs: https://bazarr.ericweissgerber.com/api/ (swagger at `/api/swagger.json`). It has no response schemas, so response shapes come from the Bazarr source; normalize in `BazarrApi` and mirror every endpoint in `DemoServer`.
- Respect the premises: no login/database, local cache only, primary + secondary URL with API key (`X-API-KEY`).
- **Always keep `PRIVACY_POLICY.txt` accurate**: if a change alters data stored on the device, data sent over the network, permissions in `AndroidManifest.xml`, or adds a third-party SDK, update the policy and its "Last updated" date in the same change.
- Screenshots are manual and live at `assets/images/screenshots/`; keep README references in sync.
