# Upgrading

A homelab-hyperion release changes which image versions run, and sometimes the services or settings. Services often
migrate their database when they start a new version and can't go back afterwards, so **every upgrade starts
with a backup**. The same steps apply to updating a checkout of `main`, which is possible but unsupported for
anything you depend on.

> **Planned:** there are no releases yet and no `compose.yaml`. The backup and restore scripts exist and are
> tested against a stand-in stack; they run in CI against the real one once it's added.

## Before you upgrade

1. Read the release notes (the `CHANGELOG.md` section) for every release between yours and the new one, and
   the services' own release notes for any major version bump. Anything under **Upgrading** needs action.
2. Verify the new release ([verifying-releases.md](verifying-releases.md)).
3. If the release changes the **Minecraft server version**, warn the players: the worlds are upgraded when the
   new server first opens them and can't be opened by the old one again, and clients may need to update too.
4. Pause qBittorrent's downloads, or accept that they resume after the restart.

## Backing up

The state worth keeping is each service's data: Prowlarr's database (with the indexers and their credentials),
qBittorrent's settings and torrent list, Heimdall's database, and the Minecraft server's worlds and settings.
`scripts/backup.sh` stops the stack so the databases and worlds are consistent, archives each of those mounts,
copies `.env` and any `<service>.env`, and starts again whatever was running:

```sh
scripts/backup.sh                       # into backups/<date>-<time>/ in the checkout (gitignored)
scripts/backup.sh /path/to/backup-dir   # or a directory of your choice (new or empty)
```

It **never** archives the downloads directory: it is large, and the apps that import from it keep their own
copies.

The directory holds one `<service>--<path>.tar.gz` per mount, the settings under `env/`, a `MANIFEST` naming
each archive's service, container path, host path and image, and `SHA256SUMS`. Everything in it is readable
only by the user who ran the backup, and it holds secrets (Prowlarr's indexer credentials among them). **Copy it
off the host.**

## Upgrading

```sh
git fetch --tags
git checkout vX.Y.Z
docker compose pull
docker compose up -d --wait
docker compose ps
```

Then check each service's web UI and logs (`docker compose logs <service>`, or Dozzle) for migration errors,
that Prowlarr's indexers still test green and the media apps still reach Prowlarr and qBittorrent, and that a
player can join the Minecraft server.

## Rolling back

If a service fails after the upgrade, go back to the previous version **and** restore its data; a service whose
database was migrated forward may not start with the older image. For one service (Prowlarr here):

```sh
git checkout vPREVIOUS
scripts/restore.sh backups/YYYYMMDD-HHMMSS prowlarr   # checks SHA256SUMS, lists what it replaces, asks first
docker compose up -d prowlarr
```

`scripts/restore.sh` replaces everything in each of the service's mounts listed in the backup's `MANIFEST`,
keeping the files' owners and modes. Without service names it restores every service in the backup. Rolling
the Minecraft server back to an older version needs its world restored too, which loses whatever players built
since the backup.

## Restoring on a new host

See [rebuilding.md](rebuilding.md): install the host, restore `.env`, then `scripts/restore.sh` creates the
containers and fills their data from the backup.
