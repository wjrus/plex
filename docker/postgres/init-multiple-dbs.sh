#!/usr/bin/env bash
set -Eeuo pipefail

psql=(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER")

for db in plex_production_cache plex_production_queue plex_production_cable; do
  "${psql[@]}" --dbname "$POSTGRES_DB" <<SQL
CREATE DATABASE ${db} OWNER ${POSTGRES_USER};
SQL
done
