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
#   scripts/steerhouse.sh request DIR          on the host: the database's key (server.key) and a signing request
#                                              (server.csr) in DIR (CONFIG_ROOT/steerhouse-postgres/config/tls)
#   scripts/steerhouse.sh sign CA_DIR CSR CRT NAME...
#                                              on the CA's machine: CRT, the certificate for CSR, signed by the CA in
#                                              CA_DIR, for each NAME (a DNS name or an IP address Argus connects to),
#                                              valid 3 years; copy it and the CA's ca.crt into DIR
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

# The key never leaves the host: only the signing request goes to the CA's machine, and only certificates come back.
request() {
  local dir=$1 config
  new_dir "$dir"
  [ ! -e "$dir/server.key" ] || fail "$dir/server.key already exists; not replacing it"
  config=$(mktemp)
  printf '[req]\ndistinguished_name = dn\nprompt = no\n[dn]\nCN = Steerhouse database\n' >"$config"
  (
    umask 077
    openssl req -new -newkey rsa:3072 -nodes -sha256 -config "$config" -keyout "$dir/server.key" \
      -out "$dir/server.csr" 2>/dev/null
  ) || {
    rm -f "$config"
    fail "openssl couldn't make the key"
  }
  rm -f "$config"
  chmod 644 "$dir/server.csr"
  echo "Wrote $dir/server.key (it stays here) and $dir/server.csr: sign the request with the CA (sign)."
}

sign() {
  local ca_dir=$1 csr=$2 crt=$3 config sans="" name n=0
  shift 3
  [ -f "$ca_dir/ca.crt" ] && [ -f "$ca_dir/ca.key" ] || fail "$ca_dir has no ca.crt and ca.key"
  [ -f "$csr" ] || fail "$csr doesn't exist"
  [ ! -e "$crt" ] || fail "$crt already exists; not replacing it"
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
  config=$(mktemp)
  cat >"$config" <<CONF
[server]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @names
[names]
$sans
CONF
  # The request names nothing that counts: the certificate's names are only those given here.
  openssl x509 -req -sha256 -days 1095 -in "$csr" -CA "$ca_dir/ca.crt" -CAkey "$ca_dir/ca.key" \
    -set_serial "0x$(random_hex 16)" -extfile "$config" -extensions server -out "$crt" 2>/dev/null || {
    rm -f "$config"
    fail "openssl couldn't sign $csr"
  }
  rm -f "$config"
  chmod 644 "$crt"
  openssl verify -CAfile "$ca_dir/ca.crt" "$crt" >/dev/null
  echo "Wrote $crt (for: $*). Copy it, as server.crt, and $ca_dir/ca.crt next to the database's server.key."
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
  "request 1") request "$1" ;;
  "sign "*) if [ $# -ge 4 ]; then sign "$@"; else usage; fi ;;
  "grafana-role 0") grafana_role ;;
  *) usage ;;
esac
