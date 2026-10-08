# Architecture

homelab-hyperion is the Docker Compose definition of **Hyperion**, a homelab server for the household's
download tooling and shared services: Prowlarr and qBittorrent, which serve the media apps on another server,
a start page, a log viewer and a Minecraft Bedrock server, with autoheal keeping them running. Hyperion is an
Ubuntu 24.04 virtual machine on amd64, with no GPU. The repository holds configuration, not application code:
the services run from their upstream images, pinned by digest.

> **Planned:** `compose.yaml` isn't in the repository yet. This page describes the stack it will define; the
> services run today from an older, hand-managed setup on the host and move over in one planned cutover.

## Services

| Service | Image source | Role |
| --- | --- | --- |
| Prowlarr | linuxserver.io | Indexer manager: holds the indexers' settings and credentials, and pushes them to Sonarr, Radarr and Lidarr on another host |
| qBittorrent | linuxserver.io | BitTorrent client: those apps send it torrents, it downloads them into the downloads directory, which they then import from |
| Heimdall | linuxserver.io | Start page with links (and optional live stats) for the homelab's web UIs |
| Dozzle | the project's own image | Web UI that streams the containers' logs live: this host's from the Docker API, other hosts' from Dozzle agents running there |
| Minecraft Bedrock server | `itzg/minecraft-bedrock-server`, a community wrapper | Downloads the pinned Bedrock Dedicated Server from Minecraft's site on start and runs it |
| autoheal | `willfarrell/autoheal` | Restarts any container labelled `autoheal: "true"` that Docker reports unhealthy |
| socket proxy | linuxserver.io | Gives autoheal a filtered Docker API (list, inspect, restart) instead of the socket |

Other services on the same host (a media server, a transcoder, monitoring agents, a Docker management agent)
come from their own projects; this stack doesn't include or manage them.

## Actors and actions

| Actor | Does |
| --- | --- |
| Maintainer | Merges pull requests, tags releases, runs `git pull` / `docker compose up -d` on the host, configures each service in its web UI |
| Dependabot | Opens a pull request when an image (tag and digest), a check tool or an Action has a new version; patch and minor updates are auto-merged once the checks pass |
| CI | Lints, scans for secrets, tests the checker, resolves the Compose file, enforces the policy and smoke-tests the stack on amd64 on every pull request |
| Release workflow | On a version tag: checks the policy, writes the SBOM, signs the checksums, publishes the GitHub Release |
| LAN users | Use the web UIs, usually through the homelab's reverse proxy |
| Sonarr, Radarr, Lidarr (another host) | Call Prowlarr's and qBittorrent's APIs: search through Prowlarr, add torrents to qBittorrent, read their progress |
| BitTorrent peers and trackers | Exchange data with qBittorrent on its listening port |
| Minecraft players | Connect to the Bedrock server on its UDP port |
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

Each service keeps its settings and database in its own data directory (see
[interfaces.md](interfaces.md#volumes-and-mounts)), which is what `scripts/backup.sh` archives. The downloads
directory is never archived.

## How changes reach the host

1. Dependabot (or the maintainer) opens a pull request that changes an image's tag and digest. The Minecraft
   server's own version, set in `compose.yaml`, is changed by hand the same way.
2. CI resolves the Compose file, runs the policy check and the smoke test; the maintainer reads the service's
   release notes.
3. The pull request is squash-merged (automatically for Dependabot's patch and minor updates, once every
   check passes); a version tag makes a signed release.
4. On the host: back up, `git checkout <tag>`, `docker compose pull && docker compose up -d`
   ([upgrading.md](upgrading.md)).

Nothing on the host updates itself: a version that runs is always a version that's in git.

## Repository layout

| Path | What |
| --- | --- |
| `compose.yaml` | The stack (**Planned**) |
| `.env.example` | Template for the settings |
| `scripts/check_compose.py` | The policy check and SBOM generator (standard-library Python) |
| `scripts/backup.sh`, `scripts/restore.sh` | Backup and restore of every service's data, never the downloads |
| `scripts/smoke-test.sh` | Starts the stack in isolation, waits for health, and round-trips a backup |
| `tests/` | The checker's tests, with JSON fixtures |
| `docs/` | This documentation |
| `.github/` | CI, release and security workflows, Dependabot, templates |
