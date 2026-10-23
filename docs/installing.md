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
  web UI), 9696 (Prowlarr), 19132 TCP and 19140–19149 UDP (Minecraft), and the three Steerhouse ports you choose
  (`STEERHOUSE_PORT`, `STEERHOUSE_METRICS_PORT`, `STEERHOUSE_POSTGRES_PORT`).
- `openssl` on the host, for `scripts/steerhouse.sh` (Steerhouse's secrets and its database's certificate), and a
  reverse proxy that serves Steerhouse's web UI over HTTPS ([Steerhouse](#steerhouse)).
- Acceptance of the [Minecraft EULA](https://www.minecraft.net/eula), which the Bedrock Dedicated Server requires.

## Where data lives

Every app keeps its settings and data in its own folder under one directory you choose, `CONFIG_ROOT` (for
example `/srv/config`, or a folder in your home directory): `CONFIG_ROOT/<app>/config`, where `<app>` is the
service's name. Anything else an app keeps on the host goes beside it, as `CONFIG_ROOT/<app>/<purpose>` (none does
yet).

| What | Where on the host | In the container |
| --- | --- | --- |
| Prowlarr's database and settings | `CONFIG_ROOT/prowlarr/config` | `/config` |
| qBittorrent's settings and torrent list | `CONFIG_ROOT/qbittorrent/config` | `/config` |
| qBittorrent's downloads | `DOWNLOADS_PATH` | `/downloads` |
| qBittorrent's incomplete torrents | `INCOMPLETE_PATH` | `/incomplete` |
| Heimdall's database and settings | `CONFIG_ROOT/heimdall/config` | `/config` |
| The Minecraft server's worlds and settings | `CONFIG_ROOT/minecraft/config` | `/data` |
| Dozzle's settings (saved in its UI) | `CONFIG_ROOT/dozzle/config` | `/data` |
| Steerhouse's playbooks, run logs, Galaxy content and git checkouts | `CONFIG_ROOT/steerhouse/config` | `/data` (the workers: `galaxy/` at `/galaxy`, read-only) |
| Steerhouse's secrets (not backed up) | `CONFIG_ROOT/steerhouse/secrets` | `/run/secrets/<name>`, read-only |
| Steerhouse's database, and its TLS certificate and key (`tls/`) | `CONFIG_ROOT/steerhouse-postgres/config` | `/var/lib/postgresql` |

The container paths are fixed in `compose.yaml` ([interfaces.md](interfaces.md#volumes-and-mounts)). The apps'
folders must be owned by `PUID`:`PGID`, except Dozzle's: Dozzle runs as root, so leave its folder for Docker to
create (owned by root) on the first start. Steerhouse's API and database run as `PUID`:`PGID` and can't take
ownership of anything, so create their folders before the first start. autoheal and the socket proxy keep no data.

> **Warning: keep app data out of Docker volumes.** Never point `CONFIG_ROOT`, `DOWNLOADS_PATH`, `INCOMPLETE_PATH` or any other path
> setting into `/var/lib/docker/volumes`, and don't keep app data in named Docker volumes. `docker volume prune`,
> `docker system prune --volumes` and Portainer's "remove unused volumes" delete every volume that no container
> mounts *as a volume*, and that includes a volume whose `_data` folder a service bind-mounts by its path: Docker
> counts it as unused, and the app's data is gone. Keep the data under `CONFIG_ROOT`, which no prune touches, and
> back it up ([below](#scheduled-backups)).

### Downloads on a network share

`DOWNLOADS_PATH` and `INCOMPLETE_PATH` may be on a network share (NFS or SMB, from a NAS). qBittorrent must then
read and write the files rather than map them into memory: on a share, memory-mapped files make the share's page
cache count as qBittorrent's memory and make every page fault wait on the network. The pinned build uses
libtorrent 2.1, whose disk I/O does that by default. Check it in qBittorrent's web UI, under Settings → Advanced →
"Disk IO type (requires restart)": **Default** or **Pread/pwrite**, never "Memory mapped files"; after changing it,
restart qBittorrent (`docker compose restart qbittorrent`). The setting is kept in qBittorrent's own settings
(`CONFIG_ROOT/qbittorrent/config`), so `compose.yaml` can't set it. qBittorrent also gets a minute to stop
(`stop_grace_period`), so that it can finish writing to the share before Docker stops it.

## Installing

1. Clone the repository (or download a release's source archive and verify it,
   [verifying-releases.md](verifying-releases.md)).
2. Create `.env` from `.env.example` (mode `600`) and set every value, including `MINECRAFT_EULA=TRUE`.
   Optionally create `autoheal.env` from `autoheal.env.example` (mode `600`) for restart notices.
3. Create the apps' folders as the `PUID`:`PGID` user (all but Dozzle's,
   [quick start](quick-start.md)), and Steerhouse's secrets, tokens and database certificate
   ([below](#steerhouse)), then `docker compose up -d --wait`.

**Adopting existing containers.** If the services already run on the host (from Portainer stacks or another
Compose project), move their existing data into the apps' folders instead of starting empty: stop the old
containers, take a backup of the old data, and move or copy each one's data into `CONFIG_ROOT/<app>/config`
(`docker inspect --format '{{json .Mounts}}' <container>` shows what it mounts where). Copy with `cp -a` (as root
for data in a Docker volume) so the owners stay the same. Keep the same published ports and the **same container
path for the downloads**: qBittorrent records every torrent's save path, and the media apps map that path to their
own view of the files, so a different mount point breaks both. Run the same Minecraft server version as before (or
newer): a world opened by a newer server can't go back to an older one. Set `MINECRAFT_LEVEL_NAME` to the existing
world's folder name (otherwise the server starts a new, empty world), make `CONFIG_ROOT/minecraft/config` owned by
`PUID`:`PGID` (the server runs as that user, not as root), and check that `allowlist.json` names the players.

The maintainer's server runs `main` rather than a release, and deploys every merge by itself
([upgrading.md](upgrading.md#following-main)). For your own setup, a release is the safer choice.

## Steerhouse

[Steerhouse](https://github.com/HoneyBearTech/Steerhouse) runs Ansible playbooks from a web UI. It stores the SSH
keys, vault passwords and tokens of the machines it manages (encrypted with `credential_encryption_key`), so treat
it as the most sensitive service here. It is five pieces: the database (`steerhouse-postgres`), the API
(`steerhouse`), the workers that run the playbooks (`steerhouse-worker`) and the web UI (`steerhouse-frontend`),
from Steerhouse's own `deploy/compose.yaml`. Its monitoring is Argus' job (on another host): the API's Prometheus
metrics and the database's read-only `analytics` views are published for it, the database over TLS only.

Before the first start, as the `PUID`:`PGID` user, in the checkout:

1. **Folders and secrets.** `scripts/steerhouse.sh` never replaces a file that exists.

   ```sh
   . ./.env
   mkdir -p "$CONFIG_ROOT/steerhouse/config" "$CONFIG_ROOT/steerhouse-postgres/config"
   scripts/steerhouse.sh secrets "$CONFIG_ROOT/steerhouse/secrets"
   scripts/steerhouse.sh env steerhouse.env
   ```

   `secrets` writes the six secret files ([interfaces.md](interfaces.md#steerhouses-secret-files)), `env` the two
   tokens. **Save `credential_encryption_key` in a password manager now**, with the other secrets: they are never in
   the stack's backups, on purpose (anyone with a database backup and the key can decrypt every stored SSH key),
   and a database restored without its key is useless. `admin_password` is the first admin's password (user
   `admin`); change it in Steerhouse after signing in.
2. **The database's certificate**, from a certificate authority of your own. Make the CA once, on a machine you
   trust, and keep `ca.key` off this host (in the password manager, say); then issue the server certificate for
   every name and address Argus' Grafana connects to (it checks them):

   ```sh
   scripts/steerhouse.sh ca ~/steerhouse-ca     # ca.crt and ca.key, valid 10 years
   scripts/steerhouse.sh cert ~/steerhouse-ca "$CONFIG_ROOT/steerhouse-postgres/config/tls" \
     <this host's DNS name> <this host's address>
   ```

   That writes `server.crt` and `server.key` (mode `600`, owned by you: the database runs as `PUID`) and `ca.crt`,
   the certificate Argus pins. They are backed up with the database. The server certificate is valid for 3 years;
   to renew it, move the `tls` folder aside, run `cert` again and `docker compose restart steerhouse-postgres`.
3. **Settings** in `.env`: `STEERHOUSE_PORT`, `STEERHOUSE_PUBLIC_URL`, `STEERHOUSE_TRUSTED_PROXIES` (the reverse
   proxy's address), `STEERHOUSE_METRICS_PORT`, `STEERHOUSE_POSTGRES_PORT` and `STEERHOUSE_DB_SUBNET`, a private
   range that no network on the host uses yet:

   ```sh
   docker network inspect --format '{{.Name}} {{range .IPAM.Config}}{{.Subnet}} {{end}}' $(docker network ls -q)
   ```

4. **Start it** (`docker compose up -d --wait`). The API creates and migrates the database on its first start.
5. **The role for Argus' Grafana**, once the stack is up:

   ```sh
   scripts/steerhouse.sh grafana-role
   ```

   It runs Steerhouse's own setup in the API's container: it creates `grafana_ro` as Steerhouse documents
   (`LOGIN NOINHERIT CONNECTION LIMIT 10`, read-only transactions, `statement_timeout` 30 s, `search_path`
   `analytics`), lets it read the `analytics` views (`analytics-grant`) and checks that it can read nothing else
   (`analytics-check`). Run it again after you change `grafana_db_password` (it sets the role's password again) and
   after an upgrade of Steerhouse.
6. **HTTPS in front.** On the reverse proxy (Nginx Proxy Manager), a proxy host for the name in
   `STEERHOUSE_PUBLIC_URL`, forwarding to `http://<this host>:<STEERHOUSE_PORT>`, with **Websockets Support** on
   (live run output uses them), an SSL certificate, Force SSL and HSTS, and, under Advanced,
   `proxy_read_timeout 1h;` (long runs keep their output stream open). It passes the `Host` header and the
   client's address in `X-Forwarded-For`, which Steerhouse believes from `STEERHOUSE_TRUSTED_PROXIES` only. Don't
   strip the security headers the web UI sends.
7. **Sign in** at `STEERHOUSE_PUBLIC_URL` as `admin`, change the password and set up two-factor login: admins must
   (`REQUIRE_ADMIN_2FA` is on). Then follow Steerhouse's quick start from its step 2.

**What Argus needs**, over the LAN:

| For | Address | Credentials |
| --- | --- | --- |
| Prometheus | `http://<this host>:<STEERHOUSE_METRICS_PORT>/metrics` | `Authorization: Bearer <METRICS_TOKEN>` (from `steerhouse.env`) |
| Grafana's PostgreSQL data source | `<this host>:<STEERHOUSE_POSTGRES_PORT>`, database `steerhouse` | user `grafana_ro`, password `grafana_db_password`; TLS mode `verify-full` with `ca.crt` (`CONFIG_ROOT/steerhouse-postgres/config/tls/ca.crt`); max open connections below 10 |

The database accepts nothing else from outside its internal network: no connection without TLS (and TLS 1.3 only),
no other role, and its own user `steerhouse` only from `steerhouse-db`. The metrics answer only with the token, but
over plain HTTP: keep the port on the LAN.

**Backups and restores.** The nightly backup archives the API's folder and the database's (the database is stopped
while its folder is copied, which keeps the copy consistent), certificate included; never the secrets. To restore
on a new host, put the secret files and `steerhouse.env` back first, from the password manager.

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
- **Steerhouse holds the keys to other machines.** Keep its web UI behind the reverse proxy's HTTPS and on the
  LAN, keep two-factor login on for admins, and give each person only the projects they need. Its database and
  metrics ports are for Argus only: TLS and `grafana_ro` for the one, a token for the other.
- **qBittorrent is on the public internet** by design: peers see your public IP address. Forward only its
  listening port, never its web UI. Whether to route it through a VPN is your decision; this stack has none.
- **Minecraft from outside the LAN** means forwarding TCP 19132 and UDP 19140–19149, and setting
  `MINECRAFT_ADDRESS` to an address those players can reach. Do it only if you mean to; the server's allowlist is
  on, so only the players you name can join.
- Keep `.env` at mode `600`; it holds no secrets by design, but it describes your host. `autoheal.env` holds a
  secret (anyone with the webhook URL can post to the channel), and `steerhouse.env` two: mode `600`, never
  committed. Steerhouse's secret files stay mode `600` in a folder of mode `700`.
- Back up the apps' folders under `CONFIG_ROOT` ([upgrading.md](upgrading.md#backing-up)), and schedule a nightly copy
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

   Neither an upgrade nor a deploy by the pull agent installs these units: when a new version changes the files in
   `deploy/systemd/`, copy them again and run `systemctl --user daemon-reload`.

On a server whose pull agent deploys `main` ([upgrading.md](upgrading.md#following-main)), the backup waits for a
running deploy to finish and keeps the agent from deploying until its copies are done.

Restore a copy from the backup server as [rebuilding.md](rebuilding.md) describes; `scripts/restore.sh` verifies
its `SHA256SUMS` first, and a copy that was cut off has none yet, so it is refused.

## Uninstalling

```sh
systemctl --user disable --now homelab-hyperion-backup.timer   # if you scheduled backups
docker compose down          # stops and removes the containers and the stack's networks
```

The apps' folders under `CONFIG_ROOT` and the downloads are left untouched. Remove them by hand if you no longer
want the services' data.
