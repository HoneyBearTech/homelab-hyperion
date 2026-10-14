# Installing

The [quick start](quick-start.md) is the short version of this page.

## Requirements

- Linux with Docker Engine and the Compose v2 plugin (Docker Engine 25 or later and Compose 2.24 or later, for
  the health checks' `start_interval`). The reference host is **Ubuntu 24.04 on amd64**; every image is chosen
  to publish `linux/amd64`. No GPU is needed.
- A user in the `docker` group to run `docker compose`. Membership is equivalent to root on the host, so keep
  that group small.
- A downloads directory (local disk or a network share) writable by `PUID`/`PGID`. If the media apps that
  import from it run on another machine, it must be storage that machine sees too.
- Free host ports: 80 and 443 (Heimdall), 4040 (Dozzle), 6881 TCP and UDP (qBittorrent), 8090 (qBittorrent's
  web UI), 9696 (Prowlarr), and 19132 TCP and 19140–19149 UDP (Minecraft).
- Acceptance of the [Minecraft EULA](https://www.minecraft.net/eula), which the Bedrock Dedicated Server requires.

## Where data lives

| What | Where on the host | In the container |
| --- | --- | --- |
| Prowlarr's database and settings | `PROWLARR_CONFIG_PATH` | `/config` |
| qBittorrent's settings and torrent list | `QBITTORRENT_CONFIG_PATH` | `/config` |
| qBittorrent's downloads | `DOWNLOADS_PATH` | `/downloads` |
| Heimdall's database and settings | `HEIMDALL_CONFIG_PATH` | `/config` |
| The Minecraft server's worlds and settings | `MINECRAFT_DATA_PATH` | `/data` |

The container paths are fixed in `compose.yaml` ([interfaces.md](interfaces.md#volumes-and-mounts)); the host
paths are yours to choose. Each data directory must be owned by `PUID`:`PGID`. Dozzle, autoheal and the socket
proxy keep no data.

## Installing

1. Clone the repository (or download a release's source archive and verify it,
   [verifying-releases.md](verifying-releases.md)).
2. Create `.env` from `.env.example` (mode `600`) and set every value, including `MINECRAFT_EULA=TRUE`.
   Optionally create `autoheal.env` from `autoheal.env.example` (mode `600`) for restart notices.
3. Create the data directories, then `docker compose up -d --wait`.

**Adopting existing containers.** If the services already run on the host (from Portainer stacks or another
Compose project), point the stack at their existing data instead of starting empty: stop the old containers,
set each path in `.env` to where its data already is, and keep the same published ports and the **same
container path for the downloads**: qBittorrent records every torrent's save path, and the media apps map that
path to their own view of the files, so a different mount point breaks both. Take a backup of the old data
first. Run the same Minecraft server version as before (or newer): a world opened by a newer server can't go
back to an older one. Set `MINECRAFT_LEVEL_NAME` to the existing world's folder name (otherwise the server
starts a new, empty world), make the Minecraft data directory owned by `PUID`:`PGID` (the server runs as that
user, not as root), and check that `allowlist.json` names the players.

The maintainer's server runs `main` rather than a release, and deploys every merge by itself
([upgrading.md](upgrading.md#following-main)). For your own setup, a release is the safer choice.

## Running it securely

- **Web UIs on the LAN only.** Don't publish Prowlarr's, qBittorrent's, Heimdall's or Dozzle's ports beyond the
  LAN; Docker-published ports bypass host firewalls such as `ufw`, so restrict them at the router or with Docker's
  own `DOCKER-USER` rules, and use a reverse proxy's access lists for names you give them.
- **Turn on every login a service offers**, with long, unique passwords: Prowlarr and qBittorrent require one;
  Heimdall and Dozzle can have one.
- **Treat Dozzle as admin access.** It reads every container's logs through the Docker socket, and every
  connected host's through its Dozzle agent; keep those agents' ports on the LAN too. The socket is
  mounted read-only, which protects the socket file, not the API behind it.
- **autoheal only through the socket proxy**, which allows listing, inspecting, restarting and stopping
  containers and nothing else, on a network with no published ports.
- **qBittorrent is on the public internet** by design: peers see your public IP address. Forward only its
  listening port, never its web UI. Whether to route it through a VPN is your decision; this stack has none.
- **Minecraft from outside the LAN** means forwarding TCP 19132 and UDP 19140–19149, and setting
  `MINECRAFT_ADDRESS` to an address those players can reach. Do it only if you mean to; the server's allowlist is
  on, so only the players you name can join.
- Keep `.env` at mode `600`; it holds no secrets by design, but it describes your host. `autoheal.env` holds a
  secret (anyone with the webhook URL can post to the channel): mode `600`, never committed.
- Back up the services' data directories ([upgrading.md](upgrading.md#backing-up)), and schedule a nightly copy
  off the host ([below](#scheduled-backups)).
- Don't add services that mount the Docker socket, run privileged or use the host network without a documented
  reason; the policy check refuses them ([security.md](security.md)).
- Don't run an auto-updater (such as Watchtower) on these containers: it would replace the pinned, reviewed
  versions with whatever a tag points to today.

## Scheduled backups

`scripts/scheduled-backup.sh` takes a backup (`scripts/backup.sh`), copies it to another machine with rsync, keeps
only the newest few in both places and reports to an Uptime Kuma push monitor. A systemd timer runs it nightly.
Every setting is in the optional `backup.env` ([interfaces.md](interfaces.md#backupenv)). The backups hold every
login and token, Prowlarr's indexer credentials among them: copy them only to a machine you trust as much as this
one. The downloads are never part of them.

1. **On the backup server**, create a folder for the backups and a user that can write only there and use rsync
   over SSH (on a Synology: a shared folder, a non-admin user with read/write on that folder only, rsync allowed
   under Application Privileges, SSH on, the rsync service on under File Services, and the user home service on so
   the user can have an `authorized_keys`). Whoever controls this host can delete or overwrite what it copied
   there, so keep older versions where the backup user can't reach them: snapshots of the folder, or a versioned
   copy of it made on the server after the nightly backup (on a Synology without Btrfs, a Hyper Backup task with
   rotation, into a folder the backup user has no access to). A recycle bin isn't enough: Synology's doesn't keep
   files deleted over rsync.
2. **On this host**, as the user who runs the stack, install rsync and curl (and pigz, which compresses the
   archives on every core instead of one), and create a key used only for the backups, with an alias for it in
   `~/.ssh/config`:

   ```sh
   sudo apt install -y rsync curl pigz
   ssh-keygen -t ed25519 -N '' -f ~/.ssh/homelab-hyperion-backup
   ```

   ```text
   Host backup-host
     HostName <the backup server's address>
     User <the backup user>
     IdentityFile ~/.ssh/homelab-hyperion-backup
     IdentitiesOnly yes
   ```

   Add the public key to the backup user's `~/.ssh/authorized_keys` on the server, prefixed with
   `restrict,from="<this host's address>"` (no shell or forwarding, and only from this host), then check that
   `rsync --list-only backup-host:/volume1/<folder>/` works without a password prompt.
3. **Settings**: `cp backup.env.example backup.env && chmod 600 backup.env`, then set
   `BACKUP_REMOTE=backup-host:/volume1/<folder>` and, optionally, the retention and `BACKUP_PING_URL`. For the
   ping, add a monitor of type **Push** in Uptime Kuma with a heartbeat interval of 25 hours, and copy its URL.
4. **Try it**: `scripts/scheduled-backup.sh`. Each service stops only while its own data is copied (seconds for
   this stack's data), and the archives are compressed after it has started again.
5. **Schedule it**, with the systemd user units in [`deploy/systemd/`](../deploy/systemd/) (they expect the
   checkout at `~/homelab-hyperion`; edit both paths in the `.service` file if it's elsewhere). Lingering lets the
   timer run while you're logged out:

   ```sh
   mkdir -p ~/.config/systemd/user
   cp deploy/systemd/homelab-hyperion-backup.* ~/.config/systemd/user/
   sudo loginctl enable-linger "$USER"
   systemctl --user daemon-reload
   systemctl --user enable --now homelab-hyperion-backup.timer
   systemctl --user list-timers homelab-hyperion-backup.timer   # next run: 04:30, plus up to 5 minutes
   journalctl --user -u homelab-hyperion-backup                 # what the last runs did
   ```

Restore a copy from the backup server as [rebuilding.md](rebuilding.md) describes; `scripts/restore.sh` verifies
its `SHA256SUMS` first, and a copy that was cut off has none yet, so it is refused.

## Uninstalling

```sh
systemctl --user disable --now homelab-hyperion-backup.timer   # if you scheduled backups
docker compose down          # stops and removes the containers and the stack's networks
```

The data directories and the downloads are left untouched. Remove the data directories by hand if you no
longer want the services' data.
