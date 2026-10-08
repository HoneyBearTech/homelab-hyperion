# Installing

The [quick start](quick-start.md) is the short version of this page.

> **Planned:** `compose.yaml` isn't in the repository yet. The requirements and security advice apply now; the
> install steps apply once the stack is added.

## Requirements

- Linux with Docker Engine and the Compose v2 plugin (Docker Engine 25 or later and Compose 2.24 or later, for
  the health checks' `start_interval`). The reference host is **Ubuntu 24.04 on amd64**; every image is chosen
  to publish `linux/amd64`. No GPU is needed.
- A user in the `docker` group to run `docker compose`. Membership is equivalent to root on the host, so keep
  that group small.
- A downloads directory (local disk or a network share) writable by `PUID`/`PGID`. If the media apps that
  import from it run on another machine, it must be storage that machine sees too.
- Free host ports: 80 and 443 (Heimdall), 4040 (Dozzle), 6881 TCP and UDP (qBittorrent), 8090 (qBittorrent's
  web UI), 9696 (Prowlarr) and 19132 UDP (Minecraft).
- Acceptance of the [Minecraft EULA](https://www.minecraft.net/eula), which the Bedrock Dedicated Server requires.

## Where data lives

| What | Where on the host | In the container |
| --- | --- | --- |
| Prowlarr's database and settings | `PROWLARR_CONFIG_PATH` | `/config` |
| qBittorrent's settings and torrent list | `QBITTORRENT_CONFIG_PATH` | `/config` |
| qBittorrent's downloads | `DOWNLOADS_PATH` | `/downloads` |
| Heimdall's database and settings | `HEIMDALL_CONFIG_PATH` | `/config` |
| The Minecraft server's worlds and settings | `MINECRAFT_DATA_PATH` | `/data` |

These are **Planned** paths ([interfaces.md](interfaces.md#volumes-and-mounts)). Dozzle, autoheal and the socket
proxy keep no data.

## Installing

1. Clone the repository (or download a release's source archive and verify it,
   [verifying-releases.md](verifying-releases.md)).
2. Create `.env` from `.env.example` (mode `600`) and set every value, including `MINECRAFT_EULA=TRUE`.
3. Create the data directories, then `docker compose up -d`.

**Adopting existing containers.** If the services already run on the host (from Portainer stacks or another
Compose project), point the stack at their existing data instead of starting empty: stop the old containers,
set each path in `.env` to where its data already is, and keep the same published ports and the **same
container path for the downloads**: qBittorrent records every torrent's save path, and the media apps map that
path to their own view of the files, so a different mount point breaks both. Take a backup of the old data
first. Run the same Minecraft server version as before (or newer): a world opened by a newer server can't go
back to an older one.

Running `main` instead of a release is possible but unsupported for anything you depend on.

## Running it securely

- **Web UIs on the LAN only.** Don't publish Prowlarr's, qBittorrent's, Heimdall's or Dozzle's ports beyond the
  LAN; Docker-published ports bypass host firewalls such as `ufw`, so restrict them at the router or with Docker's
  own `DOCKER-USER` rules, and use a reverse proxy's access lists for names you give them.
- **Turn on every login a service offers**, with long, unique passwords: Prowlarr and qBittorrent require one;
  Heimdall and Dozzle can have one.
- **Treat Dozzle as admin access.** It reads every container's logs through the Docker socket, and every
  connected host's through its Dozzle agent; keep those agents' ports on the LAN too. The socket is
  mounted read-only, which protects the socket file, not the API behind it.
- **autoheal only through the socket proxy**, which allows listing, inspecting and restarting containers and
  nothing else, on a network with no published ports.
- **qBittorrent is on the public internet** by design: peers see your public IP address. Forward only its
  listening port, never its web UI. Whether to route it through a VPN is your decision; this stack has none.
- **Minecraft from outside the LAN** means forwarding UDP 19132. Do it only if you mean to, and keep the server's
  allowlist on so only the players you name can join.
- Keep `.env` at mode `600`; it holds no secrets by design, but it describes your host.
- Back up the services' data directories ([upgrading.md](upgrading.md#backing-up)).
- Don't add services that mount the Docker socket, run privileged or use the host network without a documented
  reason; the policy check refuses them ([security.md](security.md)).
- Don't run an auto-updater (such as Watchtower) on these containers: it would replace the pinned, reviewed
  versions with whatever a tag points to today.

## Uninstalling

```sh
docker compose down          # stops and removes the containers and the stack's networks
```

The data directories and the downloads are left untouched. Remove the data directories by hand if you no
longer want the services' data.
