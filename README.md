# Plex Shares

Small Rails app for viewing which Plex users can access your shared libraries.
It stores API results in a local PostgreSQL snapshot so normal page loads do not
hit Plex. Use the refresh button when you want to fetch the latest sharing data.

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
ADMIN_USERS=wjr@wjr.us,another-admin@example.com
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
PLEX_CLIENT_IDENTIFIER=plex-shares-local
PLEX_CLIENT_NAME=Plex Shares
```

`PLEX_SERVER_BASE_URL` is required for "last streamed" because playback
history comes from Plex Media Server's `/status/sessions/history/all` endpoint,
not from `plex.tv`.

Use `http://...:32400` unless you know the server presents a certificate that
matches the hostname you configured.

## Refresh behavior

The root page renders the newest `ShareSnapshot` row for the configured machine
identifier. If no snapshot exists yet, it fetches once from Plex and saves one.
After that, the "Refresh from Plex" button refreshes share/library metadata
without scanning playback history, preserving existing last-streamed data from
previous snapshots.

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

Use the rake task when you want to refresh last-streamed history.

## Useful commands

```sh
bin/rails test
bin/rubocop
```

## Deployment

See [docs/deploy.md](/Users/wjr/dev/plex/docs/deploy.md) for Docker Compose,
nginx reverse proxy, and development-to-production Postgres import steps.
