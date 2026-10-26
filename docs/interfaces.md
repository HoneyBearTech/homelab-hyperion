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
| `PUID`, `PGID` | yes | `1000` | User and group Prowlarr, qBittorrent, Heimdall, the Minecraft server and Steerhouse's API and database run as; must own those apps' folders under `CONFIG_ROOT` (and Steerhouse's secrets) and be able to write the downloads and incomplete directories. |
| `CONFIG_ROOT` | yes | `/srv/config` | Host directory with each app's folder: `<app>/config` holds its settings and database (Minecraft's worlds), for `prowlarr`, `qbittorrent`, `heimdall`, `minecraft`, `dozzle`, `steerhouse` and `steerhouse-postgres`, mounted at the app's data path ([below](#volumes-and-mounts)), `steerhouse/secrets` Steerhouse's secret files ([below](#steerhouses-secret-files)), and `dozzle/certs` Dozzle's certificate and key ([below](#dozzles-certificate-files)). Owned by `PUID:PGID`, except `dozzle/config` and `dozzle/certs`, owned by root. Holds Prowlarr's indexer credentials, Steerhouse's encrypted SSH keys and every login: back it up. Never a path inside `/var/lib/docker/volumes` ([installing.md](installing.md#where-data-lives)). |
| `DOWNLOADS_PATH` | yes | `/srv/downloads` | Where qBittorrent saves downloads. Never backed up by this stack. |
| `INCOMPLETE_PATH` | yes | `/srv/incomplete` | Where qBittorrent keeps torrents still downloading, mounted at `/incomplete`. Never backed up by this stack. |
| `DOZZLE_REMOTE_AGENT` | no | `agent-one.example.com:7007` | Dozzle agents on other hosts (`host:port`, comma-separated) whose containers Dozzle also shows. Empty: this host only. |
| `MINECRAFT_LEVEL_NAME` | yes | `Bedrock level` | The world the server opens: the name of its folder under `worlds/` in `CONFIG_ROOT/minecraft/config`. A new installation starts a new world with this name. |
| `MINECRAFT_ADDRESS` | yes | `192.0.2.10` | The address players reach this host at (an IP literal, not a hostname). The server hands it to each client with its gameplay port. |
| `MINECRAFT_EULA` | yes | `TRUE` | Accepts the [Minecraft EULA](https://www.minecraft.net/eula); must be `TRUE` for the server to start. |
| `STEERHOUSE_PORT` | yes | `8085` | Host port of Steerhouse's web UI, which the reverse proxy serves over HTTPS (with WebSockets). |
| `STEERHOUSE_PUBLIC_URL` | yes | `https://steerhouse.example.com` | The address people open Steerhouse at, through the reverse proxy: notifications link to it, single sign-on and passkeys depend on it. |
| `STEERHOUSE_TRUSTED_PROXIES` | yes | `192.0.2.20` | The reverse proxy's address (comma-separated addresses or CIDRs): the only peers whose `X-Forwarded-For` Steerhouse believes (login throttling, audit log). |
| `STEERHOUSE_METRICS_PORT` | yes | `8002` | Host port of the API's Prometheus metrics, for Argus; answers only with `METRICS_TOKEN`. |
| `STEERHOUSE_POSTGRES_PORT` | yes | `5432` | Host port of Steerhouse's database, for Argus' Grafana: TLS only, and only the read-only role `grafana_ro`. |
| `STEERHOUSE_DB_SUBNET` | yes | `172.16.90.0/28` | Address range of `steerhouse-db`, the internal network of Steerhouse's API and database; the app's own database user may connect from there only. A private range no other network on the host uses. |

The Bedrock Dedicated Server's version is not a setting: it is pinned in `compose.yaml` (`VERSION`), like the
images, and so are its allowlist (on) and its transport (NetherNet, the only one clients use since 1.26.50).
Its other game settings live in `server.properties` in its folder, `CONFIG_ROOT/minecraft/config`.

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
| `BACKUP_AGE_RECIPIENT` | empty | An age public key (`age1...`). When set, the copy at `BACKUP_REMOTE` is only `backup.tar.age` (the backup directory as one tar archive, encrypted to that key) and its `SHA256SUMS`; `age -d -i <private key> backup.tar.age \| tar -x` gives back the backup directory that `scripts/restore.sh` reads. Needs `age` on the host. Empty = the backup is copied as it is. |

Only directories named like a backup (`<date>-<time>`) are ever deleted, here or at the remote.

### `steerhouse.env`

Read by the `steerhouse` and `steerhouse-worker` services (template:
[`steerhouse.env.example`](../steerhouse.env.example)); mode `600`, gitignored. Without it the API refuses to start.
`scripts/steerhouse.sh env steerhouse.env` writes one with new random values.

| Setting | Meaning |
| --- | --- |
| `WORKER_TOKEN` | Shared by the API and the workers (at least 32 characters). In the environment because the workers can't read secret files safely: they run playbooks as other users. |
| `METRICS_TOKEN` | The bearer token Argus' Prometheus sends for `/metrics` on `STEERHOUSE_METRICS_PORT` (at least 32 characters, unlike the others). Empty = no metrics. |

### Steerhouse's secret files

Docker secrets: files in `CONFIG_ROOT/steerhouse/secrets` (mode `700`, the files `600`, owned by `PUID:PGID`), which
Compose mounts read-only at `/run/secrets/<name>` in the services that need them. Never committed, and never in the
stack's backups: keep them in a password manager. `scripts/steerhouse.sh secrets CONFIG_ROOT/steerhouse/secrets`
writes them all with new random values.

| File | Read by | Meaning |
| --- | --- | --- |
| `postgres_password` | `steerhouse-postgres` (first start only) | The password of the database's own user, `steerhouse` |
| `database_url` | `steerhouse` | `postgresql+psycopg://steerhouse:<postgres_password>@steerhouse-postgres:5432/steerhouse` |
| `auth_secret_key` | `steerhouse` | Signs sign-in sessions |
| `credential_encryption_key` | `steerhouse` | Encrypts every stored SSH key, vault password and token (a Fernet key). Without it a backup of the database can't be decrypted |
| `admin_password` | `steerhouse` (first start only) | The first admin's password; change it in Steerhouse afterwards |
| `grafana_db_password` | `steerhouse` (`scripts/steerhouse.sh grafana-role` only) | The password of `grafana_ro`, the read-only role Argus' Grafana logs in as |

The database's TLS certificate and key are in its data folder, `CONFIG_ROOT/steerhouse-postgres/config/tls`
(`server.crt`, `server.key` mode `600`, and `ca.crt`, the certificate Argus checks it against), and are backed up with
it ([installing.md](installing.md#steerhouse)).

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
| Steerhouse web UI (`steerhouse-frontend`) | `honeybeartech/steerhouse-frontend` | `STEERHOUSE_PORT` → 8080 | Web UI and API, behind the reverse proxy's HTTPS (LAN only) |
| Steerhouse API (`steerhouse`) | `honeybeartech/steerhouse-backend` | `STEERHOUSE_METRICS_PORT` → 8002 | Prometheus metrics, only with `METRICS_TOKEN` (for Argus). The API itself (8000) is reached through the web UI; the workers' internal API (8001) is never published |
| Steerhouse workers (`steerhouse-worker`) | `honeybeartech/steerhouse-backend` | none | Run the playbooks; connect out to the machines they manage |
| Steerhouse database (`steerhouse-postgres`) | `postgres` | `STEERHOUSE_POSTGRES_PORT` → 5432 | PostgreSQL, TLS 1.3 only from outside, and only the read-only role `grafana_ro` (for Argus' Grafana) |

Ports are published on every host interface. Exact versions and digests are in [`compose.yaml`](../compose.yaml).

## Health checks and autoheal

Every service has a health check defined in `compose.yaml`, and every service but autoheal itself has the
label `autoheal: "true"`. When Docker reports a container unhealthy, autoheal restarts it (Docker itself only
restarts a container whose process exits). Each health check has a `start_period` long enough for a slow start
after an upgrade (10 minutes; 1 minute for autoheal and the socket proxy), so autoheal doesn't restart a service
in the middle of a database migration or while the Minecraft image downloads its server.

### Dozzle's certificate files

Docker secrets too: `CONFIG_ROOT/dozzle/certs/dozzle_cert.pem` (mode `644`) and `dozzle_key.pem` (mode `600`), both
owned by root, mounted read-only at `/run/secrets/dozzle_cert` and `/run/secrets/dozzle_key`, where `DOZZLE_CERT`
and `DOZZLE_KEY` (set in `compose.yaml`) point Dozzle. The same pair as every agent's in `DOZZLE_REMOTE_AGENT`; never
committed or backed up ([installing.md](installing.md#dozzles-certificate)).

## Volumes and mounts

| Container path | Host source | Service |
| --- | --- | --- |
| `/config` | `CONFIG_ROOT/prowlarr/config` | Prowlarr: database and settings |
| `/config` | `CONFIG_ROOT/qbittorrent/config` | qBittorrent: settings and torrent list |
| `/downloads` | `DOWNLOADS_PATH` | qBittorrent: downloads (read-write; never backed up) |
| `/incomplete` | `INCOMPLETE_PATH` | qBittorrent: torrents still downloading (read-write; never backed up) |
| `/config` | `CONFIG_ROOT/heimdall/config` | Heimdall: database and settings |
| `/data` | `CONFIG_ROOT/minecraft/config` | Minecraft server: worlds, `server.properties`, allowlist and permissions |
| `/data` | `CONFIG_ROOT/dozzle/config` | Dozzle: settings saved in its UI |
| `/data` | `CONFIG_ROOT/steerhouse/config` | Steerhouse's API: playbooks, run logs and artifacts, Galaxy roles and collections, git checkouts |
| `/galaxy` | `CONFIG_ROOT/steerhouse/config/galaxy`, read-only | Steerhouse's workers: the API's Galaxy roles and collections |
| `/var/lib/postgresql` | `CONFIG_ROOT/steerhouse-postgres/config` | Steerhouse's database (`18/docker`) and its TLS certificate and key (`tls/`) |
| `/run/secrets/<name>` | `CONFIG_ROOT/steerhouse/secrets/<name>`, read-only | Steerhouse's database and API: their secrets ([above](#steerhouses-secret-files)); never backed up |
| `/run/secrets/dozzle_cert`, `/run/secrets/dozzle_key` | `CONFIG_ROOT/dozzle/certs/dozzle_cert.pem` and `dozzle_key.pem`, read-only | Dozzle: the certificate and key it shares with its agents ([above](#dozzles-certificate-files)); never backed up |
| `/var/run/docker.sock` | the Docker socket, read-only | Dozzle (allowed by label) and the socket proxy (allowed by label) |

The socket proxy and autoheal share the internal network `docker-proxy`, which has no route out and nothing
published; autoheal also joins the default network, to reach its webhook. Steerhouse has networks of its own:
`steerhouse-web` (web UI and API), `steerhouse-db` (internal, with the fixed range `STEERHOUSE_DB_SUBNET`: API and
database), `steerhouse-workers` (workers and the API's internal port; not internal, playbooks reach the LAN) and
`steerhouse-postgres-lan` (the database alone, for its published port).

## Labels

| Label | Meaning |
| --- | --- |
| `autoheal` | `"true"` on every service autoheal may restart when its health check fails (every service but autoheal). |
| `org.honeybeartech.hyperion.allow.<rule>` | Lets one service break one policy rule; the value is the reason, and must not be empty. Rules: `image`, `digest`, `latest`, `build`, `privileged`, `no-new-privileges`, `cap-drop`, `cap-add`, `host-network`, `host-pid`, `docker-socket`, `devices`, `healthcheck` ([security.md](security.md#policy)). In use: `docker-socket` for Dozzle and the socket proxy, `latest` for autoheal (its maintained image is only published as `latest`, pinned by digest), `cap-add` for Steerhouse's worker (`NET_ADMIN`, for its egress filter; the owner agreed on 2026-10-22). |
| `org.honeybeartech.hyperion.backup.skip` | Container paths (comma-separated, exact) that `scripts/backup.sh` never archives and `scripts/restore.sh` refuses to write, even if a backup lists them. In use: qBittorrent's `/downloads` and `/incomplete`. |
| `org.honeybeartech.hyperion.backup.exclude` | Paths inside a service's data mounts (comma-separated, exact container paths, at any depth) that `scripts/backup.sh` leaves out of the mount's archive and `scripts/restore.sh` leaves in place. A path that isn't inside one of the service's data mounts, or contains `..` or a pattern character (`*?[\`), makes both fail before anything stops. Not in use. |

## Commands

| Command | Does |
| --- | --- |
| `docker compose up -d` / `down` / `ps` / `logs <service>` | Runs and inspects the stack |
| `make check` | `docker compose config --format json \| python scripts/check_compose.py`: the policy check |
| `python scripts/check_compose.py [FILE] [--sbom OUT]` | Checks a resolved Compose config (from `FILE` or stdin); `--sbom` also writes a CycloneDX 1.6 SBOM of the images. Exit 0 = no violations, 1 = violations (one line each), 2 = unreadable input |
| `make test`, `make lint` | The checker's tests and the linters |
| `scripts/backup.sh [DIR]` | Archives every service's data mounts (every read-write volume or bind mount except the Docker socket, anonymous volumes and the paths in the service's `backup.skip` label: the downloads directory; a mount inside another mount is archived on its own and left out of the outer archive), `.env` and any `<service>.env` into `DIR` (default `backups/<date>-<time>`, gitignored) with a `MANIFEST`, `NETWORKS` (the address range of each network the stack uses but doesn't create; this stack has none, so only the header), `VERSION` (the checkout's `git describe`) and `SHA256SUMS`, all mode `600`. Each service is stopped only while its own mounts are copied and started again (with any service Compose stopped along with it) before the copies are compressed (with `pigz` when it's installed, else `gzip`). Leaves out the paths a service's `org.honeybeartech.hyperion.backup.exclude` label lists. If the pull agent keeps state for this stack (`${HOMELAB_PULL_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/homelab-pull}/hyperion`), first takes its `lock` with `flock` (waiting up to 30 minutes for a deploy to finish) and holds it until it exits. If stopping a service fails while its container is still on its way down (a process stuck writing to a network share can outlast Docker's stop), it waits up to `BACKUP_STOP_WAIT` seconds (default 120) for the container to exit and carries on; if it still runs then, the backup fails, and the services are started again only after a second wait. Fails, naming them, if any service that was running when it began isn't running again at the end. Exit 0 = backup complete |
| `scripts/scheduled-backup.sh` | Runs `scripts/backup.sh` into `BACKUP_DIR/<date>-<time>`, copies it to `BACKUP_REMOTE` with rsync (`SHA256SUMS` last; with `BACKUP_AGE_RECIPIENT`, only the encrypted `backup.tar.age` and its `SHA256SUMS`), deletes all but the newest `BACKUP_REMOTE_KEEP` there and `BACKUP_KEEP` here, and reports to `BACKUP_PING_URL` ([`backup.env`](#backupenv)). Run nightly at 04:30 by the systemd user units in `deploy/systemd/` |
| `scripts/restore.sh [--yes] DIR [SERVICE...]` | Verifies `DIR/SHA256SUMS`, checks the `MANIFEST`, creates missing containers, asks for confirmation (unless `--yes`), stops the services, recreates a service's container if it predates `compose.yaml`, replaces the contents of each listed mount with its archive (owners and modes kept), and starts what was running. Each archive goes to what the service mounts at that container path now, whatever the `MANIFEST` names as its source (so a backup of the old data directories or of Dozzle's old volume restores into the folders under `CONFIG_ROOT`), and a missing folder is created. Writes only mounts the service still has read-write; never the Docker socket, a path in the service's `backup.skip` label, another mount inside the one it restores, or a path in its `backup.exclude` label. A service that bind-mounts a folder inside a mount it restores (Steerhouse's worker: the API's Galaxy folder) is stopped and started again with it, so it doesn't keep the replaced folder. Holds the pull agent's lock as `scripts/backup.sh` does. An encrypted copy is decrypted first ([rebuilding.md](rebuilding.md#opening-an-encrypted-copy)) |
| `scripts/steerhouse.sh secrets DIR` / `env FILE` / `ca DIR` / `request DIR` / `sign CA_DIR CSR CRT NAME...` / `grafana-role` | Writes Steerhouse's secret files, `steerhouse.env`, a CA, the database's key and signing request (on the host), or the certificate signed for it (on the CA's machine; never replacing a file), or creates the read-only role `grafana_ro` in the running stack (again: sets its password to `grafana_db_password`) ([installing.md](installing.md#steerhouse)) |
| `make smoke` | `scripts/smoke-test.sh`: starts every service under a separate Compose project with throwaway directories and app folders under a throwaway `CONFIG_ROOT` (owned by `PUID`:`PGID` with mode 0755, as on the host; Dozzle's created by Docker, owned by root) and no published ports, waits until all are healthy, round-trips a backup and restore over every data mount, checks that an app's data restores through a container made from older settings into its folder under `CONFIG_ROOT`, removed beforehand, with its owner and mode, that excluded mounts and paths were neither archived nor overwritten and that the backup has `NETWORKS` and `VERSION`, runs the scheduled backup against a stand-in backup server and checks the copy and the pruning (and, when `age` is installed, the encrypted copy: only the archive and its checksums leave, the right key opens it, another key doesn't), checks that autoheal restarts a container that turns unhealthy, then removes what it created. Its stack-specific steps are in `scripts/smoke-stack.sh`: Steerhouse's throwaway secrets and certificate, made with `scripts/steerhouse.sh`, and checks, before and after the restore, that `grafana_ro` reads the `analytics` views over TLS and nothing else, that connections without TLS and every other login from outside `steerhouse-db` are refused, that `/metrics` needs `METRICS_TOKEN`, and that the worker is ready and sees the API's Galaxy folder. Exit 0 = all healthy and restored |

## Outbound connections

From the host: the image registries (GitHub Container Registry, Docker Hub, linuxserver.io's `lscr.io`) on
`docker compose pull`. From the services: Prowlarr to the indexers it is configured with, and to the media apps'
APIs; qBittorrent to BitTorrent trackers, peers and the DHT; the Minecraft server image downloads the pinned
Bedrock Dedicated Server from Minecraft's website on start; Heimdall to the apps it shows live stats for, if
configured; Prowlarr and qBittorrent may check for updates (which this stack doesn't apply). Dozzle to the local Docker
API and to the Dozzle agents named in `DOZZLE_REMOTE_AGENT`; autoheal only to the socket proxy. Steerhouse's workers to
the machines its playbooks manage (SSH) and whatever the playbooks fetch (never the API's own address or cloud
metadata: the worker's egress filter); its API to Ansible Galaxy, the git repositories and the single sign-on, mail
and notification services it is configured with. Into the stack from Argus (another host): Prometheus scrapes
`STEERHOUSE_METRICS_PORT`, Grafana reads `STEERHOUSE_POSTGRES_PORT` as `grafana_ro`.

The scheduled backup talks to `BACKUP_REMOTE` (rsync, usually over SSH) and `BACKUP_PING_URL`, if they are set.

## Release files

Each GitHub Release has `homelab-hyperion-<version>.tar.gz` (source, with `LICENSE`),
`homelab-hyperion-<version>.cdx.json` (CycloneDX SBOM of the pinned images), `SHA256SUMS` and its Sigstore
bundle, and SLSA provenance ([verifying-releases.md](verifying-releases.md)).
