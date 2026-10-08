# Rebuilding the host

How to bring the stack back on a new or wiped machine from a backup made by `scripts/backup.sh`
([upgrading.md](upgrading.md#backing-up)), with every service's settings, history and worlds as they were.

> **Planned:** this needs `compose.yaml`, which isn't in the repository yet. The backup and restore scripts
> exist; the rebuild is rehearsed once the stack is in place.

You need: the backup directory (copied off the old host), this repository, and the downloads storage if it's a
network share.

## 1. The operating system

Install a 64-bit Linux server; the reference is **Ubuntu 24.04 on amd64**. Then:

```sh
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y unattended-upgrades git
```

Give the machine the same address the old one had (or update everything that reaches it by address: the media
apps' download client and indexer settings, reverse proxy hosts, monitoring, any router port forwards for
qBittorrent or Minecraft).

If the downloads directory is a network share, mount it at the same host path as before (`DOWNLOADS_PATH` in the
backup's `.env`).

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

Copy any `<service>.env` from the backup's `env/` the same way (mode `600`). Edit `.env` if the new host's
paths differ (but keep the downloads' container path), create the data directories as your user, then:

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
links, and the Minecraft server should load its worlds. A Minecraft release older than the backup's can't open
its worlds: check out that release or a newer one.

## What the backup doesn't bring back

- **The downloads**: never backed up; torrents still in qBittorrent's list download again.
- **Host settings**: the static address, the network share's mount, firewall rules, SSH keys, monitoring
  agents.
- **Other machines' view of this one**: the media apps' settings, reverse proxy hosts, DNS records, router port
  forwards, anything that reaches Hyperion by address.
- **Services from other projects** on the same host: restore them from their own backups.
