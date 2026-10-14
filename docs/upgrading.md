# Upgrading

A homelab-hyperion release changes which image versions run, and sometimes the services or settings. Services often
migrate their database when they start a new version and can't go back afterwards, so **every upgrade starts with a
backup**. The same steps apply to updating a checkout of `main` by hand; the maintainer's server follows `main`
automatically instead, where the merge is the upgrade ([Following `main`](#following-main)).

## Before you upgrade

1. Read the release notes (the `CHANGELOG.md` section) for every release between yours and the new one, and
   the services' own release notes for any major version bump: Dependabot's major updates merge automatically, so
   they arrive without a separate review. Anything under **Upgrading** needs action.
2. Verify the new release ([verifying-releases.md](verifying-releases.md)).
3. If the release changes the **Minecraft server version**, warn the players: the worlds are upgraded when the
   new server first opens them and can't be opened by the old one again, and clients may need to update too.
4. Pause qBittorrent's downloads, or accept that they resume after the restart.

## Backing up

The state worth keeping is each service's data: Prowlarr's database (with the indexers and their credentials),
qBittorrent's settings and torrent list, Heimdall's database, and the Minecraft server's worlds and settings.
`scripts/backup.sh` stops each service in turn while it copies that service's mounts, so its database or world is
consistent, starts it again (with any service Compose stopped along with it), then compresses the copy; services
with nothing to archive keep running. It also copies `.env` and any `<service>.env` (such as `autoheal.env`):

```sh
scripts/backup.sh                       # into backups/<date>-<time>/ in the checkout (gitignored)
scripts/backup.sh /path/to/backup-dir   # or a directory of your choice (new or empty)
```

It **never** archives the downloads directory: it is large, and the apps that import from it keep their own
copies. A service can also leave paths inside a mount out of its archive with the
`org.honeybeartech.hyperion.backup.exclude` label ([interfaces.md](interfaces.md#labels)); no service does yet.

The directory holds one `<service>--<path>.tar.gz` per mount, the settings under `env/`, a `MANIFEST` naming
each archive's service, container path, host path and image, `NETWORKS` (the address range of each network the
stack joins but doesn't create, for a rebuild; this stack creates its own, so only the header), `VERSION` (the
checkout's `git describe`) and `SHA256SUMS`. Everything in it is readable only by the user who ran the backup,
and it holds secrets (Prowlarr's indexer credentials among them). **Copy it off the host**: the nightly
scheduled backup does that for you ([installing.md](installing.md#scheduled-backups)), but take a fresh one
before an upgrade all the same.

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

## Following `main`

The maintainer's server doesn't check out releases: it runs `main`, and a small pull agent (kept in the
maintainer's private orchestration repository, not here) deploys every merge. A systemd user timer starts it about
every 90 seconds; when `main` has moved, it fast-forwards the checkout, runs `docker compose config --quiet`,
`docker compose pull` and `docker compose up -d --remove-orphans --wait`, and logs the old and the new commit. So
**a merge to `main` reaches the server within about two minutes**, including the updates Dependabot merges by
itself ([dependencies.md](dependencies.md#tracking-dependencies)).

- The agent only fast-forwards: it refuses a checkout with local changes or a `main` whose history was rewritten.
  If the configuration doesn't resolve or an image can't be pulled, it moves the checkout back, so the server keeps
  running what it ran.
- **The merge is the upgrade.** Before merging an update that can migrate a service's data, read the release notes
  and take a backup on the server (`scripts/backup.sh`). The updates that merge by themselves (Dependabot's patch,
  minor and major ones, and image rebuilds) rely on the nightly [scheduled backup](installing.md#scheduled-backups);
  a major can migrate its data one way, so undoing it means a revert plus a restore from that backup.
- **Rolling back** is a revert pull request, deployed the same way. If the service already migrated its data,
  restore that too ([Rolling back](#rolling-back)).
- **Holding the server on a version**: check out that commit or release on the server (`git checkout vX.Y.Z`).
  The agent pauses while the checkout isn't on `main`, and carries on once it's switched back (`git switch main`).
- **Backups and deploys take turns.** `scripts/backup.sh` and `scripts/restore.sh` share the agent's lock: they
  wait for a running deploy to finish (up to 30 minutes, then fail before stopping anything), and while they hold
  the lock the agent skips its runs, so it never recreates a service they have stopped. A merge that lands during
  the nightly backup deploys a minute or two after the backup's copies are done. Where no agent runs, the lock is
  skipped.
- **Changed systemd units aren't installed by the deploy.** The agent only runs `docker compose`; the scheduled
  backup's units in `deploy/systemd/` are copied into `~/.config/systemd/user/` once, by hand
  ([installing.md](installing.md#scheduled-backups)). When a merge changes them, copy them again and run
  `systemctl --user daemon-reload` (the scripts they start come from the checkout, so a change to a script needs
  nothing more).

## Rolling back

If a service fails after the upgrade, go back to the previous version **and** restore its data; a service whose
database was migrated forward may not start with the older image. For one service (Prowlarr here):

```sh
git checkout vPREVIOUS
scripts/restore.sh backups/YYYYMMDD-HHMMSS prowlarr   # checks SHA256SUMS, lists what it replaces, asks first
docker compose up -d prowlarr
```

On a server that follows `main`, revert the change with a pull request instead of checking out the old release
(the merge deploys the old version), then restore the service's data the same way.

`scripts/restore.sh` replaces everything in each of the service's mounts listed in the backup's `MANIFEST`
(except the paths its `backup.exclude` label lists and any mount inside it), keeping the files' owners and modes.
Without service names it restores every service in the backup. Rolling
the Minecraft server back to an older version needs its world restored too, which loses whatever players built
since the backup.

## Restoring on a new host

See [rebuilding.md](rebuilding.md): install the host, restore `.env`, then `scripts/restore.sh` creates the
containers and fills their data from the backup.
