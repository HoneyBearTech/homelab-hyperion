# Architecture

homelab-hyperion is the Docker Compose definition of **Hyperion**, a homelab server for the household's
download tooling and shared services: Prowlarr and qBittorrent, which serve the media apps on another server,
a start page, a log viewer and a Minecraft Bedrock server, with autoheal keeping them running. Hyperion is an
Ubuntu 24.04 virtual machine on amd64, with no GPU. The repository holds configuration, not application code:
the services run from their upstream images, pinned by digest.

Hyperion runs the stack from a checkout of `main`, which a pull agent on the host deploys
([upgrading.md](upgrading.md#following-main)). It moved over from an older, hand-managed setup in one cutover,
adopting the existing data, ports and download paths.

## Services

| Service | Image source | Role |
| --- | --- | --- |
| Prowlarr | linuxserver.io | Indexer manager: holds the indexers' settings and credentials, and pushes them to Sonarr, Radarr and Lidarr on another host |
| qBittorrent | linuxserver.io | BitTorrent client: those apps send it torrents, it downloads them into the downloads directory, which they then import from |
| Heimdall | linuxserver.io | Start page with links (and optional live stats) for the homelab's web UIs |
| Dozzle | the project's own image | Web UI that streams the containers' logs live: this host's from the Docker API, other hosts' from Dozzle agents running there |
| Minecraft Bedrock server | `itzg/minecraft-bedrock-server`, a community wrapper | Downloads the pinned Bedrock Dedicated Server from Minecraft's site on start and runs it |
| autoheal | `willfarrell/autoheal` | Restarts any container labelled `autoheal: "true"` that Docker reports unhealthy |
| socket proxy | linuxserver.io | Gives autoheal a filtered Docker API (list, inspect, restart, stop) instead of the socket |

Other services on the same host (a media server, a transcoder, monitoring agents, a Docker management agent)
come from their own projects; this stack doesn't include or manage them.

## Actors and actions

| Actor | Does |
| --- | --- |
| Maintainer | Merges pull requests (a merge deploys), tags releases, configures each service in its web UI |
| Dependabot | Opens a pull request when an image (tag and digest), a check tool or an Action has a new version; patch, minor and major updates are auto-merged once the checks pass |
| CI | Lints, scans for secrets, tests the checker, resolves the Compose file, enforces the policy and smoke-tests the stack on amd64 on every pull request |
| Pull agent | On the maintainer's server, about every 90 seconds: fetches `main` and, when it moved, fast-forwards the checkout and runs `docker compose pull` and `docker compose up -d` (it lives in the maintainer's private orchestration repository) |
| Release workflow | On a version tag: checks the policy, writes the SBOM, signs the checksums, publishes the GitHub Release |
| LAN users | Use the web UIs, usually through the homelab's reverse proxy |
| Sonarr, Radarr, Lidarr (another host) | Call Prowlarr's and qBittorrent's APIs: search through Prowlarr, add torrents to qBittorrent, read their progress |
| BitTorrent peers and trackers | Exchange data with qBittorrent on its listening port |
| Minecraft players | Connect to the Bedrock server: a NetherNet handshake on TCP 19132, then gameplay on a UDP port from 19140–19149 |
| autoheal | Watches health through the socket proxy and restarts unhealthy containers |

## Data flow

```
LAN clients ──HTTP(S) via reverse proxy──▶ Prowlarr · qBittorrent · Heimdall · Dozzle

Sonarr / Radarr / Lidarr ──API──▶ Prowlarr ──HTTPS──▶ indexers on the internet
Prowlarr ──API (pushes indexers)──▶ Sonarr / Radarr / Lidarr
Sonarr / Radarr / Lidarr ──API──▶ qBittorrent ──BitTorrent──▶ peers, trackers, DHT
qBittorrent ──writes──▶ downloads directory ◀──imports── Sonarr / Radarr / Lidarr

Minecraft players ──UDP──▶ Minecraft Bedrock server ──HTTPS on start──▶ Minecraft's download site

Dozzle ──Docker socket (read-only mount)──▶ Docker API
Dozzle ──agent protocol──▶ Dozzle agents on other hosts (optional)
autoheal ──filtered API──▶ socket proxy ──▶ Docker socket
```

Each service keeps its settings and database in its own folder on the host, `CONFIG_ROOT/<app>/config` (see
[interfaces.md](interfaces.md#volumes-and-mounts)), which is what `scripts/backup.sh` archives; no app data is in a
Docker volume. The downloads
directory is never archived.

## How changes reach the host

1. Dependabot (or the maintainer) opens a pull request that changes an image's tag and digest. The Minecraft
   server's own version, set in `compose.yaml`, is changed by hand the same way.
2. CI resolves the Compose file, runs the policy check and the smoke test; the maintainer reads the service's
   release notes.
3. The pull request is squash-merged (automatically for Dependabot's patch, minor and major updates and image
   rebuilds, once every check passes, with the nightly backup behind them; by the maintainer, after a backup, for
   any other change that can migrate data, such as the Minecraft server's version).
4. Within about 90 seconds the pull agent on the host sees `main` move, fast-forwards its checkout and runs
   `docker compose pull && docker compose up -d --remove-orphans --wait`
   ([upgrading.md](upgrading.md#following-main)). A rollback is a revert pull request, deployed the same way.
   While a backup or a restore holds the agent's lock, the agent skips its runs, so it never recreates a service
   they have stopped; the merge deploys once they're done.
5. A version tag makes a signed release: a named, verifiable snapshot of `main`.

Nothing updates from a registry by itself: a version that runs is always a version that's in `main`. The host
only pulls; nothing connects in to it to deploy.

## Repository layout

| Path | What |
| --- | --- |
| `compose.yaml` | The stack |
| `.env.example` | Template for the settings |
| `autoheal.env.example` | Template for autoheal's optional restart webhook (a secret) |
| `backup.env.example` | Template for the scheduled backup's settings |
| `scripts/check_compose.py` | The policy check and SBOM generator (standard-library Python) |
| `scripts/backup.sh`, `scripts/restore.sh` | Backup and restore of every service's data, never the downloads |
| `scripts/scheduled-backup.sh`, `deploy/systemd/` | Nightly backup, copied off the host with rsync and pruned, reported to an Uptime Kuma push monitor |
| `scripts/smoke-test.sh` | Starts the stack in isolation, waits for health, and round-trips a backup |
| `tests/` | The checker's tests, with JSON fixtures |
| `docs/` | This documentation |
| `.github/` | CI, release and security workflows, Dependabot, templates |
| `.gitlab-ci.yml` | The pipeline of the copy on the maintainer's GitLab: mirrors GitHub, re-runs the daemon-free checks |
