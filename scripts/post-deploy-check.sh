#!/usr/bin/env bash
# The check the pull agent runs on the server after each deploy of main (homelab-pull 0.5.0 and later, whose CHECK
# setting names this file): that Dozzle sees every agent in DOZZLE_REMOTE_AGENT, restarting it once when it doesn't.
#
# Dozzle dials each agent once, when it starts, and never dials one that didn't answer then: a hub started while an
# agent's host is down or in the middle of its own deploy keeps that host marked unavailable (and its own health
# check stays green) until the hub is restarted (amir20/dozzle#5624). A hub that is already running does reconnect
# to an agent that goes away and comes back. So after a deploy, this reads Dozzle's page, and if a host is
# unavailable after DOZZLE_CHECK_WAIT seconds, restarts the hub and reads the page again.
#
# It passes (exit 0) when Dozzle sees every host, or when there is nothing to check (Dozzle isn't running, or
# DOZZLE_REMOTE_AGENT is empty). It exits 1 when a host is still unavailable after the restart (its agent really is
# down): the agent then records the deploy's check as failed (`failed:check`, which alerts), keeps the deploy, and
# runs this again when it retries (about every 15 minutes), restarting the hub again. Only Dozzle, a log viewer, is
# restarted; nothing else is touched.
#
# It runs in the checkout, where the agent's COMPOSE_FILE and the .env apply, and reads Dozzle's page on the host's
# published port (DOZZLE_CHECK_URL, default http://127.0.0.1:4040/).
#
# Settings, all optional:
#   DOZZLE_CHECK_URL   Dozzle's address on this host (default http://127.0.0.1:4040/)
#   DOZZLE_CHECK_WAIT  seconds to wait for every host to be available, before and after a restart (default 90;
#                      keep twice it below the agent's CHECK_TIMEOUT, 600 by default)
set -euo pipefail

cd "$(dirname "$0")/.."

url=${DOZZLE_CHECK_URL:-http://127.0.0.1:4040/}
wait_for=${DOZZLE_CHECK_WAIT:-90}
case $wait_for in
'' | *[!0-9]*)
  echo "DOZZLE_CHECK_WAIT must be a number of seconds" >&2
  exit 2
  ;;
esac

# The hosts on Dozzle's page (its config__json) that aren't available, one endpoint per line; nothing when every
# host is. Fails when the page can't be read.
unavailable_hosts() {
  python3 -I -c '
import json, re, sys, urllib.request
with urllib.request.urlopen(sys.argv[1], timeout=10) as page:  # noqa: S310
    match = re.search(r"id=\"config__json\"[^>]*>([^<]*)<", page.read().decode())
if not match:
    sys.exit("no config__json on the page")
for host in json.loads(match.group(1))["hosts"]:
    if not host["available"]:
        print(host["endpoint"])' "$url"
}

# Waits up to $wait_for seconds for every host to be available; leaves the ones that aren't in `down`.
wait_for_hosts() {
  local deadline=$((SECONDS + wait_for))
  while :; do
    if down=$(unavailable_hosts 2>/dev/null) && [ -z "$down" ]; then return 0; fi
    if [ "$SECONDS" -ge "$deadline" ]; then return 1; fi
    sleep 5
  done
}

if [ -z "$(docker compose ps --status running --quiet dozzle)" ]; then
  echo "Dozzle isn't running: nothing to check"
  exit 0
fi
# (The image has no shell or printenv to ask the container, so ask Compose for the setting it was started with.)
agents=$(docker compose config --format json |
  python3 -I -c 'import json, sys; print(json.load(sys.stdin)["services"]["dozzle"]["environment"].get("DOZZLE_REMOTE_AGENT") or "")')
if [ -z "$agents" ]; then
  echo "Dozzle has no agents (DOZZLE_REMOTE_AGENT is empty): nothing to check"
  exit 0
fi

down=""
if wait_for_hosts; then
  echo "Dozzle sees every host"
  exit 0
fi
echo "Dozzle doesn't see: ${down:-its page is unreadable}; restarting it, which dials every agent again"
docker compose restart dozzle
if wait_for_hosts; then
  echo "Dozzle sees every host after the restart"
  exit 0
fi
echo "Dozzle still doesn't see: ${down:-its page is unreadable} (is that agent's host down?)" >&2
exit 1
