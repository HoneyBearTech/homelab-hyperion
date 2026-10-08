# homelab-hyperion

[![CI](https://github.com/HoneyBearTech/homelab-hyperion/actions/workflows/ci.yml/badge.svg)](https://github.com/HoneyBearTech/homelab-hyperion/actions/workflows/ci.yml)
[![CodeQL](https://github.com/HoneyBearTech/homelab-hyperion/actions/workflows/codeql.yml/badge.svg)](https://github.com/HoneyBearTech/homelab-hyperion/actions/workflows/codeql.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/HoneyBearTech/homelab-hyperion/badge)](https://scorecard.dev/viewer/?uri=github.com/HoneyBearTech/homelab-hyperion)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/15292/badge)](https://www.bestpractices.dev/projects/15292)
[![OpenSSF Baseline](https://www.bestpractices.dev/projects/15292/baseline)](https://www.bestpractices.dev/projects/15292)

Docker Compose stack for Hyperion, a homelab Ubuntu server (24.04, amd64). Version-pinned, self-hosted services, kept as code for easy upgrades and rebuilds.

> [!WARNING]
> Two of these services reach far beyond their own data. Dozzle reads the Docker API, which controls every
> container on the host, and qBittorrent shares files with the public BitTorrent network, which shows peers your
> public IP address. Keep every web UI on your LAN, and back up the services' data before every upgrade
> ([docs/upgrading.md](docs/upgrading.md)).

> [!NOTE]
> **Planned:** the stack itself (`compose.yaml`) isn't in the repository yet. The documentation describes what
> it will be; everything not built yet is marked **Planned**.

## Documentation

- [Quick start](docs/quick-start.md): getting the stack running on a fresh Docker host
- [Installing](docs/installing.md): host preparation, where data lives, running it securely, uninstalling
- [Upgrading](docs/upgrading.md): moving to a new release, backup and restore, rolling back
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

**Planned** ([architecture](docs/architecture.md), ports in [interfaces](docs/interfaces.md#services-and-ports)):

- **Prowlarr**: manages indexers for Sonarr, Radarr and Lidarr, which run elsewhere
- **qBittorrent**: the BitTorrent client those apps send downloads to
- **Heimdall**: a start page linking the homelab's web UIs
- **Dozzle**: a live view of the containers' logs in the browser, for this host and, through Dozzle agents,
  the homelab's other hosts
- **Minecraft Bedrock server**: a Bedrock Dedicated Server for the household, in the `itzg/minecraft-bedrock-server`
  wrapper image
- **autoheal**, behind a **socket proxy**: restarts any container whose health check fails

Every service will have a health check, and every image will be pinned by tag **and** digest, for
`linux/amd64`. The Minecraft server's own version is pinned in `compose.yaml` too, never `LATEST`. New versions arrive as Dependabot pull
requests that CI checks and the maintainer merges; nothing on the host updates itself.

## Getting started

**Planned**, once `compose.yaml` exists:

```sh
git clone https://github.com/HoneyBearTech/homelab-hyperion.git && cd homelab-hyperion
cp .env.example .env && chmod 600 .env              # then set TZ, PUID/PGID, the paths and the Minecraft settings
. ./.env && mkdir -p "$PROWLARR_CONFIG_PATH" "$QBITTORRENT_CONFIG_PATH" "$DOWNLOADS_PATH" \
  "$HEIMDALL_CONFIG_PATH" "$MINECRAFT_DATA_PATH"
docker compose up -d --wait
```

The full steps are in the [quick start](docs/quick-start.md).

## Usage

```sh
docker compose ps                 # what's running
docker compose logs -f <service>  # one service's log (or use Dozzle)
make check                        # policy check: every image pinned, nothing privileged
scripts/backup.sh                 # back up every service's data, never the downloads
```

Upgrading to a new release: [docs/upgrading.md](docs/upgrading.md).

## Configuration

Settings come from `.env` (template [`.env.example`](.env.example)), which holds no secrets. **Planned**: the
list is settled when the stack is added.

| Setting | Default in `.env.example` | Meaning |
| --- | --- | --- |
| `TZ` | `Etc/UTC` | Time zone |
| `PUID`, `PGID` | `1000` | User and group the linuxserver.io services run as; must be able to write the downloads directory |
| `PROWLARR_CONFIG_PATH` | `/srv/appdata/prowlarr` | Prowlarr's database and settings |
| `QBITTORRENT_CONFIG_PATH` | `/srv/appdata/qbittorrent` | qBittorrent's settings and torrent list |
| `DOWNLOADS_PATH` | `/srv/downloads` | Where qBittorrent saves downloads (never backed up by this stack) |
| `HEIMDALL_CONFIG_PATH` | `/srv/appdata/heimdall` | Heimdall's database and settings |
| `DOZZLE_REMOTE_AGENT` | *(empty)* | Dozzle agents on other hosts (`host:port`, comma-separated) whose logs Dozzle also shows |
| `MINECRAFT_DATA_PATH` | `/srv/appdata/minecraft-bedrock` | The Minecraft server's worlds and settings |
| `MINECRAFT_EULA` | *(empty)* | Set to `TRUE` to accept the [Minecraft EULA](https://www.minecraft.net/eula); the server won't start otherwise |

Ports, volumes and labels: [docs/interfaces.md](docs/interfaces.md).

## Running it securely

- Keep the web UIs (Prowlarr, qBittorrent, Heimdall, Dozzle) on your LAN, behind a reverse proxy with access
  lists, and turn on the logins they offer. Docker-published ports bypass host firewalls such as `ufw`.
- Dozzle can read every container's logs through the Docker socket, and those of every host whose Dozzle agent
  it connects to, and logs can hold secrets. It mounts the
  socket read-only, but that doesn't limit the API: treat its web UI as admin access to the host.
- autoheal reaches Docker only through the socket proxy, which lets it list, inspect and restart containers
  and nothing else.
- qBittorrent's peers see your public IP address. Whether to route it through a VPN is your call; this stack
  doesn't include one.
- Only forward the Minecraft server's UDP port to the internet if you mean to host players from outside your
  LAN, and keep the server's allowlist on.
- Secrets (logins, indexer API keys, webhook URLs) live only in each service's data or its own gitignored
  `<service>.env`, never in this repository or `.env`. Backups contain them: keep them private and off the host.
- Don't run an auto-updater such as Watchtower on these containers; upgrade by release instead.
- The policy check refuses privileged containers, added capabilities, host networking and Docker socket
  mounts unless a service documents why ([docs/security.md](docs/security.md)).

Report vulnerabilities privately: [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
