# This stack's own steps in scripts/smoke-test.sh, which sources this file; it isn't run on its own. It may define
# smoke_prepare, run once the throwaway settings ($work/env) and folders exist, just before the stack starts (it may
# write $work/override-stack.yaml, which is then added to the Compose files), and smoke_check, run once every service
# is healthy and again after the backup has been restored. Both run with smoke-test.sh's variables and functions
# (work, project, root, busybox, compose, fail). Written for bash 3.2 and later (macOS ships 3.2).
# shellcheck shell=bash disable=SC2154 # work, project, root and busybox come from smoke-test.sh

# Steerhouse: its secrets and tokens, and its database's certificate from a throwaway CA, all made with
# scripts/steerhouse.sh as on the host; then its read-only role for Argus (grafana_ro), what that role and a client
# outside Steerhouse's own networks can and can't do in the database, the metrics token, and that the worker sees the
# API's Galaxy folder.
steerhouse_pg=postgres:18.6-trixie@sha256:edb0c08dc33befd0262ab3b5cf1c4f3f8cfd8b09e88c05b45adee29d6761ddb6

smoke_prepare() {
  local config_root puid pgid made
  config_root=$(sed -n 's/^CONFIG_ROOT=//p' "$work/env")
  puid=$(sed -n 's/^PUID=//p' "$work/env")
  pgid=$(sed -n 's/^PGID=//p' "$work/env")
  made=$work/steerhouse
  mkdir -p "$made"
  "$root/scripts/steerhouse.sh" secrets "$made/secrets" >/dev/null
  "$root/scripts/steerhouse.sh" env "$made/steerhouse.env" >/dev/null
  "$root/scripts/steerhouse.sh" ca "$made/ca" >/dev/null
  "$root/scripts/steerhouse.sh" request "$made/tls" >/dev/null
  "$root/scripts/steerhouse.sh" sign "$made/ca" "$made/tls/server.csr" "$made/tls/server.crt" steerhouse-postgres \
    >/dev/null
  cp "$made/ca/ca.crt" "$made/tls/ca.crt"
  # Into CONFIG_ROOT as on the host: owned by PUID:PGID (the user both services run as), the folders mode 0755 and the
  # secrets' and the key's 0700/0600. CONFIG_ROOT belongs to PUID, who may not be the caller: copied as root.
  docker run --rm --network none -v "$config_root:/c" -v "$made:/made:ro" "$busybox" sh -c '
    set -e
    mkdir -p /c/steerhouse/config /c/steerhouse-postgres/config
    cp -R /made/secrets /c/steerhouse/secrets
    cp -R /made/tls /c/steerhouse-postgres/config/tls
    chown -R "$1:$2" /c/steerhouse /c/steerhouse-postgres
    chmod 0755 /c/steerhouse /c/steerhouse/config /c/steerhouse-postgres /c/steerhouse-postgres/config' \
    own "$puid" "${pgid:-$puid}" </dev/null
  # steerhouse.env in place of the real one, which the smoke test never reads.
  {
    echo "services:"
    for service in steerhouse steerhouse-worker; do
      printf '  %s:\n    env_file: !override\n      - %s\n' "$service" "$made/steerhouse.env"
    done
  } >"$work/override-stack.yaml"
}

# psql in a throwaway container on Steerhouse's network $1, as user $2 with password $3 and the extra connection
# settings $4, running the SQL $5; prints psql's output (and errors).
steerhouse_psql() {
  docker run --rm --network "${project}_$1" -v "$work/steerhouse/tls/ca.crt:/ca.crt:ro" -e PGPASSWORD="$3" \
    "$steerhouse_pg" psql "host=steerhouse-postgres dbname=steerhouse user=$2 connect_timeout=10 $4" \
    -v ON_ERROR_STOP=1 -Atc "$5" </dev/null 2>&1
}

smoke_check() {
  local made=$work/steerhouse grafana app metrics out tls
  grafana=$(cat "$made/secrets/grafana_db_password")
  app=$(cat "$made/secrets/postgres_password")
  metrics=$(sed -n 's/^METRICS_TOKEN=//p' "$made/steerhouse.env")
  tls="sslmode=verify-full sslrootcert=/ca.crt"

  echo "Steerhouse: creating grafana_ro (scripts/steerhouse.sh grafana-role)"
  "$root/scripts/steerhouse.sh" grafana-role

  # From steerhouse-postgres-lan, the network the published port is on (outside Steerhouse's own networks).
  out=$(steerhouse_psql steerhouse-postgres-lan grafana_ro "$grafana" "$tls" \
    "SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid(); SELECT count(*) >= 0 FROM analytics.runs") ||
    fail "grafana_ro can't read analytics.runs over TLS: $out"
  [ "$out" = $'t\nt' ] || fail "grafana_ro's connection isn't encrypted, or analytics.runs is unreadable: $out"
  out=$(steerhouse_psql steerhouse-postgres-lan grafana_ro "$grafana" sslmode=disable "SELECT 1") &&
    fail "grafana_ro could connect without TLS"
  [[ $out == *"pg_hba.conf rejects connection"*"no encryption"* ]] || fail "unexpected error without TLS: $out"
  out=$(steerhouse_psql steerhouse-postgres-lan grafana_ro "$grafana" "$tls" "SELECT count(*) FROM public.users") &&
    fail "grafana_ro can read public.users"
  [[ $out == *"permission denied"* ]] || fail "unexpected error reading public.users: $out"
  out=$(steerhouse_psql steerhouse-postgres-lan grafana_ro "$grafana" "$tls" "CREATE TABLE analytics.smoke (x int)") &&
    fail "grafana_ro could create a table"
  [[ $out == *"read-only transaction"* || $out == *"permission denied"* ]] ||
    fail "unexpected error creating a table: $out"
  out=$(steerhouse_psql steerhouse-postgres-lan steerhouse "$app" "$tls" "SELECT 1") &&
    fail "the app's own user could connect from outside steerhouse-db"
  [[ $out == *"pg_hba.conf rejects connection"* ]] || fail "unexpected error for the app's user: $out"
  echo "Steerhouse: grafana_ro reads the analytics views over TLS only and nothing else; no other login from outside"

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
}
