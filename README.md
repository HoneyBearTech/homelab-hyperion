# homelab-hyperion

[![CI](https://github.com/HoneyBearTech/homelab-hyperion/actions/workflows/ci.yml/badge.svg)](https://github.com/HoneyBearTech/homelab-hyperion/actions/workflows/ci.yml)
[![CodeQL](https://github.com/HoneyBearTech/homelab-hyperion/actions/workflows/codeql.yml/badge.svg)](https://github.com/HoneyBearTech/homelab-hyperion/actions/workflows/codeql.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/HoneyBearTech/homelab-hyperion/badge)](https://scorecard.dev/viewer/?uri=github.com/HoneyBearTech/homelab-hyperion)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/15292/badge)](https://www.bestpractices.dev/projects/15292)
[![OpenSSF Baseline](https://www.bestpractices.dev/projects/15292/baseline)](https://www.bestpractices.dev/projects/15292)

Docker Compose stack for Hyperion, a homelab Ubuntu server (24.04, amd64). Version-pinned, self-hosted services, kept as code for easy upgrades and rebuilds.

> [!WARNING]
> Three of these services reach far beyond their own data. Dozzle reads the Docker API, which controls every
> container on the host; Steerhouse holds the SSH keys of the machines it manages; and qBittorrent shares files with
> the public BitTorrent network, which shows peers your public IP address. Keep every web UI on your LAN, and back up
> the services' data before every upgrade ([docs/upgrading.md](docs/upgrading.md)).

## Documentation

- [Quick start](docs/quick-start.md): getting the stack running on a fresh Docker host
- [Installing](docs/installing.md): host preparation, where data lives, running it securely, uninstalling
- [Upgrading](docs/upgrading.md): moving to a new release or following `main`, backup and restore, rolling back
- [Rebuilding](docs/rebuilding.md): a new or wiped host, from a backup
- [Architecture](docs/architecture.md): the services, actors, data flow and how updates reach the host
- [Interfaces](docs/interfaces.md): every setting, port, volume, label and command
- [Verifying releases](docs/verifying-releases.md): checking signatures, checksums, provenance and the SBOM
- [Security requirements](docs/security.md): what the stack protects, what it doesn't, where secrets live
- [Assurance case](docs/assurance-case.md): threat model, trust boundaries, secure design, common weaknesses
- [Dependencies](docs/dependencies.md): how images and tools are chosen, pinned, tracked and patched
- [Roadmap](docs/roadmap.md): the next year, and what homelab-hyperion will not do
- Project policies: [CONTRIBUTING](CONTRIBUTING.md) · [SECURITY](SECURITY.md) · [GOVERNANCE](GOVERNANCE.md) ·
  [SUPPORT](SUPPORT.md) · [CODE OF CONDUCT](CODE_OF_CONDUCT.md) · [CHANGELOG](CHANGELOG.md)

## What's in the stack

[`compose.yaml`](compose.yaml) runs ([architecture](docs/architecture.md), ports in
[interfaces](docs/interfaces.md#services-and-ports)):

- **Prowlarr**: manages indexers for Sonarr, Radarr and Lidarr, which run elsewhere
- **qBittorrent**: the BitTorrent client those apps send downloads to
- **Heimdall**: a start page linking the homelab's web UIs
- **Dozzle**: a live view of the containers' logs in the browser, for this host and, through Dozzle agents,
  the homelab's other hosts
- **Minecraft Bedrock server**: a Bedrock Dedicated Server for the household, in the `itzg/minecraft-bedrock-server`
  wrapper image
- **Steerhouse**: runs Ansible playbooks from a web UI (API, workers and web UI; its database on a PostgreSQL
  server), with its metrics published for the homelab's Prometheus
- **autoheal**, behind a **socket proxy**: restarts any container whose health check fails

Every service has a health check, and every image is pinned by tag **and** digest, for `linux/amd64`. The
Minecraft server's own version is pinned in `compose.yaml` too, never `LATEST`. New versions arrive as Dependabot
pull requests that CI checks before they're merged. The maintainer's server follows `main`: a pull agent there
applies each merge within a couple of minutes ([upgrading](docs/upgrading.md#following-main)). Nothing updates from a
registry tag by itself: what runs is always a commit in `main`.

## Getting started

Follow the [quick start](docs/quick-start.md) on a prepared Docker host
([requirements](docs/installing.md#requirements)). Before the first start, configure the required settings,
create the app and download folders with the right ownership, provision Steerhouse's external PostgreSQL database
and secret files/tokens, and configure its HTTPS reverse proxy ([Steerhouse setup](docs/installing.md#steerhouse)).
Install Dozzle's root-owned certificate and key even if no remote agents are configured
([certificate setup](docs/installing.md#dozzles-certificate)).

`.env` is Compose configuration data, not a shell script: do not source it.

## Repository layout

| Path | Purpose |
| --- | --- |
| [`compose.yaml`](compose.yaml) | Services, ports, mounts, health checks and hardening |
| [`.env.example`](.env.example), [`autoheal.env.example`](autoheal.env.example), [`backup.env.example`](backup.env.example), [`steerhouse.env.example`](steerhouse.env.example) | Settings and secret-variable inventories; supply values locally |
| [`scripts/`](scripts/) | Policy checking, backup, restore, setup helpers and isolated smoke checks |
| [`deploy/systemd/`](deploy/systemd/) | Scheduled backup user service and timer |
| [`tests/`](tests/) | Policy, backup stop handling, deploy locking and settings-parsing tests |
| [`docs/`](docs/) | Setup, architecture, interfaces, operations and security documentation |
| [`Makefile`](Makefile) | Development checks and smoke-test entry points |
| [`requirements-dev.in`](requirements-dev.in), [`requirements-dev.txt`](requirements-dev.txt) | Development tool inventory and pinned, hashed requirements |

## Usage

```sh
docker compose ps                 # what's running
docker compose logs -f <service>  # one service's log (or use Dozzle)
make check                        # policy check; needs Docker/Compose, configured settings and development tools
scripts/backup.sh                 # back up every service's data (stops each briefly), never downloads or incomplete storage
```

Use `docker compose ps` and service logs to inspect health after changes. Configure
[scheduled backups](docs/installing.md#scheduled-backups) with the supplied user service and timer, keep copies
off the host, and take a fresh backup before an [upgrade](docs/upgrading.md). For recovery, follow the
[restore and rollback steps](docs/upgrading.md#rolling-back) or [rebuild guide](docs/rebuilding.md).
`make check` creates a local development venv from the pinned requirements and also needs Docker Engine,
Compose and configured settings; see [commands](docs/interfaces.md#commands).

## Configuration

Settings come from `.env` (template [`.env.example`](.env.example)), which holds no secrets. autoheal's optional
restart webhook goes in the gitignored `autoheal.env` (template [`autoheal.env.example`](autoheal.env.example));
without it, restarts are only logged. Steerhouse's tokens go in the gitignored `steerhouse.env` (template
[`steerhouse.env.example`](steerhouse.env.example)) and its other secrets in files under
`CONFIG_ROOT/steerhouse/secrets`, which `scripts/steerhouse.sh` writes ([installing](docs/installing.md#steerhouse)).

| Setting | Required | Meaning |
| --- | --- | --- |
| `TZ` | yes | Time zone |
| `PUID`, `PGID` | yes | User and group Prowlarr, qBittorrent, Heimdall, the Minecraft server and Steerhouse's API run as; must own those apps' folders under `CONFIG_ROOT` and be able to write the downloads and incomplete directories |
| `CONFIG_ROOT` | yes | Each app's folder, `<app>/config`: its settings and database (Minecraft's worlds), and Steerhouse's secrets (`steerhouse/secrets`, never backed up). Holds every login: back it up. Never a path inside `/var/lib/docker/volumes` ([why](docs/installing.md#where-data-lives)) |
| `DOWNLOADS_PATH` | yes | Where qBittorrent saves downloads (never backed up by this stack) |
| `INCOMPLETE_PATH` | yes | Where qBittorrent keeps torrents still downloading, at `/incomplete` (never backed up) |
| `DOZZLE_REMOTE_AGENT` | no | Dozzle agents on other hosts (`host:port`, comma-separated) whose logs Dozzle also shows |
| `MINECRAFT_LEVEL_NAME` | yes | The world the server opens: its folder under `worlds/` |
| `MINECRAFT_ADDRESS` | yes | The address players reach this host at, handed to them with their gameplay port |
| `MINECRAFT_EULA` | yes | Set to `TRUE` to accept the [Minecraft EULA](https://www.minecraft.net/eula); the server won't start otherwise |
| `STEERHOUSE_PORT` | yes | Host port of Steerhouse's web UI, behind the reverse proxy's HTTPS |
| `STEERHOUSE_PUBLIC_URL` | yes | The address people open Steerhouse at |
| `STEERHOUSE_TRUSTED_PROXIES` | yes | The reverse proxy's address, the only one whose `X-Forwarded-For` Steerhouse believes |
| `STEERHOUSE_METRICS_PORT` | yes | Host port of Steerhouse's metrics (token-protected), for the monitoring system |

Optional backup configuration is in [`backup.env.example`](backup.env.example): `BACKUP_DIR`, `BACKUP_KEEP`,
`BACKUP_REMOTE`, `BACKUP_REMOTE_KEEP`, `BACKUP_PING_URL` and `BACKUP_AGE_RECIPIENT`. autoheal's optional
`WEBHOOK_URL` and Steerhouse's required `WORKER_TOKEN` and optional `METRICS_TOKEN` are described in the
[settings reference](docs/interfaces.md#settings), along with the four secret-file names and recovery requirements.

Ports, volumes and labels: [docs/interfaces.md](docs/interfaces.md).

## Running it securely

- Keep the web UIs (Prowlarr, qBittorrent, Heimdall, Dozzle) on your LAN, behind a reverse proxy with access
  lists, and turn on the logins they offer. Docker-published ports bypass host firewalls such as `ufw`.
- Dozzle can read every container's logs through the Docker socket, and those of every host whose Dozzle agent
  it connects to, and logs can hold secrets. It mounts the
  socket read-only, but that doesn't limit the API: treat its web UI as admin access to the host. It and its agents
  authenticate each other with a certificate and key of your own, never the pair built into every Dozzle image
  ([docs/installing.md](docs/installing.md#dozzles-certificate)): keep the key secret.
- autoheal reaches Docker only through the socket proxy, which lets it list, inspect, restart and stop
  containers and nothing else.
- qBittorrent's peers see your public IP address. Whether to route it through a VPN is your call; this stack
  doesn't include one.
- The Minecraft server's allowlist is on: only the players in its `allowlist.json` can join. Only forward its
  ports (TCP 19132, UDP 19140–19149) to the internet if you mean to host players from outside your LAN.
- Secrets (logins, indexer API keys, webhook URLs) live only in each service's data or its own gitignored
  `<service>.env`, never in this repository or `.env`. Backups contain them: keep them private and off the host, and
  encrypt the copy that leaves it (`BACKUP_AGE_RECIPIENT`).
- Don't run an auto-updater such as Watchtower on these containers; upgrade from this repository instead (a
  release, or `main`).
- Every service drops every Linux capability, adds back only the ones its image needs, and can't gain new
  privileges; where its image allows it, its root filesystem is read-only. The policy check refuses privileged containers, capabilities beyond Docker's defaults, host
  networking, device mappings and Docker socket mounts unless a service documents why
  ([docs/security.md](docs/security.md)).

Report vulnerabilities privately: [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
