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
  web UI), 9696 (Prowlarr), 19132 TCP and 19140–19149 UDP (Minecraft), and the two Steerhouse ports you choose
  (`STEERHOUSE_PORT`, `STEERHOUSE_METRICS_PORT`).
- A PostgreSQL server for Steerhouse's database (PostgreSQL 18, reachable from this host), `openssl` on the host,
  for `scripts/steerhouse.sh` (Steerhouse's secrets), and a reverse proxy that serves Steerhouse's web UI over HTTPS
  ([Steerhouse](#steerhouse)).
- `age` if the backups are copied off the host encrypted ([Scheduled backups](#scheduled-backups)).
- Acceptance of the [Minecraft EULA](https://www.minecraft.net/eula), which the Bedrock Dedicated Server requires.

## Where data lives

Every app keeps its settings and data in its own folder under one directory you choose, `CONFIG_ROOT`:
`CONFIG_ROOT/<app>/config`, where `<app>` is the service's name. Other host files go beside it as
`CONFIG_ROOT/<app>/<purpose>`: Steerhouse uses `steerhouse/secrets`, and Dozzle uses `dozzle/certs`.

| What | Where on the host | In the container |
| --- | --- | --- |
| Prowlarr's database and settings | `CONFIG_ROOT/prowlarr/config` | `/config` |
| qBittorrent's settings and torrent list | `CONFIG_ROOT/qbittorrent/config` | `/config` |
| qBittorrent's downloads | `DOWNLOADS_PATH` | `/downloads` |
| qBittorrent's incomplete torrents | `INCOMPLETE_PATH` | `/incomplete` |
| Heimdall's database and settings | `CONFIG_ROOT/heimdall/config` | `/config` |
| The Minecraft server's worlds and settings | `CONFIG_ROOT/minecraft/config` | `/data` |
| Dozzle's settings (saved in its UI) | `CONFIG_ROOT/dozzle/config` | `/data` |
| Dozzle's certificate and key for its agents (owned by root, not backed up; [below](#dozzles-certificate)) | `CONFIG_ROOT/dozzle/certs` | `/run/secrets/dozzle_cert`, `/run/secrets/dozzle_key`, read-only |
| Steerhouse's playbooks, run logs, Galaxy content and git checkouts | `CONFIG_ROOT/steerhouse/config` | `/data` (the workers: `galaxy/` at `/galaxy`, read-only) |
| Steerhouse's secrets (not backed up) | `CONFIG_ROOT/steerhouse/secrets` | `/run/secrets/<name>`, read-only |

The container paths are fixed in `compose.yaml` ([interfaces.md](interfaces.md#volumes-and-mounts)). The apps'
folders must be owned by `PUID`:`PGID`, except Dozzle's: Dozzle runs as root, so leave its folder for Docker to
create (owned by root) on the first start. Steerhouse's API runs as `PUID`:`PGID` and can't take ownership of
anything, so create its folder before the first start; its database is on a PostgreSQL server, not here. autoheal
and the socket proxy keep no data.

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
2. Create `.env` from `.env.example` (mode `600`) and set the required settings, including acceptance of the
   Minecraft EULA.
   Optional settings may remain empty; see [interfaces.md](interfaces.md#settings).
   Optionally create `autoheal.env` from `autoheal.env.example` (mode `600`) for restart notices.
3. Create the apps' folders as the `PUID`:`PGID` user (all but Dozzle's,
   [quick start](quick-start.md)), Steerhouse's database, secrets and tokens
   ([below](#steerhouse)), configure the HTTPS reverse proxy, and install Dozzle's certificate and key
   even without remote agents ([below](#dozzles-certificate)), then
   `docker compose up -d --wait`.

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
it as the most sensitive service here. It is three pieces from Steerhouse's own `deploy/compose.yaml`: the API
(`steerhouse`), the workers that run the playbooks (`steerhouse-worker`) and the web UI (`steerhouse-frontend`). Its
database is in PostgreSQL on a database server, not in this stack: the API reaches it with one URL, login and
password included, which it reads from a secret file. An external monitoring system handles its monitoring: the API's
Prometheus metrics are published for it, and its Grafana reads the database's read-only `analytics` views on the
database server.

Before the first start:

1. **On the database server**, as its administrator in `psql`, make a login that owns one new database, and the
   read-only role the monitoring system's Grafana logs in as, each with a long random password
   (for example `openssl rand -hex 24`).
   Steerhouse's login needs no other rights: it can't make roles, which is why `grafana_ro` is made here, with the
   settings Steerhouse documents for it:

   ```sql
   CREATE ROLE steerhouse LOGIN PASSWORD '<its password>';
   CREATE DATABASE steerhouse OWNER steerhouse;
   CREATE ROLE grafana_ro WITH LOGIN NOINHERIT CONNECTION LIMIT 10 PASSWORD '<grafana_ro's password>';
   ALTER ROLE grafana_ro SET default_transaction_read_only = on;
   ALTER ROLE grafana_ro SET statement_timeout = '30s';
   ALTER ROLE grafana_ro SET search_path = analytics;
   GRANT CONNECT ON DATABASE steerhouse TO grafana_ro;
   ```

   Let `steerhouse` connect from this host and `grafana_ro` from the monitoring host (`pg_hba.conf`, `hostssl` with
   `scram-sha-256`).
2. **Folders and secrets**, on this host as the `PUID`:`PGID` user, in the checkout. `scripts/steerhouse.sh` never
   replaces a file that exists. First set the shell variable `CONFIG_ROOT` to the configuration directory you
   chose in `.env`; do not source `.env` or try to parse it as shell code.

   ```sh
   mkdir -p "$CONFIG_ROOT/steerhouse/config"
   scripts/steerhouse.sh secrets "$CONFIG_ROOT/steerhouse/secrets"
   scripts/steerhouse.sh env steerhouse.env
   ```

   `secrets` writes three of the four secret files ([interfaces.md](interfaces.md#steerhouses-secret-files)), `env`
   the two tokens. **Save `credential_encryption_key` in a password manager now**, with the other secrets: they are
   never in the stack's backups, on purpose (anyone with a database backup and the key can decrypt every stored SSH
   key), and a database restored without its key is useless. `admin_password` is the first admin's password (user
   `admin`); change it in Steerhouse after signing in.
3. **The database's URL**, the fourth secret, with the login from step 1. `read -s` keeps the password out of the
   shell's history:

   ```sh
   (umask 077 && read -rsp 'Password: ' pw && echo &&
     printf 'postgresql+psycopg://steerhouse:%s@db.example.com:5432/steerhouse?sslmode=require\n' "$pw" \
       >"$CONFIG_ROOT/steerhouse/secrets/database_url")
   ```

   Use the database server's name. A password with any of `@:/?#%` in it must be percent-encoded in the URL (a
   hexadecimal one never needs it). `sslmode=require` encrypts the connection; `verify-full` would also check the
   server's certificate, which needs its CA certificate inside the container.
4. **Settings** in `.env`: `STEERHOUSE_PORT`, `STEERHOUSE_PUBLIC_URL`, `STEERHOUSE_TRUSTED_PROXIES` (the reverse
   proxy's address) and `STEERHOUSE_METRICS_PORT`.
5. **HTTPS in front.** On the reverse proxy (Nginx Proxy Manager), a proxy host for the name in
   `STEERHOUSE_PUBLIC_URL`, forwarding to `http://<this host>:<STEERHOUSE_PORT>`, with **Websockets Support** on
   (live run output uses them), an SSL certificate, Force SSL and HSTS, and, under Advanced,
   `proxy_read_timeout 1h;` (long runs keep their output stream open). It passes the `Host` header and the
   client's address in `X-Forwarded-For`, which Steerhouse believes from `STEERHOUSE_TRUSTED_PROXIES` only. Don't
   strip the security headers the web UI sends.

   Install [Dozzle's certificate and key](#dozzles-certificate) before starting the stack too.
6. **Start it** (`docker compose up -d --wait`). The API makes and migrates its tables on its first start.
7. **The analytics views for the monitoring system's Grafana**, once the stack is up:

   ```sh
   scripts/steerhouse.sh grafana-role
   ```

   It runs Steerhouse's own commands in the API's container, over the API's connection: `analytics-grant` lets
   `grafana_ro` read the `analytics` views, and `analytics-check` checks that it can read nothing else. Run it again
   after an upgrade of Steerhouse.
8. **Sign in** at `STEERHOUSE_PUBLIC_URL` as `admin`, change the password and set up two-factor login: admins must
   (`REQUIRE_ADMIN_2FA` is on). Then follow Steerhouse's quick start from its step 2.

**What the monitoring system needs**, over the LAN:

| For | Address | Credentials |
| --- | --- | --- |
| Prometheus | `http://<this host>:<STEERHOUSE_METRICS_PORT>/metrics` | `Authorization: Bearer <METRICS_TOKEN>` (from `steerhouse.env`) |
| Grafana's PostgreSQL data source | the database server, database `steerhouse` | user `grafana_ro` and its password from step 1; TLS as the database server requires it; max open connections below 10 |

The metrics answer only with the token, but over plain HTTP: keep the port on the LAN.

**Backups and restores.** The nightly backup archives the API's folder, never the secrets; the database is backed
up on its server, not here. To restore on a new host, put the secret files and `steerhouse.env` back first, from the
password manager. To give the login a new password (`ALTER ROLE steerhouse PASSWORD '…'` on the server), write
`database_url` again as in step 3 and `docker compose restart steerhouse`.

## Dozzle's certificate

Dozzle and its agents on other hosts (`DOZZLE_REMOTE_AGENT`) authenticate each other with a certificate and key:
each end presents the pair and accepts only a peer that presents the same one. Every Dozzle image also ships a
built-in pair, the same in every copy, so an agent that uses it accepts anyone on the network who has a Dozzle image,
and through it they can read every container's log on that host and control its Docker. This stack's Dozzle never
uses the built-in pair: it reads its own from two files under `CONFIG_ROOT/dozzle/certs` (Docker secrets, mounted
read-only in `/run/secrets`), and it doesn't start while either file is missing. Every agent it connects to needs the
same pair (the homelab's agent stacks read it the same way).

| File | Owner, mode | What |
| --- | --- | --- |
| `CONFIG_ROOT/dozzle/certs/dozzle_cert.pem` | `root:root`, `644` | The certificate (self-signed, valid for five years) |
| `CONFIG_ROOT/dozzle/certs/dozzle_key.pem` | `root:root`, `600` | Its private key: **a secret**; whoever holds it can connect to every agent |

Both belong to root: Dozzle runs as root without capabilities, so it can read only a file that root owns (or one
that every user can read, which the key must never be).

**One pair for Dozzle and all its agents.** Make it once, on a machine you trust, with the Dozzle image this stack
pins (the `image:` of `dozzle` in `compose.yaml`):

```sh
mkdir -m 700 dozzle-pair
docker run --rm --network none -v "$PWD/dozzle-pair:/out" amir20/dozzle:<tag>@sha256:<digest> \
  --no-analytics generate-certs --cert-out /out/dozzle_cert.pem --key-out /out/dozzle_key.pem
```

Save both files in a password manager, with Steerhouse's secrets: they are never in the stack's backups
(`scripts/backup.sh` copies read-write mounts only), so that is where a rebuilt host gets them back from. Then copy
them to this host and to every agent's (for example with `scp` into your home directory) and, in each checkout, put
them in place. First set the shell variable `CONFIG_ROOT` to the configuration directory chosen in `.env`;
do not source `.env`. These files are required even when `DOZZLE_REMOTE_AGENT` is empty.

```sh
sudo install -d -o root -g root -m 755 "$CONFIG_ROOT/dozzle/certs"
sudo install -o root -g root -m 644 ~/dozzle_cert.pem "$CONFIG_ROOT/dozzle/certs/dozzle_cert.pem"
sudo install -o root -g root -m 600 ~/dozzle_key.pem "$CONFIG_ROOT/dozzle/certs/dozzle_key.pem"
rm ~/dozzle_cert.pem ~/dozzle_key.pem
```

`docker compose logs dozzle` then says `Loaded custom dozzle certificate and key` at each start, and Dozzle lists
each agent as a host of its own. An agent whose pair differs is refused, and Dozzle shows it as unavailable (its log
says `authentication handshake failed`). So to change the pair (before it expires, or at once if the key may have
leaked), put the new one on every host first, then recreate the agents and Dozzle with it, one right after the other
(`docker compose up -d --force-recreate dozzle` here), Dozzle last, so that it connects to every agent afresh: until
then it can't show the hosts whose pair differs from its own. The logs themselves aren't lost: Docker keeps them,
and Dozzle shows them again once it reaches the agent.

## Running it securely

- **Web UIs on the LAN only.** Don't publish Prowlarr's, qBittorrent's, Heimdall's or Dozzle's ports beyond the
  LAN; Docker-published ports bypass host firewalls such as `ufw`, so restrict them at the router or with Docker's
  own `DOCKER-USER` rules, and use a reverse proxy's access lists for names you give them.
- **Turn on every login a service offers**, with long, unique passwords: Prowlarr and qBittorrent require one;
  Heimdall and Dozzle can have one.
- **Treat Dozzle as admin access.** It reads every container's logs through the Docker socket, and every
  connected host's through its Dozzle agent; keep those agents' ports on the LAN too. The socket is
  mounted read-only, which protects the socket file, not the API behind it. Its key is a credential for every
  agent: keep it secret ([Dozzle's certificate](#dozzles-certificate)).
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

`scripts/scheduled-backup.sh` takes a backup (`scripts/backup.sh`), copies it to another machine with rsync
(encrypted with age, when `BACKUP_AGE_RECIPIENT` is set), keeps only the newest few in both places and reports to an
Uptime Kuma push monitor. A systemd timer runs it nightly. Every setting is in the optional `backup.env`
([interfaces.md](interfaces.md#backupenv)). The backups hold every login and token, Prowlarr's indexer credentials
among them: copy them only to a machine you trust as much as this one, or encrypt the copy (step 3). The downloads
are never part of them.

1. **On the backup server**, create a folder for the backups and a user that can write only there and use rsync
   over SSH (on a Synology: a shared folder, a non-admin user with read/write on that folder only, rsync allowed
   under Application Privileges, SSH on, the rsync service on under File Services, and the user home service on so
   the user can have an `authorized_keys`). Whoever controls this host can delete or overwrite what it copied
   there, so keep older versions where the backup user can't reach them: snapshots of the folder, or a versioned
   copy of it made on the server after the nightly backup (on a Synology without Btrfs, a Hyper Backup task with
   rotation, into a folder the backup user has no access to). A recycle bin isn't enough: Synology's doesn't keep
   files deleted over rsync.
2. **On this host**, as the user who runs the stack, install rsync and curl (and pigz, which compresses the
   archives on every core instead of one; age, to encrypt the copy), and create a key used only for the backups,
   with an alias for it in `~/.ssh/config`:

   ```sh
   sudo apt install -y rsync curl pigz age
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
3. **The encryption key** (optional, recommended), on another machine you trust (not this host):
   `age-keygen -o hyperion-backup.key`. It prints the public key (`age1...`). Keep the key file where you keep your
   other recovery secrets, such as a password manager, and never copy it to this host: without it no encrypted
   backup off the host can be read, and with it any of them can.
4. **Settings**: `cp backup.env.example backup.env && chmod 600 backup.env`, then set
   `BACKUP_REMOTE=backup-host:/volume1/<folder>`, `BACKUP_AGE_RECIPIENT=age1...` (the public key from step 3; leave
   it empty to copy the backups as they are) and, optionally, the retention and `BACKUP_PING_URL`. For the ping, add
   a monitor of type **Push** in Uptime Kuma with a heartbeat interval of 25 hours, and copy its URL.
5. **Try it**: `scripts/scheduled-backup.sh`. Each service stops only while its own data is copied (seconds for
   this stack's data), and the archives are compressed after it has started again. With `BACKUP_AGE_RECIPIENT`, the
   copy off the host is one folder per backup holding only `backup.tar.age` and its `SHA256SUMS`; the backup itself
   stays readable here, in `BACKUP_DIR`.
6. **Schedule it**, with the systemd user units in [`deploy/systemd/`](../deploy/systemd/) (they expect the
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
its `SHA256SUMS` first, and a copy that was cut off has none yet, so it is refused. An encrypted copy is decrypted
first with the private key (`age -d -i hyperion-backup.key backup.tar.age | tar -x`), which gives the backup
directory `scripts/restore.sh` reads; check the copy's `SHA256SUMS` before that (it is sent last, so a copy that was
cut off has none).

## Uninstalling

```sh
systemctl --user disable --now homelab-hyperion-backup.timer   # if you scheduled backups
docker compose down          # stops and removes the containers and the stack's networks
```

The apps' folders under `CONFIG_ROOT` and the downloads are left untouched. Remove them by hand if you no longer
want the services' data.
