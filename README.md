# Plex Shares

Small Rails app for Plex server admins. It shows shared-library access, pending
invites, local notes, playback stats, stream history, and current sessions.

The app stores Plex API results in PostgreSQL so normal page loads do not hit
Plex. Use the Maintenance page when you need to refresh Plex data on demand.

## Setup

```sh
cp .env.example .env
bin/setup
bin/rails db:create db:migrate
bin/dev
```

Open `http://localhost:3000`.

## Plex configuration

Put these values in `.env`:

```sh
PLEX_TOKEN=
PLEX_MACHINE_IDENTIFIER=
ADMIN_USERS=admin@example.com,another-admin@example.com
```

`PLEX_TOKEN` is your Plex account token. One practical way to find it:

1. Open Plex Web.
2. Play or inspect any item from your server.
3. Choose "Get Info" / "View XML" for the item.
4. Copy the `X-Plex-Token` value from the XML URL.

`PLEX_MACHINE_IDENTIFIER` is the server machine identifier. You can get it with
your token:

```sh
curl "https://plex.tv/api/servers?X-Plex-Token=$PLEX_TOKEN"
```

Use the `machineIdentifier` attribute for the server you own and want to audit.

Optional `.env` values:

```sh
PLEX_API_BASE_URL=https://plex.tv
PLEX_SERVER_BASE_URL=http://127.0.0.1:32400
PLEX_HISTORY_PAGE_SIZE=1000
PLEX_HISTORY_MAX_PAGES=all
PLEX_HISTORY_DAYS=730
PLEX_HISTORY_RETRIES=8
PLEX_CLIENT_IDENTIFIER=plex-shares-local
PLEX_CLIENT_NAME=Plex Shares
PLEX_NOW_PLAYING_SAMPLE_INTERVAL=60
PLEX_NOW_PLAYING_RETENTION_DAYS=90
PLEX_DAILY_REFRESH_AT=04:15
PLEX_DAILY_REFRESH_DAYS=1
PLEX_OWNER_ACCOUNT_ID=
PLEX_OWNER_NAME=
PLEX_OWNER_USERNAME=
PLEX_OWNER_EMAIL=
```

`PLEX_SERVER_BASE_URL` is required for "last streamed" because playback
history comes from Plex Media Server's `/status/sessions/history/all` endpoint,
not from `plex.tv`.

Use `http://...:32400` unless you know the server presents a certificate that
matches the hostname you configured.

The optional `PLEX_OWNER_*` values label your own playback-history account in
the users and user detail views. Plex does not list the server owner as a shared
library user, so the app adds any account found in local stream history that is
not already in the share snapshot.

## Main Features

- **Access**: view and edit which libraries each shared user can access.
- **Users**: quick-glance user list with notes, status, libraries, and last
  streamed data.
- **User detail**: manage libraries, edit notes, cancel pending invites, remove
  access, review stream history, and inspect per-user stats.
- **Now**: current Plex sessions with cover art, player/IP data when available,
  and background refreshes every 10 seconds.
- **Stats**: completed-play stats for active libraries only. Stats default to
  the last 7 days and can be toggled to 30 days, past year, or all time.
- **Log**: audit trail for admin actions such as library changes, note edits,
  suppression changes, invite cancellation, and access removal.
- **Maintenance**: manual Plex refreshes, current refresh status, now-playing
  sampling, sample pruning, playback-history summary, and suppressed-user link.

Pending invites are stored in the local snapshot when Plex exposes them. If an
invite disappears from Plex but remains in the local cache, canceling it in the
app will clean up the stale local row when Plex returns `404`.

Suppressed users are local-history accounts you do not want in the default
Access or Users lists. Suppression never deletes playback history.

## Refresh behavior

Access and Users render the newest `ShareSnapshot` row for the configured
machine identifier. The Maintenance page has a "Refresh from Plex" action that
queues a metadata refresh without scanning playback history, preserving existing
last-streamed data from previous snapshots. The refresh panel shows whether a
refresh is queued/running, the last message, and history progress when history
is included.

For the full history-backed refresh, prefer the rake task:

```sh
bin/rails plex:refresh
```

It can take a while when `PLEX_HISTORY_MAX_PAGES=all`, but it avoids tying the
long-running Plex history scan to a browser request. By default the task scans
the past 730 days, roughly 24 months. To intentionally scan everything, run:

```sh
PLEX_HISTORY_DAYS=all bin/rails plex:refresh
```

Use the rake task when you want to refresh last-streamed history for shared
users. For one-time population of the local stream-events table, use:

```sh
bin/rails plex:backfill_history
PLEX_HISTORY_DAYS=all PLEX_HISTORY_MAX_PAGES=all bin/rails plex:backfill_history
PLEX_HISTORY_START_PAGE=179 PLEX_HISTORY_DAYS=all bin/rails plex:backfill_history
```

`PLEX_HISTORY_RETRIES` controls how many times each history page is retried
after a Plex timeout before the task stops and prints the resume page. Backfill
saves after each page, so it is safe to resume from the next page printed in the
logs.

In Docker Compose production, the `daily_refresh` service runs the same rake task
once per day with `PLEX_DAILY_REFRESH_DAYS=1`. Set `PLEX_DAILY_REFRESH_AT` in
`.env.production` to choose the daily wall-clock time, using `HH:MM`.

The `now_playing_sampler` Compose service records lightweight current-stream
samples every `PLEX_NOW_PLAYING_SAMPLE_INTERVAL` seconds. This captures future
player/IP data from the live sessions endpoint when Plex exposes it. Samples
older than `PLEX_NOW_PLAYING_RETENTION_DAYS` are pruned automatically by the
sampler and can also be pruned from the Maintenance page.

## Stats

Stats count completed video plays only, scoped to active libraries in the latest
snapshot. Audio/track history and inactive libraries are ignored for the stats
surfaces.

The default stats period is 7 days. The available toggles are `7 days`, `30
days`, `Past year`, and `All time`.

Short periods show daily activity buckets. Past-year and all-time views show
monthly buckets. User detail pages split top titles into top series and top
movies.

## Security Notes

The app is intended to run behind Google OAuth and a TLS-terminating reverse
proxy. For production behind TLS, set `PLEX_ASSUME_SSL=true`. Set
`PLEX_FORCE_SSL=true` only when Rails itself should force SSL/HSTS behavior for
your deployment.

Playback history and now-playing samples can include Plex metadata, device
names, IP addresses, session identifiers, and watch history. Treat database
dumps and backups as sensitive admin data.

CSV exports escape spreadsheet formula prefixes to avoid formula execution when
opened in Excel, Numbers, or Google Sheets.

## Useful commands

```sh
bin/rails test
bin/rubocop
bundle exec brakeman -q --no-pager
bundle exec bundle-audit check
bin/rails restart
```

Production helper scripts:

```sh
./scripts/backfill-history
./scripts/resume-backfill 179
./scripts/sample-now-playing
./scripts/prune-samples
./scripts/deploy
./scripts/logs
```

## Deployment

See [docs/deploy.md](docs/deploy.md) for Docker Compose,
nginx reverse proxy, and development-to-production Postgres import steps.
