#!/usr/bin/env bash
# Steerhouse's secrets and tokens, and the analytics views for the read-only role Argus' Grafana logs in as
# (docs/installing.md#steerhouse). Run on the host, as the user the stack runs as (PUID): every file it writes belongs
# to that user, mode 600, in a directory of mode 700. It never overwrites a file that exists.
#
#   scripts/steerhouse.sh secrets DIR          the secret files in DIR (CONFIG_ROOT/steerhouse/secrets), new random
#                                              values, all but database_url (written by hand, from the database
#                                              server's login); the first admin's password is admin_password
#   scripts/steerhouse.sh env FILE             FILE (steerhouse.env) with a new WORKER_TOKEN and METRICS_TOKEN
#   scripts/steerhouse.sh grafana-role         let grafana_ro, made on the database server, read the analytics views,
#                                              and check that it can read nothing else, in the running stack
#
# `grafana-role` runs `docker compose` from the checkout, so the standard Compose variables select another project, as
# in scripts/backup.sh. Written for bash 3.2 and later (macOS ships 3.2) and OpenSSL or LibreSSL.
set -euo pipefail

usage() {
  sed -n 's/^#   //p' "$0" >&2
  exit 2
}

fail() {
  echo "error: $*" >&2
  exit 1
}

# A new random hex string, $1 bytes long.
random_hex() { openssl rand -hex "$1"; }

# Writes stdin to $1 (mode 600), refusing to replace it.
write_new() {
  [ ! -e "$1" ] || fail "$1 already exists; not replacing it"
  (
    umask 077
    cat >"$1"
  )
}

new_dir() {
  mkdir -p "$1"
  chmod 700 "$1"
}

secrets() {
  local dir=$1 name
  for name in auth_secret_key credential_encryption_key admin_password; do
    [ ! -e "$dir/$name" ] || fail "$dir/$name already exists; not replacing any secret"
  done
  new_dir "$dir"
  random_hex 32 | write_new "$dir/auth_secret_key"
  # A Fernet key: 32 random bytes, URL-safe base64.
  { openssl rand 32 | openssl base64 -A | tr '+/' '-_' && echo; } | write_new "$dir/credential_encryption_key"
  random_hex 16 | write_new "$dir/admin_password"
  echo "Wrote the secrets to $dir. Save credential_encryption_key in a password manager now: without it a" \
    "backup of the database can't be decrypted. The first admin's password is in $dir/admin_password." \
    "Write database_url yourself, with the login from the database server."
}

env_file() {
  printf 'WORKER_TOKEN=%s\nMETRICS_TOKEN=%s\n' "$(random_hex 32)" "$(random_hex 32)" | write_new "$1"
  echo "Wrote $1. Give METRICS_TOKEN to Argus' Prometheus (as a secret); WORKER_TOKEN never leaves the host."
}

# Steerhouse's login on the database server can't create roles, so grafana_ro is made there by its administrator
# (docs/installing.md#steerhouse). This lets it read the analytics views (analytics-grant) and checks that it can read
# nothing else (analytics-check); both use the API's own connection.
grafana_role() {
  local root
  root=$(cd "$(dirname "$0")/.." && pwd)
  cd "$root"
  docker compose exec -T steerhouse python -m app.cli analytics-grant grafana_ro
  docker compose exec -T steerhouse python -m app.cli analytics-check grafana_ro
}

[ $# -ge 1 ] || usage
command=$1
shift
case "$command $#" in
  "secrets 1") secrets "$1" ;;
  "env 1") env_file "$1" ;;
  "grafana-role 0") grafana_role ;;
  *) usage ;;
esac
