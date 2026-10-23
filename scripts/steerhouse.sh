#!/usr/bin/env bash
# Steerhouse's secrets, its database's TLS certificate and the read-only role Argus' Grafana logs in as
# (docs/installing.md#steerhouse). Run on the host, as the user the stack runs as (PUID): every file it writes belongs
# to that user, mode 600, in a directory of mode 700. It never overwrites a file that exists.
#
#   scripts/steerhouse.sh secrets DIR          the secret files in DIR (CONFIG_ROOT/steerhouse/secrets), new random
#                                              values; the first admin's password is admin_password
#   scripts/steerhouse.sh env FILE             FILE (steerhouse.env) with a new WORKER_TOKEN and METRICS_TOKEN
#   scripts/steerhouse.sh ca DIR               a new certificate authority in DIR (ca.crt, ca.key), valid 10 years;
#                                              keep DIR off the host
#   scripts/steerhouse.sh cert CA_DIR DIR NAME...
#                                              the database's certificate and key, signed by the CA in CA_DIR, for
#                                              each NAME (a DNS name or an IP address Argus connects to), valid 3
#                                              years, with the CA's certificate, in DIR
#                                              (CONFIG_ROOT/steerhouse-postgres/config/tls)
#   scripts/steerhouse.sh grafana-role         create grafana_ro, or set its password to grafana_db_password again,
#                                              in the running stack
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
  local dir=$1 password name
  for name in postgres_password database_url auth_secret_key credential_encryption_key admin_password \
    grafana_db_password; do
    [ ! -e "$dir/$name" ] || fail "$dir/$name already exists; not replacing any secret"
  done
  new_dir "$dir"
  password=$(random_hex 24)
  printf '%s\n' "$password" | write_new "$dir/postgres_password"
  # The database's host is its service name, on the internal network steerhouse-db.
  printf 'postgresql+psycopg://steerhouse:%s@steerhouse-postgres:5432/steerhouse\n' "$password" |
    write_new "$dir/database_url"
  random_hex 32 | write_new "$dir/auth_secret_key"
  # A Fernet key: 32 random bytes, URL-safe base64.
  { openssl rand 32 | openssl base64 -A | tr '+/' '-_' && echo; } | write_new "$dir/credential_encryption_key"
  random_hex 16 | write_new "$dir/admin_password"
  random_hex 24 | write_new "$dir/grafana_db_password"
  echo "Wrote the secrets to $dir. Save credential_encryption_key in a password manager now: without it a" \
    "backup of the database can't be decrypted. The first admin's password is in $dir/admin_password."
}

env_file() {
  printf 'WORKER_TOKEN=%s\nMETRICS_TOKEN=%s\n' "$(random_hex 32)" "$(random_hex 32)" | write_new "$1"
  echo "Wrote $1. Give METRICS_TOKEN to Argus' Prometheus (as a secret); WORKER_TOKEN never leaves the host."
}

ca() {
  local dir=$1 config
  new_dir "$dir"
  [ ! -e "$dir/ca.key" ] && [ ! -e "$dir/ca.crt" ] || fail "$dir already holds a CA; not replacing it"
  config=$(mktemp)
  cat >"$config" <<'CONF'
[req]
distinguished_name = dn
prompt = no
x509_extensions = ca
[dn]
CN = Steerhouse database CA
[ca]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
CONF
  (
    umask 077
    openssl req -x509 -new -newkey rsa:3072 -nodes -sha256 -days 3650 -config "$config" \
      -keyout "$dir/ca.key" -out "$dir/ca.crt" 2>/dev/null
  ) || {
    rm -f "$config"
    fail "openssl couldn't make the CA"
  }
  rm -f "$config"
  chmod 644 "$dir/ca.crt"
  echo "Wrote $dir/ca.crt (give it to Argus) and $dir/ca.key (keep it off the host, with the secrets)."
}

cert() {
  local ca_dir=$1 dir=$2 config sans="" name n=0
  shift 2
  [ $# -ge 1 ] || usage
  [ -f "$ca_dir/ca.crt" ] && [ -f "$ca_dir/ca.key" ] || fail "$ca_dir has no ca.crt and ca.key"
  for name in "$@"; do
    n=$((n + 1))
    if [[ $name =~ ^[0-9.]+$ || $name == *:* ]]; then
      sans="${sans}IP.$n = $name"$'\n'
    elif [[ $name =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
      sans="${sans}DNS.$n = $name"$'\n'
    else
      fail "$name is neither a DNS name nor an IP address"
    fi
  done
  new_dir "$dir"
  [ ! -e "$dir/server.key" ] && [ ! -e "$dir/server.crt" ] || fail "$dir already holds a certificate; not replacing it"
  config=$(mktemp -d)
  cat >"$config/req.conf" <<CONF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = $1
[server]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @names
[names]
$sans
CONF
  (
    umask 077
    openssl req -new -newkey rsa:3072 -nodes -sha256 -config "$config/req.conf" \
      -keyout "$dir/server.key" -out "$config/server.csr" 2>/dev/null
  )
  openssl x509 -req -sha256 -days 1095 -in "$config/server.csr" -CA "$ca_dir/ca.crt" -CAkey "$ca_dir/ca.key" \
    -set_serial "0x$(random_hex 16)" -extfile "$config/req.conf" -extensions server -out "$dir/server.crt" 2>/dev/null
  rm -rf "$config"
  cp "$ca_dir/ca.crt" "$dir/ca.crt"
  chmod 644 "$dir/server.crt" "$dir/ca.crt"
  openssl verify -CAfile "$dir/ca.crt" "$dir/server.crt" >/dev/null
  echo "Wrote $dir/server.crt and server.key (for: $*), and ca.crt, the certificate Argus checks it against."
}

# monitoring-setup is the one-shot of Steerhouse's own `monitoring` profile: it creates the role as Steerhouse
# documents (LOGIN NOINHERIT CONNECTION LIMIT 10, read-only transactions, statement_timeout 30s, search_path
# analytics, CONNECT only), grants it the analytics views (analytics-grant) and checks that it can read nothing else
# (analytics-check). It also writes Prometheus' and Grafana's configuration, which Argus doesn't need: into a
# temporary directory in the API's container, removed again.
grafana_role() {
  local root
  root=$(cd "$(dirname "$0")/.." && pwd)
  cd "$root"
  # shellcheck disable=SC2016 # expanded by the container's shell
  docker compose exec -T steerhouse sh -c 'd=$(mktemp -d) &&
    python -m app.cli monitoring-setup --prometheus-dir "$d/prometheus" --grafana-dir "$d/grafana"
    status=$?; rm -rf "$d"; exit $status'
}

[ $# -ge 1 ] || usage
command=$1
shift
case "$command $#" in
  "secrets 1") secrets "$1" ;;
  "env 1") env_file "$1" ;;
  "ca 1") ca "$1" ;;
  "cert "*) if [ $# -ge 3 ]; then cert "$@"; else usage; fi ;;
  "grafana-role 0") grafana_role ;;
  *) usage ;;
esac
