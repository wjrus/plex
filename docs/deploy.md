# Deploy

Production is a small Docker Compose stack intended to live at:

```sh
/apps/plex
```

It runs:

- `web`: Rails/Puma/Thruster on container port `80`, bound to localhost only
- `db`: PostgreSQL 18 with primary, cache, queue, and cable databases

The host port defaults to `3010`, bound on all host interfaces so a separate
Nginx Proxy Manager container/host can reach it. Your reverse proxy can forward
`plexadmin.example.com` to:

```text
http://<docker-host-ip>:3010
```

## First Setup

On the server:

```sh
mkdir -p /apps
cd /apps
git clone <your-repo-url> plex
cd /apps/plex

cp .env.production.example .env.production
cp .env.postgres.example .env.postgres
```

Generate secrets:

```sh
bin/rails secret
openssl rand -hex 32
```

Put the `bin/rails secret` value in `.env.production` as `SECRET_KEY_BASE`.
Put the random Postgres password in both places:

```sh
# .env.postgres
POSTGRES_PASSWORD=...

# .env.production
PLEX_DATABASE_PASSWORD=...
```

Fill in the remaining `.env.production` values:

```sh
PLEX_HOST=plexadmin.example.com
PLEX_HOSTS=plexadmin.example.com
PLEX_FORCE_SSL=true
ADMIN_USERS=admin@example.com
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
PLEX_TOKEN=...
PLEX_MACHINE_IDENTIFIER=...
PLEX_SERVER_BASE_URL=http://plex.example.com:32400
```

Google OAuth redirect URI:

```text
https://plexadmin.example.com/auth/google_oauth2/callback
```

Deploy:

```sh
./scripts/deploy
```

Follow logs:

```sh
./scripts/logs
./scripts/logs all
```

## Nginx Reverse Proxy

Use a vhost for `plexadmin.example.com` that terminates TLS and proxies to the local
Compose port.

Plain nginx example:

```nginx
server {
  listen 443 ssl http2;
  server_name plexadmin.example.com;

  location / {
    proxy_pass http://127.0.0.1:3010;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;
  }
}
```

If port `3010` conflicts with another app:

```sh
PLEX_ADMIN_PORT=3011 ./scripts/deploy
```

Then point nginx at `127.0.0.1:3011`.

If nginx runs on the same host and you want to keep the app private to
localhost only:

```sh
PLEX_ADMIN_BIND=127.0.0.1 ./scripts/deploy
```

## Import Development Data

This copies the local development database snapshots and notes into the
production primary database. It does not copy secrets; those stay in
`.env.production`.

On your development machine:

```sh
cd /path/to/plex
mkdir -p tmp
pg_dump --format=custom --no-owner --no-acl --file=tmp/plex_development.dump plex_development
scp tmp/plex_development.dump <server>:/apps/plex/tmp/plex_development.dump
```

On the server:

```sh
cd /apps/plex
./scripts/deploy
docker compose stop web
docker compose cp tmp/plex_development.dump db:/tmp/plex_development.dump
docker compose exec -T db pg_restore \
  --clean \
  --if-exists \
  --no-owner \
  --no-acl \
  --role=plex \
  --username=plex \
  --dbname=plex_production \
  /tmp/plex_development.dump
docker compose run --rm web ./bin/rails db:migrate
docker compose up -d web
```

Verify:

```sh
docker compose exec web ./bin/rails runner 'puts ShareSnapshot.count; puts PlexUserNote.count'
curl -fsSI -H 'Host: plexadmin.example.com' http://127.0.0.1:3010/up
```

## Useful Commands

```sh
./scripts/deploy
./scripts/logs
./scripts/logs db
docker compose ps
docker compose exec web ./bin/rails console
docker compose run --rm web ./bin/rails plex:refresh
docker compose logs -f daily_refresh
```

## Backups

Back up the Compose volume:

```text
plex_postgres_data
```

The app storage volume is currently only for Rails local storage; this app does
not store Plex media there.

PostgreSQL contains Plex sharing data, playback history, now-playing samples,
raw Plex metadata payloads, device names, IP addresses, and local admin notes.
Treat dumps and backups as sensitive data.
