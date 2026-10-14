# Interfaces

Everything homelab-hyperion reads, exposes or runs. homelab-hyperion has no HTTP API of its own; the services' web
UIs and APIs are documented by their projects.

## Settings

### `.env`

Read by `docker compose` from `.env` next to `compose.yaml` (template: [`.env.example`](../.env.example)). A
setting marked required stops `docker compose` with an error naming it when it's missing.

| Setting | Required | Example | Meaning |
| --- | --- | --- | --- |
| `TZ` | yes | `Etc/UTC` | Time zone (tz database name) for logs and schedules. |
| `PUID`, `PGID` | yes | `1000` | User and group Prowlarr, qBittorrent, Heimdall and the Minecraft server run as; must own the data directories and be able to write the downloads directory. |
| `PROWLARR_CONFIG_PATH` | yes | `/srv/appdata/prowlarr` | Prowlarr's database and settings, including the indexers' credentials. |
| `QBITTORRENT_CONFIG_PATH` | yes | `/srv/appdata/qbittorrent` | qBittorrent's settings and torrent list. |
| `DOWNLOADS_PATH` | yes | `/srv/downloads` | Where qBittorrent saves downloads. Never backed up by this stack. |
| `HEIMDALL_CONFIG_PATH` | yes | `/srv/appdata/heimdall` | Heimdall's database and settings. |
| `DOZZLE_REMOTE_AGENT` | no | `agent-one.example.com:7007` | Dozzle agents on other hosts (`host:port`, comma-separated) whose containers Dozzle also shows. Empty: this host only. |
| `MINECRAFT_DATA_PATH` | yes | `/srv/appdata/minecraft-bedrock` | The Minecraft server's worlds, settings and allowlist. |
| `MINECRAFT_LEVEL_NAME` | yes | `Bedrock level` | The world the server opens: the name of its folder under `worlds/` in `MINECRAFT_DATA_PATH`. A new installation starts a new world with this name. |
| `MINECRAFT_ADDRESS` | yes | `192.0.2.10` | The address players reach this host at (an IP literal, not a hostname). The server hands it to each client with its gameplay port. |
| `MINECRAFT_EULA` | yes | `TRUE` | Accepts the [Minecraft EULA](https://www.minecraft.net/eula); must be `TRUE` for the server to start. |

The Bedrock Dedicated Server's version is not a setting: it is pinned in `compose.yaml` (`VERSION`), like the
images, and so are its allowlist (on) and its transport (NetherNet, the only one clients use since 1.26.50).
Its other game settings live in `server.properties` in its data directory.

No secret is a setting. A service that needs one in its environment gets its own gitignored `<service>.env`
(mode `600`) with a committed `<service>.env.example`, listed below.

### `autoheal.env`

Read by the `autoheal` service (template: [`autoheal.env.example`](../autoheal.env.example)); optional, mode
`600`, gitignored.

| Setting | Meaning |
| --- | --- |
| `WEBHOOK_URL` | Where autoheal posts a notice each time it restarts a container (a secret). A Discord channel webhook works as is; empty or missing = log only |

### `backup.env`

Read by `scripts/scheduled-backup.sh` (template: [`backup.env.example`](../backup.env.example)); optional, mode
`600`, gitignored. Read as data, never run: only these keys, one `KEY=value` per line; anything else is an error.

| Setting | Default | Meaning |
| --- | --- | --- |
| `BACKUP_DIR` | `backups` | Where backups are written (relative to the checkout, or absolute). |
| `BACKUP_KEEP` | `3` | How many backups are kept in `BACKUP_DIR`; older ones are deleted. |
| `BACKUP_REMOTE` | empty | rsync destination each backup is copied to, such as `backup-host:/volume1/hyperion-backups` (an SSH alias); empty = no copy. |
| `BACKUP_REMOTE_KEEP` | `30` | How many backups are kept at `BACKUP_REMOTE`; older ones are deleted. |
| `BACKUP_PING_URL` | empty | An Uptime Kuma push URL (a secret), told `up` after each good run and `down` after a failed one. |

Only directories named like a backup (`<date>-<time>`) are ever deleted, here or at the remote.

## Services and ports

| Service | Image | Host port → container | What |
| --- | --- | --- | --- |
| Prowlarr | `lscr.io/linuxserver/prowlarr` | 9696 → 9696 | Web UI and API (LAN only) |
| qBittorrent | `lscr.io/linuxserver/qbittorrent` | 8090 → 8080 | Web UI and API (LAN only) |
| | | 6881 → 6881 (TCP and UDP) | BitTorrent listening port (the one port meant for the internet, if forwarded) |
| Heimdall | `lscr.io/linuxserver/heimdall` | 80 → 80, 443 → 443 | Start page over HTTP and HTTPS (self-signed) (LAN only) |
| Dozzle | `amir20/dozzle` | 4040 → 8080 | Log viewer web UI (LAN only) |
| Minecraft Bedrock server | `itzg/minecraft-bedrock-server` | 19132 → 19132 (TCP) | NetherNet handshake (IPv4 and IPv6) |
| | | 19140–19149 → 19140–19149 (UDP) | NetherNet gameplay, one port per player (`max-players` 10) |
| autoheal | `willfarrell/autoheal` | none | Restarts unhealthy containers, through the socket proxy |
| socket proxy | `lscr.io/linuxserver/socket-proxy` | none (internal network only) | Filtered Docker API for autoheal |

Ports are published on every host interface. Exact versions and digests are in [`compose.yaml`](../compose.yaml).

## Health checks and autoheal

Every service has a health check defined in `compose.yaml`, and every service but autoheal itself has the
label `autoheal: "true"`. When Docker reports a container unhealthy, autoheal restarts it (Docker itself only
restarts a container whose process exits). Each health check has a `start_period` long enough for a slow start
after an upgrade (10 minutes; 1 minute for autoheal and the socket proxy), so autoheal doesn't restart a service
in the middle of a database migration or while the Minecraft image downloads its server.

## Volumes and mounts

| Container path | Host source | Service |
| --- | --- | --- |
| `/config` | `PROWLARR_CONFIG_PATH` | Prowlarr: database and settings |
| `/config` | `QBITTORRENT_CONFIG_PATH` | qBittorrent: settings and torrent list |
| `/downloads` | `DOWNLOADS_PATH` | qBittorrent: downloads (read-write; never backed up) |
| `/config` | `HEIMDALL_CONFIG_PATH` | Heimdall: database and settings |
| `/data` | `MINECRAFT_DATA_PATH` | Minecraft server: worlds, `server.properties`, allowlist and permissions |
| `/var/run/docker.sock` | the Docker socket, read-only | Dozzle (allowed by label) and the socket proxy (allowed by label) |

The socket proxy and autoheal share the internal network `docker-proxy`, which has no route out and nothing
published; autoheal also joins the default network, to reach its webhook.

## Labels

| Label | Meaning |
| --- | --- |
| `autoheal` | `"true"` on every service autoheal may restart when its health check fails (every service but autoheal). |
| `org.honeybeartech.hyperion.allow.<rule>` | Lets one service break one policy rule; the value is the reason, and must not be empty. Rules: `image`, `digest`, `latest`, `build`, `privileged`, `cap-add`, `host-network`, `host-pid`, `docker-socket`, `healthcheck` ([security.md](security.md#policy)). In use: `docker-socket` for Dozzle and the socket proxy, `latest` for autoheal (its maintained image is only published as `latest`, pinned by digest). |
| `org.honeybeartech.hyperion.backup.skip` | Container paths (comma-separated, exact) that `scripts/backup.sh` never archives and `scripts/restore.sh` refuses to write, even if a backup lists them. In use: qBittorrent's `/downloads`. |
| `org.honeybeartech.hyperion.backup.exclude` | Paths inside a service's data mounts (comma-separated, exact container paths, at any depth) that `scripts/backup.sh` leaves out of the mount's archive and `scripts/restore.sh` leaves in place. A path that isn't inside one of the service's data mounts, or contains `..` or a pattern character (`*?[\`), makes both fail before anything stops. Not in use. |

## Commands

| Command | Does |
| --- | --- |
| `docker compose up -d` / `down` / `ps` / `logs <service>` | Runs and inspects the stack |
| `make check` | `docker compose config --format json \| python scripts/check_compose.py`: the policy check |
| `python scripts/check_compose.py [FILE] [--sbom OUT]` | Checks a resolved Compose config (from `FILE` or stdin); `--sbom` also writes a CycloneDX 1.6 SBOM of the images. Exit 0 = no violations, 1 = violations (one line each), 2 = unreadable input |
| `make test`, `make lint` | The checker's tests and the linters |
| `scripts/backup.sh [DIR]` | Archives every service's data mounts (every read-write volume or bind mount except the Docker socket, anonymous volumes and the paths in the service's `backup.skip` label: the downloads directory; a mount inside another mount is archived on its own and left out of the outer archive), `.env` and any `<service>.env` into `DIR` (default `backups/<date>-<time>`, gitignored) with a `MANIFEST`, `NETWORKS` (the address range of each network the stack uses but doesn't create; this stack has none, so only the header), `VERSION` (the checkout's `git describe`) and `SHA256SUMS`, all mode `600`. Each service is stopped only while its own mounts are copied and started again (with any service Compose stopped along with it) before the copies are compressed (with `pigz` when it's installed, else `gzip`). Leaves out the paths a service's `org.honeybeartech.hyperion.backup.exclude` label lists. Exit 0 = backup complete |
| `scripts/scheduled-backup.sh` | Runs `scripts/backup.sh` into `BACKUP_DIR/<date>-<time>`, copies it to `BACKUP_REMOTE` with rsync (`SHA256SUMS` last), deletes all but the newest `BACKUP_REMOTE_KEEP` there and `BACKUP_KEEP` here, and reports to `BACKUP_PING_URL` ([`backup.env`](#backupenv)). Run nightly at 04:30 by the systemd user units in `deploy/systemd/` |
| `scripts/restore.sh [--yes] DIR [SERVICE...]` | Verifies `DIR/SHA256SUMS`, checks the `MANIFEST`, asks for confirmation (unless `--yes`), stops the services, replaces the contents of each listed mount with its archive, and starts what was running. Writes only mounts the service still has read-write; never the Docker socket, a path in the service's `backup.skip` label, another mount inside the one it restores, or a path in its `backup.exclude` label |
| `make smoke` | `scripts/smoke-test.sh`: starts every service under a separate Compose project with throwaway directories (owned by `PUID`:`PGID` with mode 0755, as on the host) and no published ports, waits until all are healthy, round-trips a backup and restore over every data mount, checks that excluded mounts and paths were neither archived nor overwritten and that the backup has `NETWORKS` and `VERSION`, runs the scheduled backup against a stand-in backup server and checks the copy and the pruning, checks that autoheal restarts a container that turns unhealthy, then removes what it created. Exit 0 = all healthy and restored |

## Outbound connections

From the host: the image registries (GitHub Container Registry, Docker Hub, linuxserver.io's `lscr.io`) on
`docker compose pull`. From the services: Prowlarr to the indexers it is configured with, and to the media apps'
APIs; qBittorrent to BitTorrent trackers, peers and the DHT; the Minecraft server image downloads the pinned
Bedrock Dedicated Server from Minecraft's website on start; Heimdall to the apps it shows live stats for, if
configured; Prowlarr and qBittorrent may check for updates (which this stack doesn't apply). Dozzle to the local Docker
API and to the Dozzle agents named in `DOZZLE_REMOTE_AGENT`; autoheal only to the socket proxy.

The scheduled backup talks to `BACKUP_REMOTE` (rsync, usually over SSH) and `BACKUP_PING_URL`, if they are set.

## Release files

Each GitHub Release has `homelab-hyperion-<version>.tar.gz` (source, with `LICENSE`),
`homelab-hyperion-<version>.cdx.json` (CycloneDX SBOM of the pinned images), `SHA256SUMS` and its Sigstore
bundle, and SLSA provenance ([verifying-releases.md](verifying-releases.md)).
