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
- **Steerhouse**: runs Ansible playbooks from a web UI (API, workers, web UI and its PostgreSQL), with its metrics
  and read-only `analytics` views published for the homelab's Grafana and Prometheus (the database over TLS only)
- **autoheal**, behind a **socket proxy**: restarts any container whose health check fails

Every service has a health check, and every image is pinned by tag **and** digest, for `linux/amd64`. The
Minecraft server's own version is pinned in `compose.yaml` too, never `LATEST`. New versions arrive as Dependabot
pull requests that CI checks before they're merged. The maintainer's server follows `main`: a pull agent there
applies each merge within a couple of minutes ([upgrading](docs/upgrading.md#following-main)). Nothing updates from a
registry tag by itself: what runs is always a commit in `main`.

## Getting started

On a Docker host ([requirements](docs/installing.md#requirements)):

```sh
git clone https://github.com/HoneyBearTech/homelab-hyperion.git && cd homelab-hyperion
cp .env.example .env && chmod 600 .env   # then set TZ, PUID/PGID, the paths, Minecraft's and Steerhouse's settings
. ./.env && mkdir -p "$DOWNLOADS_PATH" "$INCOMPLETE_PATH"
for app in prowlarr qbittorrent heimdall minecraft steerhouse steerhouse-postgres; do
  mkdir -p "$CONFIG_ROOT/$app/config"
done
# Steerhouse's secrets, tokens and database certificate first: docs/installing.md#steerhouse
docker compose up -d --wait
```

The full steps are in the [quick start](docs/quick-start.md).

## Usage

```sh
docker compose ps                 # what's running
docker compose logs -f <service>  # one service's log (or use Dozzle)
make check                        # policy check: every image pinned, nothing privileged
scripts/backup.sh                 # back up every service's data (stops each briefly), never the downloads
```

Upgrading to a new release, or following `main` the way the maintainer's server does:
[docs/upgrading.md](docs/upgrading.md).

## Configuration

Settings come from `.env` (template [`.env.example`](.env.example)), which holds no secrets. autoheal's optional
restart webhook goes in the gitignored `autoheal.env` (template [`autoheal.env.example`](autoheal.env.example));
without it, restarts are only logged. Steerhouse's tokens go in the gitignored `steerhouse.env` (template
[`steerhouse.env.example`](steerhouse.env.example)) and its other secrets in files under
`CONFIG_ROOT/steerhouse/secrets`, which `scripts/steerhouse.sh` writes ([installing](docs/installing.md#steerhouse)).

| Setting | Default in `.env.example` | Meaning |
| --- | --- | --- |
| `TZ` | `Etc/UTC` | Time zone |
| `PUID`, `PGID` | `1000` | User and group Prowlarr, qBittorrent, Heimdall, the Minecraft server and Steerhouse's API and database run as; must own those apps' folders under `CONFIG_ROOT` and be able to write the downloads and incomplete directories |
| `CONFIG_ROOT` | `/srv/config` | Each app's folder, `<app>/config`: its settings and database (Minecraft's worlds), and Steerhouse's secrets (`steerhouse/secrets`, never backed up). Holds every login: back it up. Never a path inside `/var/lib/docker/volumes` ([why](docs/installing.md#where-data-lives)) |
| `DOWNLOADS_PATH` | `/srv/downloads` | Where qBittorrent saves downloads (never backed up by this stack) |
| `INCOMPLETE_PATH` | `/srv/incomplete` | Where qBittorrent keeps torrents still downloading, at `/incomplete` (never backed up) |
| `DOZZLE_REMOTE_AGENT` | *(empty)* | Dozzle agents on other hosts (`host:port`, comma-separated) whose logs Dozzle also shows |
| `MINECRAFT_LEVEL_NAME` | `Bedrock level` | The world the server opens: its folder under `worlds/` |
| `MINECRAFT_ADDRESS` | `192.0.2.10` | The address players reach this host at, handed to them with their gameplay port |
| `MINECRAFT_EULA` | *(empty)* | Set to `TRUE` to accept the [Minecraft EULA](https://www.minecraft.net/eula); the server won't start otherwise |
| `STEERHOUSE_PORT` | `8085` | Host port of Steerhouse's web UI, behind the reverse proxy's HTTPS |
| `STEERHOUSE_PUBLIC_URL` | `https://steerhouse.example.com` | The address people open Steerhouse at |
| `STEERHOUSE_TRUSTED_PROXIES` | `192.0.2.20` | The reverse proxy's address, the only one whose `X-Forwarded-For` Steerhouse believes |
| `STEERHOUSE_METRICS_PORT` | `8002` | Host port of Steerhouse's metrics (token-protected), for Argus |
| `STEERHOUSE_POSTGRES_PORT` | `5432` | Host port of Steerhouse's database: TLS only, read-only role `grafana_ro` only, for Argus' Grafana |
| `STEERHOUSE_DB_SUBNET` | `172.16.90.0/28` | Address range of Steerhouse's internal database network, the only place its own database user may connect from |

Ports, volumes and labels: [docs/interfaces.md](docs/interfaces.md).

## Running it securely

- Keep the web UIs (Prowlarr, qBittorrent, Heimdall, Dozzle) on your LAN, behind a reverse proxy with access
  lists, and turn on the logins they offer. Docker-published ports bypass host firewalls such as `ufw`.
- Dozzle can read every container's logs through the Docker socket, and those of every host whose Dozzle agent
  it connects to, and logs can hold secrets. It mounts the
  socket read-only, but that doesn't limit the API: treat its web UI as admin access to the host.
- autoheal reaches Docker only through the socket proxy, which lets it list, inspect, restart and stop
  containers and nothing else.
- qBittorrent's peers see your public IP address. Whether to route it through a VPN is your call; this stack
  doesn't include one.
- The Minecraft server's allowlist is on: only the players in its `allowlist.json` can join. Only forward its
  ports (TCP 19132, UDP 19140–19149) to the internet if you mean to host players from outside your LAN.
- Secrets (logins, indexer API keys, webhook URLs) live only in each service's data or its own gitignored
  `<service>.env`, never in this repository or `.env`. Backups contain them: keep them private and off the host.
- Don't run an auto-updater such as Watchtower on these containers; upgrade from this repository instead (a
  release, or `main`).
- Every service drops every Linux capability, adds back only the ones its image needs, and can't gain new
  privileges; where its image allows it, its root filesystem is read-only. The policy check refuses privileged containers, capabilities beyond Docker's defaults, host
  networking, device mappings and Docker socket mounts unless a service documents why
  ([docs/security.md](docs/security.md)).

Report vulnerabilities privately: [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
