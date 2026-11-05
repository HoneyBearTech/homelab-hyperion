# This stack's own steps in scripts/smoke-test.sh, which sources this file; it isn't run on its own. It may define
# smoke_prepare, run once the throwaway settings ($work/env) and folders exist, just before the stack starts (it may
# write $work/override-stack.yaml, which is then added to the Compose files), and smoke_check, run once every service
# is healthy and again after the backup has been restored. Both run with smoke-test.sh's variables and functions
# (work, project, root, busybox, compose, fail). Written for bash 3.2 and later (macOS ships 3.2).
# shellcheck shell=bash disable=SC2154 # work, project, root and busybox come from smoke-test.sh

# Steerhouse: its secrets and tokens, made with scripts/steerhouse.sh as on the host, and a throwaway PostgreSQL in the
# stack standing in for the database server, set up as docs/installing.md has its administrator do it: Steerhouse's
# login owns its database and is no superuser, grafana_ro is made there, and the network admits TLS only (the image's
# own self-signed certificate). Then that grafana_ro reads the analytics views and nothing else once
# scripts/steerhouse.sh grafana-role ran, the metrics token, and that the worker sees the API's Galaxy folder.
steerhouse_db=steerhouse-test-db

# The PostgreSQL the database server runs, pinned like busybox in lib.sh (bumped by hand, docs/dependencies.md).
steerhouse_pg=postgres:18.6-trixie@sha256:edb0c08dc33befd0262ab3b5cf1c4f3f8cfd8b09e88c05b45adee29d6761ddb6

# Dozzle: a throwaway certificate and key, made with `dozzle generate-certs` as on the host and owned by root as there,
# and two test agents on the stack's network for Dozzle to connect to: dozzle-agent-test with that pair, which Dozzle
# must show as available, and dozzle-builtin-test with the pair built into every Dozzle image, which it must not
# reach. Each has a host id of its own: on the same Docker as Dozzle, it would otherwise be merged with this host.
dozzle_agents="dozzle-agent-test:7007,dozzle-builtin-test:7007"

# Each host on Dozzle's page (its config__json), one "<endpoint> <available>" per line.
dozzle_hosts() {
  docker run --rm --network "${project}_default" "$busybox" wget -qO - http://dozzle:8080/ </dev/null |
    python3 -I -c '
import json, re, sys
match = re.search(r"id=\"config__json\"[^>]*>([^<]*)<", sys.stdin.read())
for host in json.loads(match.group(1))["hosts"] if match else []:
    print(host["endpoint"], host["available"])'
}

smoke_prepare() {
  local config_root puid pgid made app grafana admin dozzle_image
  config_root=$(sed -n 's/^CONFIG_ROOT=//p' "$work/env")
  puid=$(sed -n 's/^PUID=//p' "$work/env")
  pgid=$(sed -n 's/^PGID=//p' "$work/env")
  made=$work/steerhouse
  mkdir -p "$made/db/initdb"
  "$root/scripts/steerhouse.sh" secrets "$made/secrets" >/dev/null
  "$root/scripts/steerhouse.sh" env "$made/steerhouse.env" >/dev/null
  app=$(openssl rand -hex 24)
  grafana=$(openssl rand -hex 24)
  admin=$(openssl rand -hex 24)
  printf '%s\n' "$app" >"$made/db/app_password"
  printf '%s\n' "$grafana" >"$made/db/grafana_password"
  # database_url as the installing docs have the user write it, with the login the server's administrator made.
  (umask 077 && printf 'postgresql+psycopg://steerhouse:%s@%s:5432/steerhouse?sslmode=require\n' "$app" \
    "$steerhouse_db" >"$made/secrets/database_url")
  # The database server's side, in its administrator's words (docs/installing.md#steerhouse); run once, as the image's
  # superuser, when the server starts with an empty data directory. The socket trusts the container's own users; over
  # the network, only the two logins, and only with TLS.
  cat >"$made/db/initdb/steerhouse.sql" <<SQL
CREATE ROLE steerhouse LOGIN PASSWORD '$app';
CREATE DATABASE steerhouse OWNER steerhouse;
CREATE ROLE grafana_ro WITH LOGIN NOINHERIT CONNECTION LIMIT 10 PASSWORD '$grafana';
ALTER ROLE grafana_ro SET default_transaction_read_only = on;
ALTER ROLE grafana_ro SET statement_timeout = '30s';
ALTER ROLE grafana_ro SET search_path = analytics;
GRANT CONNECT ON DATABASE steerhouse TO grafana_ro;
SQL
  printf '%s\n' 'local all all trust' 'hostssl steerhouse steerhouse all scram-sha-256' \
    'hostssl steerhouse grafana_ro all scram-sha-256' 'host all all all reject' >"$made/db/pg_hba.conf"
  chmod 755 "$made/db" "$made/db/initdb"
  chmod 644 "$made/db/pg_hba.conf" "$made/db/initdb/steerhouse.sql"
  # Into CONFIG_ROOT as on the host: owned by PUID:PGID (the user the API runs as), the folders mode 0755 and the
  # secrets' 0700/0600. CONFIG_ROOT belongs to PUID, who may not be the caller: copied as root.
  docker run --rm --network none -v "$config_root:/c" -v "$made:/made:ro" "$busybox" sh -c '
    set -e
    mkdir -p /c/steerhouse/config
    cp -R /made/secrets /c/steerhouse/secrets
    chown -R "$1:$2" /c/steerhouse
    chmod 0755 /c/steerhouse /c/steerhouse/config' \
    own "$puid" "${pgid:-$puid}" </dev/null
  # steerhouse.env in place of the real one, which the smoke test never reads, and the stand-in database server, on the
  # network the API reaches its server over, with its data in memory: nothing in it is backed up or restored.
  cat >"$work/override-stack.yaml" <<YAML
services:
  steerhouse:
    env_file: !override
      - $made/steerhouse.env
    depends_on:
      $steerhouse_db:
        condition: service_healthy
  steerhouse-worker:
    env_file: !override
      - $made/steerhouse.env
  $steerhouse_db:
    image: $steerhouse_pg
    user: postgres
    read_only: true
    security_opt: ["no-new-privileges:true"]
    cap_drop: [ALL]
    tmpfs: [/var/lib/postgresql, /var/run/postgresql, /tmp]
    environment:
      POSTGRES_PASSWORD: $admin
    command:
      - postgres
      - -c
      - ssl=on
      - -c
      - ssl_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
      - -c
      - ssl_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
      - -c
      - hba_file=/etc/smoke/pg_hba.conf
    volumes:
      - $made/db/pg_hba.conf:/etc/smoke/pg_hba.conf:ro
      - $made/db/initdb:/docker-entrypoint-initdb.d:ro
    networks: [steerhouse-web]
    healthcheck:
      # Over TCP: the image runs the SQL above on a server that listens on its socket only, so this passes once the
      # real server is up.
      test: ["CMD", "pg_isready", "-h", "127.0.0.1", "-U", "postgres"]
      interval: 2s
      retries: 30
YAML

  # Dozzle's pair, in its folder as root (CONFIG_ROOT belongs to PUID); generate-certs writes the key with mode 0600 and
  # the certificate with 0644, owned by root, the user it runs as.
  dozzle_image=$(compose config --images dozzle)
  docker run --rm --network none -v "$config_root:/c" "$busybox" mkdir -p /c/dozzle/certs </dev/null
  docker run --rm --network none -v "$config_root/dozzle/certs:/out" "$dozzle_image" --no-analytics generate-certs \
    --cert-out /out/dozzle_cert.pem --key-out /out/dozzle_key.pem </dev/null >/dev/null
  cat >>"$work/override-stack.yaml" <<YAML
  dozzle:
    environment:
      DOZZLE_REMOTE_AGENT: $dozzle_agents
  dozzle-agent-test:
    image: $dozzle_image
    command: agent
    environment:
      DOZZLE_HOST_ID: smoke-agent-test
      DOZZLE_CERT: /run/secrets/dozzle_cert
      DOZZLE_KEY: /run/secrets/dozzle_key
    secrets: [dozzle_cert, dozzle_key]
    volumes: [/var/run/docker.sock:/var/run/docker.sock:ro]
  dozzle-builtin-test:
    image: $dozzle_image
    command: agent
    environment:
      DOZZLE_HOST_ID: smoke-builtin-test
    volumes: [/var/run/docker.sock:/var/run/docker.sock:ro]
YAML
}

# psql in a throwaway container on the network the API reaches its database server over, as user $1 with password $2
# and the extra connection settings $3, running the SQL $4; prints psql's output (and errors).
steerhouse_psql() {
  docker run --rm --network "${project}_steerhouse-web" -e PGPASSWORD="$2" "$steerhouse_pg" \
    psql "host=$steerhouse_db dbname=steerhouse user=$1 connect_timeout=10 $3" -v ON_ERROR_STOP=1 -Atc "$4" \
    </dev/null 2>&1
}

smoke_check() {
  local made=$work/steerhouse grafana app metrics out hosts
  grafana=$(cat "$made/db/grafana_password")
  app=$(cat "$made/db/app_password")
  metrics=$(sed -n 's/^METRICS_TOKEN=//p' "$made/steerhouse.env")

  echo "Steerhouse: letting grafana_ro read the analytics views (scripts/steerhouse.sh grafana-role)"
  "$root/scripts/steerhouse.sh" grafana-role

  # The API made its tables with a login that is no superuser, as on the database server.
  out=$(steerhouse_psql steerhouse "$app" sslmode=require \
    "SELECT rolsuper FROM pg_roles WHERE rolname = current_user; SELECT count(*) > 0 FROM pg_tables
     WHERE schemaname = 'public'") || fail "Steerhouse's login can't connect over TLS: $out"
  [ "$out" = $'f\nt' ] || fail "Steerhouse's login is a superuser, or it made no tables: $out"
  out=$(steerhouse_psql grafana_ro "$grafana" sslmode=require \
    "SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid(); SELECT count(*) >= 0 FROM analytics.runs") ||
    fail "grafana_ro can't read analytics.runs over TLS: $out"
  [ "$out" = $'t\nt' ] || fail "grafana_ro's connection isn't encrypted, or analytics.runs is unreadable: $out"
  out=$(steerhouse_psql grafana_ro "$grafana" sslmode=require "SELECT count(*) FROM public.users") &&
    fail "grafana_ro can read public.users"
  [[ $out == *"permission denied"* ]] || fail "unexpected error reading public.users: $out"
  out=$(steerhouse_psql grafana_ro "$grafana" sslmode=require "CREATE TABLE analytics.smoke (x int)") &&
    fail "grafana_ro could create a table"
  [[ $out == *"read-only transaction"* || $out == *"permission denied"* ]] ||
    fail "unexpected error creating a table: $out"
  echo "Steerhouse: its login is no superuser; grafana_ro reads the analytics views and nothing else"

  # The metrics port, from the network the API's ports are published on.
  docker run --rm --network "${project}_steerhouse-web" "$busybox" \
    wget -qO /dev/null http://steerhouse:8002/metrics </dev/null 2>/dev/null &&
    fail "the metrics answered without METRICS_TOKEN"
  docker run --rm --network "${project}_steerhouse-web" "$busybox" \
    wget -qO - --header "Authorization: Bearer $metrics" http://steerhouse:8002/metrics </dev/null |
    grep '^steerhouse_' >/dev/null || fail "the metrics didn't answer with METRICS_TOKEN"
  docker run --rm --network "${project}_steerhouse-web" "$busybox" \
    wget -qO /dev/null http://steerhouse-frontend:8080/api/health </dev/null ||
    fail "the web UI doesn't reach the API"
  echo "Steerhouse: /metrics answers only with METRICS_TOKEN; the web UI reaches the API"

  # The worker started (it refuses to without its run isolation and egress filter) and reads the API's Galaxy folder,
  # which the API made (owned by PUID, not by root as Docker would make it).
  compose logs --no-color steerhouse-worker | grep "worker .* ready:" >/dev/null ||
    fail "the worker never logged that it's ready"
  docker run --rm --network none --volumes-from "$(compose ps --quiet steerhouse)" "$busybox" \
    sh -c 'test "$(stat -c %u /data/galaxy)" != 0 && touch /data/galaxy/.smoke-galaxy' </dev/null ||
    fail "the API's Galaxy folder belongs to root"
  # After the restore too: restore.sh replaced the folder, so it must have restarted the worker.
  compose exec -T steerhouse-worker test -e /galaxy/.smoke-galaxy ||
    fail "the worker doesn't see the API's Galaxy folder"
  echo "Steerhouse: the worker is ready and sees the API's Galaxy folder"

  # Dozzle started with its pair, and reaches the test agent that has it but not the one with the built-in pair. It
  # dials an agent again when its page is loaded, so a test agent that started after it shows up within seconds.
  compose logs --no-color dozzle | grep "Loaded custom dozzle certificate and key" >/dev/null ||
    fail "Dozzle didn't load its certificate and key"
  for _ in $(seq 1 30); do
    hosts=$(dozzle_hosts)
    if [[ $hosts == *"dozzle-agent-test:7007 True"* ]]; then break; fi
    sleep 2
  done
  [[ $hosts == *"dozzle-agent-test:7007 True"* ]] ||
    fail "Dozzle doesn't reach the agent that has its certificate and key: $hosts"
  [[ $hosts == *"dozzle-builtin-test:7007 False"* ]] ||
    fail "Dozzle reached the agent with the built-in certificate, or doesn't list it: $hosts"
  echo "Dozzle: reaches an agent with its own certificate and key, and not one with the built-in pair"
}
