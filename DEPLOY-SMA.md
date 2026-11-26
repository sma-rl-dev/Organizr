# Organizr deployment for tester-env

Baseline: **v2-master** `6b27515ff3bc6f4998ed83aca8c08be0998fd118` (version 2.1.5000, 2026-05-19).
There is no tagged v2 release (the latest Release is 1.90 from 2019, the v1 line), so the
commit is pinned on branch `tester-env-baseline` = this baseline + the tester-env tooling only.

Source build, single container, no external services.

## Quick start

```bash
./tester-env deploy     # docker build from source, run, script the first-run wizard
./tester-env seed       # idempotent deterministic Hale homelab fixture
./tester-env verify     # assert login, API key, SQLite DB and the seeded state
./tester-env status     # running state, image, URL, credentials
./tester-env logs       # tail container logs (TAIL=<n>, --follow)
./tester-env stop       # stop container, state preserved (alias: down)
./tester-env reset      # stop + remove the container (config, DB, caches); image kept
```

Populated baseline: `./tester-env reset && ./tester-env deploy && ./tester-env seed`
then `./tester-env verify` (also the order `scripts/rl-env` uses).

Options: `--run-id <id>` scopes the container name; `--port <port>` host port
(default 53907). `IMAGE_TAG` (set by `scripts/rl-env`) names the image; `RUN_ID` never
does. Manual runs get `tester-env-organizr:dev`.

## Runtime contract

- Host port `${PORT:-53907}` -> container 80 (nginx -> php-fpm 9000, SQLite).
- No volumes: `data/config/config.php`, `data/organizr/organizr.db` and `data/cache/`
  live in the container writable layer, so `reset` is a container removal and
  `deploy` recreates pristine state.
- `Dockerfile.tester-env` builds `php:8.5-fpm-alpine` + nginx + `ext-zip` (required by
  Organizr's dependency check) and copies the checkout with `--chown=www-data`
  (the web root must be writable). `api/vendor` and `css/*.min.css` are committed, so
  there is no composer/npm stage.
- `tester-env.nginx.conf` adds upstream docker-organizr's required rewrite
  `location /api/v2 { try_files $uri /api/v2/index.php$is_args$args; }`.
- `TZ=UTC`; server-side news/update/GitHub hosts (`organizr.app`, `api.organizr.app`,
  `feature.organizr.app`, `github.com`, `api.github.com`, `raw.githubusercontent.com`)
  are mapped to loopback with `--add-host` so offline calls fail fast.
- No base-URL variable: Organizr builds links from the request host, so
  `http://localhost:53907/` and `http://172.16.0.1:53907/` (bridge gateway) both work.

## Credentials

- `admin` / `OrganizrAdmin2026` (admin@example.com) — created by the scripted wizard
  (license `personal`, hashKey `OrganizrHashKey2026`, 20-char API key
  `organizrApiKey2026XX`, registration password `RegisterPass2026`, dbPath
  `/var/www/organizr/data/organizr`, dbName `organizr.db`, driver `sqlite3`).
- API key `organizrApiKey2026XX`, sent as header `Token`.
- Seeded users `sarah` (Co-Admin), `marcus` (Power User), `priya` (User),
  `guest` (Guest, locked), all with password `HomelabUser2026`.

## Seeded baseline (`./tester-env seed`)

`seed` runs PHP inside the container against the SQLite DB plus a `config.php` write;
no browser, API or external service. Each run restores the wizard rows and replaces the
rest with the fixed Hale homelab state, so reset+deploy+seed converges.

| Entity | Stable visible identity |
| --- | --- |
| Users (5) | admin (Admin/0, 2026-01-05 09:00:00), sarah (Co-Admin/1, 2026-02-12 14:05:00), marcus (Power User/3, 2026-03-08 19:30:00), priya (User/4, 2026-04-19 08:15:00), guest (Guest/999, locked, 2026-05-02 11:45:00) |
| Categories (4) | Unsorted (order 1/id 0), Media (2/1), Downloads (3/2), Infrastructure (4/3) |
| Tabs (11) | Settings, Homepage, then Jellyfin, Plex, Sonarr, Radarr, qBittorrent, Grafana, Uptime Kuma, Portainer, Home Assistant with fixed order 1-11 and category ids 0/1/2/3 |
| Tab gating | Jellyfin/Plex min group User (4); Sonarr/Radarr/qBittorrent Power User (3); Grafana/Uptime Kuma/Portainer/Home Assistant Super User (2) |
| Disabled tab | Home Assistant `enabled=0`: listed in Settings > Tab Editor, absent from the sidebar |
| Landing page | Homepage `enabled=1, default=1`, so login lands on the homepage |
| Homepage card | Custom HTML 01 enabled for Admin: `Hale Homelab`, `Media, downloads and monitoring for the Hale household.`, `Jellyfin and Plex serve the media library`, `Sonarr and Radarr feed qBittorrent`, `Grafana, Uptime Kuma and Portainer watch the rack` |

Seed manifest: `tester-env-seed.json` (15 requirement ids, profile `hale-homelab`).

`./tester-env verify` asserts: GET / 200 with no DEPENDENCY CHECK strings,
`/api/v2/launch` `status=ok` / `dependenciesInactive=[]` / `writable=yes`, config.php
present, API key lists admin, username/password login sets a working cookie, SQLite
file non-empty, then through the admin session the 11 tabs / 4 categories with exact
order, category, enabled, min-group and URL; the 5 users with email/group/group_id/
locked/register_date; `/api/v2/launch` navigation with Home Assistant absent; the three
homepage card phrases; and a `sarah`/`HomelabUser2026` login.

## Evidence (2026-11-26)

- Build: image `sha256:064125cf7c70342deeb582bd64678e8f640e2a9c90cee0a7802e2521316bfdb3`,
  212 MB; source-change rebuild 7.1 s with the zip layer cached (44 s when it compiles zip).
- Deploy: `./tester-env deploy` on port 53907 built, started, POSTed the wizard, found
  config.php + SQLite DB, asserted the API key and `launch` status.
- Browser smoke: hard-reload of `http://172.16.0.1:53907/`, login `admin` succeeded and
  a tab created in Settings > Tab Editor persisted after reload. An earlier build
  without `ext-zip`/`www-data` ownership rendered Organizr's DEPENDENCY CHECK page in the
  browser (curl of the shell HTML did not show it); fixed and re-verified — `launch`
  reports `status=ok`, `dependenciesInactive=[]`, `writable=yes`, 18 required extensions.
- Reset: `./tester-env stop` then `reset` removed the container (Status: NOT RUNNING);
  `deploy` + `verify` passed again. No volumes or bind mounts involved.
- Seed: 4 deterministic runs produced identical canonical snapshots
  (`sha256:593185b900379188c7f8f3b2e45759e8ce55490ca9a55763103bceda50bb2c63`,
  autoincrement ids and bcrypt salts excluded); an unseeded stack fails verify with
  "expected 11 tabs, found 2".
- Seed browser check: Homepage card, sidebar Media/Downloads/Infrastructure (no Home
  Assistant), Tab Editor 11 rows with Home Assistant inactive, 4 categories, 5 users
  with guest locked.

Docker cleanup policy: no `docker rmi`, no pruning, no access to
`alevern/chromium-browser` or `chromium-ls*` containers. The image is content-addressed
when driven by `scripts/rl-env`; reclaim tags with `scripts/rl-env gc --prune-images`.
