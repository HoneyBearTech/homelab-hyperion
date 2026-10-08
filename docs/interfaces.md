# Interfaces

Everything homelab-hyperion reads, exposes or runs. homelab-hyperion has no HTTP API of its own; the services' web
UIs and APIs are documented by their projects.

> **Planned:** `compose.yaml` isn't in the repository yet. The settings, services, ports and mounts below are the
> expected ones (the upstream defaults and today's ports); they are confirmed or corrected when the stack is
> added. The scripts and commands already exist.

## Settings

### `.env`

Read by `docker compose` from `.env` next to `compose.yaml` (template: [`.env.example`](../.env.example)). A
setting marked required stops `docker compose` with an error naming it when it's missing.

| Setting | Required | Example | Meaning |
| --- | --- | --- | --- |
| `TZ` | yes | `Etc/UTC` | Time zone (tz database name) for logs and schedules. |
| `PUID`, `PGID` | yes | `1000` | User and group Prowlarr, qBittorrent and Heimdall run as; must be able to write the downloads directory. |
| `PROWLARR_CONFIG_PATH` | yes | `/srv/appdata/prowlarr` | Prowlarr's database and settings, including the indexers' credentials. |
| `QBITTORRENT_CONFIG_PATH` | yes | `/srv/appdata/qbittorrent` | qBittorrent's settings and torrent list. |
| `DOWNLOADS_PATH` | yes | `/srv/downloads` | Where qBittorrent saves downloads. Never backed up by this stack. |
| `HEIMDALL_CONFIG_PATH` | yes | `/srv/appdata/heimdall` | Heimdall's database and settings. |
| `DOZZLE_REMOTE_AGENT` | no | `agent-one.example.com:7007` | Dozzle agents on other hosts (`host:port`, comma-separated) whose containers Dozzle also shows. Empty: this host only. |
| `MINECRAFT_DATA_PATH` | yes | `/srv/appdata/minecraft-bedrock` | The Minecraft server's worlds, settings and allowlist. |
| `MINECRAFT_EULA` | yes | `TRUE` | Accepts the [Minecraft EULA](https://www.minecraft.net/eula); must be `TRUE` for the server to start. |

The Bedrock Dedicated Server's version is not a setting: it is pinned in `compose.yaml`, like the images.

No secret is a setting. If a service ever needs one in its environment, it gets its own gitignored
`<service>.env` (mode `600`) with a committed `<service>.env.example`, listed here. **Planned:**
`autoheal.env` for autoheal's optional restart notices (`WEBHOOK_URL`), as on the sibling stacks.

## Services and ports

| Service | Image | Host port → container | What |
| --- | --- | --- | --- |
| Prowlarr | `lscr.io/linuxserver/prowlarr` | 9696 → 9696 | Web UI and API (LAN only) |
| qBittorrent | `lscr.io/linuxserver/qbittorrent` | 8090 → 8090 | Web UI and API (LAN only) |
| | | 6881 → 6881 (TCP and UDP) | BitTorrent listening port (the one port meant for the internet, if forwarded) |
| Heimdall | `lscr.io/linuxserver/heimdall` | 80 → 80, 443 → 443 | Start page over HTTP and HTTPS (self-signed) (LAN only) |
| Dozzle | `amir20/dozzle` | 4040 → 8080 | Log viewer web UI (LAN only) |
| Minecraft Bedrock server | `itzg/minecraft-bedrock-server` | 19132 → 19132 (UDP) | Bedrock game port (IPv4) |
| autoheal | `willfarrell/autoheal` | none | |
| socket proxy | `lscr.io/linuxserver/socket-proxy` | none (internal network only) | Filtered Docker API for autoheal |

Exact versions and digests will be in [`compose.yaml`](../compose.yaml).

## Health checks and autoheal

Every service, autoheal and the socket proxy included, has a health check defined in `compose.yaml` and the
label `autoheal: "true"`. When Docker reports a container unhealthy, autoheal restarts it (Docker itself only
restarts a container whose process exits). Each health check has a `start_period` long enough for a slow start
after an upgrade, so autoheal doesn't restart a service in the middle of a database migration.

## Volumes and mounts

| Container path | Host source | Service |
| --- | --- | --- |
| `/config` | `PROWLARR_CONFIG_PATH` | Prowlarr: database and settings |
| `/config` | `QBITTORRENT_CONFIG_PATH` | qBittorrent: settings and torrent list |
| `/downloads` | `DOWNLOADS_PATH` | qBittorrent: downloads (read-write; never backed up) |
| `/config` | `HEIMDALL_CONFIG_PATH` | Heimdall: database and settings |
| `/data` | `MINECRAFT_DATA_PATH` | Minecraft server: worlds, `server.properties`, allowlist and permissions |
| `/var/run/docker.sock` | the Docker socket, read-only | Dozzle (allowed by label) and the socket proxy (allowed by label) |

## Labels

| Label | Meaning |
| --- | --- |
| `autoheal` | `"true"` on every service: autoheal restarts it when it turns unhealthy. |
| `org.honeybeartech.hyperion.allow.<rule>` | Lets one service break one policy rule; the value is the reason, and must not be empty. Rules: `image`, `digest`, `latest`, `build`, `privileged`, `cap-add`, `host-network`, `host-pid`, `docker-socket`, `healthcheck` ([security.md](security.md#policy)). Planned: `docker-socket` for Dozzle and the socket proxy, `latest` for autoheal (its maintained image is only published as `latest`, pinned by digest). |
| `org.honeybeartech.hyperion.backup.skip` | Container paths (comma-separated, exact) that `scripts/backup.sh` never archives and `scripts/restore.sh` refuses to write, even if a backup lists them. Planned for qBittorrent: `/downloads`. |

## Commands

| Command | Does |
| --- | --- |
| `docker compose up -d` / `down` / `ps` / `logs <service>` | Runs and inspects the stack |
| `make check` | `docker compose config --format json \| python scripts/check_compose.py`: the policy check |
| `python scripts/check_compose.py [FILE] [--sbom OUT]` | Checks a resolved Compose config (from `FILE` or stdin); `--sbom` also writes a CycloneDX 1.6 SBOM of the images. Exit 0 = no violations, 1 = violations (one line each), 2 = unreadable input |
| `make test`, `make lint` | The checker's tests and the linters |
| `scripts/backup.sh [DIR]` | Stops the stack, archives every service's data mounts (every read-write volume or bind mount except the Docker socket, anonymous volumes and the paths in the service's `backup.skip` label: the downloads directory), `.env` and any `<service>.env` into `DIR` (default `backups/<date>-<time>`, gitignored) with a `MANIFEST` and `SHA256SUMS`, all mode `600`, then starts what was running |
| `scripts/restore.sh [--yes] DIR [SERVICE...]` | Verifies `DIR/SHA256SUMS`, checks the `MANIFEST`, asks for confirmation (unless `--yes`), stops the services, replaces the contents of each listed mount with its archive, and starts what was running. Writes only mounts the service still has read-write; never the Docker socket or a path in the service's `backup.skip` label |
| `make smoke` | `scripts/smoke-test.sh`: starts every service under a separate Compose project with throwaway directories and no published ports, waits until all are healthy, round-trips a backup and restore over every data mount, checks that excluded mounts were neither archived nor overwritten and that autoheal restarts a container that turns unhealthy, then removes what it created. Exit 0 = all healthy and restored (or no `compose.yaml` yet) |

## Outbound connections

From the host: the image registries (GitHub Container Registry, Docker Hub, linuxserver.io's `lscr.io`) on
`docker compose pull`. From the services: Prowlarr to the indexers it is configured with, and to the media apps'
APIs; qBittorrent to BitTorrent trackers, peers and the DHT; the Minecraft server image downloads the pinned
Bedrock Dedicated Server from Minecraft's website on start; Heimdall to the apps it shows live stats for, if
configured; Prowlarr and qBittorrent may check for updates (which this stack doesn't apply). Dozzle to the local Docker
API and to the Dozzle agents named in `DOZZLE_REMOTE_AGENT`; autoheal only to the socket proxy.

## Release files

Each GitHub Release will have `homelab-hyperion-<version>.tar.gz` (source, with `LICENSE`),
`homelab-hyperion-<version>.cdx.json` (CycloneDX SBOM of the pinned images), `SHA256SUMS` and its Sigstore
bundle, and SLSA provenance ([verifying-releases.md](verifying-releases.md)).
