# Rebuilding the host

How to bring the stack back on a new or wiped machine from a backup made by `scripts/backup.sh`
([upgrading.md](upgrading.md#backing-up)), with every service's settings, history and worlds as they were.

> This rebuild hasn't been rehearsed on a scratch machine. The backup and restore round trip it relies on runs
> in CI on every change.

You need: the backup directory (copied off the old host; from the backup server, take the newest one that has a
`SHA256SUMS`, since a copy that was cut off has none), **the age private key** it was encrypted to if the copies off
the host are encrypted (`BACKUP_AGE_RECIPIENT`; [below](#opening-an-encrypted-copy)), this repository, and the
downloads storage if it's a network share.

## Opening an encrypted copy

An encrypted copy (its folder on the backup server holds only `backup.tar.age` and `SHA256SUMS`) is opened on the
machine that holds the age private key, never on the backup server or the new host. Copy it there and check it
against its `SHA256SUMS`, then decrypt it, which gives the backup directory as it was written on the old host, and
copy that to the new host:

```sh
rsync -rlpt backup-host:/volume1/<folder>/<date>-<time>/ ~/sealed/
cd ~/sealed && sha256sum -c --quiet SHA256SUMS && cd -
(umask 077 && age -d -i hyperion-backup.key ~/sealed/backup.tar.age | tar -x -C ~)   # ~/<date>-<time>/
rsync -rlpt ~/<date>-<time>/ <you>@<the new host>:restore/
rm -rf ~/sealed ~/<date>-<time>
```

On the new host, `~/restore` is then the backup directory that the steps below call `/path/to/backup`. Keep it
private: it holds every login and private key the backup has.

## 1. The operating system

Install a 64-bit Linux server; the reference is **Ubuntu 24.04 on amd64**. Then:

```sh
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y unattended-upgrades git
```

Give the machine the same address the old one had (or update everything that reaches it by address: the media
apps' download client and indexer settings, reverse proxy hosts, monitoring, any router port forwards for
qBittorrent or Minecraft).

If the downloads or incomplete directory is a network share, mount it at the same host path as before
(`DOWNLOADS_PATH` and `INCOMPLETE_PATH` in the backup's `.env`).

## 2. Docker

Install Docker Engine and the Compose plugin from Docker's own repository, following
[docs.docker.com/engine/install/ubuntu](https://docs.docker.com/engine/install/ubuntu/) (Docker Engine 25 or
later, Compose 2.24 or later). Then:

```sh
sudo usermod -aG docker "$USER"      # equivalent to root on the host; log in again
```

Don't install an auto-updater such as Watchtower ([installing.md](installing.md#running-it-securely)).

## 3. The repository and settings

```sh
git clone https://github.com/HoneyBearTech/homelab-hyperion.git && cd homelab-hyperion
git checkout vX.Y.Z      # the release the backup was taken with, or newer; verify it (verifying-releases.md)
cp /path/to/backup/env/.env .env && chmod 600 .env
```

A server that follows `main` ([upgrading.md](upgrading.md#following-main)) stays on `main` here instead
(skip the `git checkout`), and gets its pull agent back once the stack is healthy.

The backup's `VERSION` names the release (or commit) the old host ran; backups made before it existed don't
have one, so check the release notes instead.

Copy any `<service>.env` from the backup's `env/` the same way (mode `600`). Steerhouse's secret files aren't in the
backup, on purpose: put them back into `CONFIG_ROOT/steerhouse/secrets` (mode `700`, the files `600`) from the
password manager before the restore, above all `credential_encryption_key`, without which Steerhouse can't decrypt
any credential in its restored database ([installing.md](installing.md#steerhouse)). Dozzle's certificate and key
aren't in it either: put them back into `CONFIG_ROOT/dozzle/certs` from the password manager, owned by root
([installing.md](installing.md#dozzles-certificate)), or the restore can't create Dozzle's container. Edit `.env` if the new host's
paths differ (but keep the downloads' container path). A backup taken before the apps' data moved under
`CONFIG_ROOT` has an `.env` without it: add `CONFIG_ROOT` (see `.env.example`) and drop the old per-app path
settings; the restore puts each archive into the app's folder under `CONFIG_ROOT` all the same. Create the apps'
folders as your user (all but Dozzle's, as in the [quick start](quick-start.md)), then:

```sh
docker compose config --quiet && docker compose pull
```

## 4. Restore and start

```sh
scripts/restore.sh /path/to/backup    # verifies SHA256SUMS, creates the containers, asks first
docker compose up -d --wait           # waits until every service reports healthy
docker compose ps
```

Then sign in to each service: Prowlarr should list its indexers and apps, qBittorrent its torrents, Heimdall its
links, the Minecraft server should load its worlds, and Steerhouse should list its projects and decrypt a
credential (run a playbook that uses one). Its database's certificate comes back with the database; if the new host
has another name or address, sign a new one for it (`scripts/steerhouse.sh sign`) with the same CA, which Argus
already trusts. A Minecraft release older than the backup's can't open
its worlds: check out that release or a newer one.

## What the backup doesn't bring back

- **The downloads**: never backed up; torrents still in qBittorrent's list download again.
- **Host settings**: the static address, the network share's mount, firewall rules, SSH keys, monitoring
  agents, and the scheduled backup (its key for the backup server, the `~/.ssh/config` alias and the systemd
  units: set them up again as [installing.md](installing.md#scheduled-backups) describes; `backup.env` comes back
  from the backup's `env/`).
- **Steerhouse's secrets**: they live in the password manager, not in the backup (see above).
- **Dozzle's certificate and key** (`CONFIG_ROOT/dozzle/certs`): in the password manager too (see above).
- **Other machines' view of this one**: the media apps' settings, reverse proxy hosts, DNS records, router port
  forwards, anything that reaches Hyperion by address (Argus' Prometheus and Grafana, for Steerhouse).
- **Services from other projects** on the same host: restore them from their own backups.
