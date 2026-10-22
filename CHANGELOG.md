# Changelog

All notable changes to homelab-hyperion are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Upgrading

- **Add `INCOMPLETE_PATH` to `.env` before this is deployed** (required; see `.env.example`): the host directory
  qBittorrent keeps torrents in while they download, mounted at `/incomplete`. It must exist and be writable by
  `PUID:PGID`. A deploy without it stops at `docker compose config` and changes nothing.
- **Move each app's data into its folder under `CONFIG_ROOT` before this is deployed, then add `CONFIG_ROOT` to
  `.env`** (required; see `.env.example`). A deploy without `CONFIG_ROOT` stops at `docker compose config` and
  changes nothing, so the old containers keep running until then (a server's pull agent tries again on its next
  run). With the stack stopped (`docker compose stop`), move or copy:

  | App | Before | Now |
  | --- | --- | --- |
  | prowlarr | the `PROWLARR_CONFIG_PATH` folder | `CONFIG_ROOT/prowlarr/config`, owned by `PUID:PGID` |
  | qbittorrent | the `QBITTORRENT_CONFIG_PATH` folder | `CONFIG_ROOT/qbittorrent/config`, owned by `PUID:PGID` |
  | heimdall | the `HEIMDALL_CONFIG_PATH` folder | `CONFIG_ROOT/heimdall/config`, owned by `PUID:PGID` |
  | minecraft | the `MINECRAFT_DATA_PATH` folder | `CONFIG_ROOT/minecraft/config`, owned by `PUID:PGID` |
  | dozzle | the `dozzle-data` volume (`homelab-hyperion_dozzle-data` by default) | `CONFIG_ROOT/dozzle/config`, owned by root |

  For example, with `CONFIG_ROOT` set in your shell:

  ```sh
  . ./.env && docker compose stop
  mkdir -p "$CONFIG_ROOT/prowlarr" && mv "$PROWLARR_CONFIG_PATH" "$CONFIG_ROOT/prowlarr/config"
  # ... the same for qbittorrent, heimdall and minecraft (sudo cp -a instead of mv across filesystems)
  docker run --rm --network none -v homelab-hyperion_dozzle-data:/from:ro -v "$CONFIG_ROOT/dozzle/config:/to" \
    busybox cp -a /from/. /to/
  ```

  `mv` and `cp -a` keep the files' owners. Then add `CONFIG_ROOT` to `.env`, drop `PROWLARR_CONFIG_PATH`,
  `QBITTORRENT_CONFIG_PATH`, `HEIMDALL_CONFIG_PATH` and `MINECRAFT_DATA_PATH` (no longer read), and deploy
  (`docker compose up -d --wait`). Remove the old Dozzle volume (`docker volume rm`) once Dozzle runs from its
  folder. Never put `CONFIG_ROOT` inside `/var/lib/docker/volumes`.
- Backups taken before this restore as they are: `scripts/restore.sh` puts each archive into the app's folder under
  `CONFIG_ROOT`.

### Added

- qBittorrent mounts `INCOMPLETE_PATH` at `/incomplete` for torrents still downloading ("Keep incomplete torrents
  in"). Like `/downloads`, it is in qBittorrent's `backup.skip` label: never backed up, never written by a restore.

### Changed

- Each app's settings and data move to one place on the host: `CONFIG_ROOT/<app>/config`, mounted at the same
  container path as before (`/config`; `/data` for Minecraft and Dozzle), the layout every homelab stack now uses
  (the maintainer's decision, 2026-10-15). The new required setting `CONFIG_ROOT` replaces `PROWLARR_CONFIG_PATH`,
  `QBITTORRENT_CONFIG_PATH`, `HEIMDALL_CONFIG_PATH` and `MINECRAFT_DATA_PATH`, and Dozzle's settings leave the named
  volume `dozzle-data`: `compose.yaml` declares no volumes any more. `DOWNLOADS_PATH` is unchanged.
  `scripts/restore.sh` writes each archive to what the service mounts at that container path now, creating a missing
  folder and recreating a container that predates `compose.yaml`, so older backups restore into the new folders.
- Docs: a warning never to point a path setting into `/var/lib/docker/volumes` or keep app data in named volumes:
  `docker volume prune`, `docker system prune --volumes` and Portainer's "remove unused volumes" delete any volume
  that no container mounts as a volume, even one whose `_data` folder a service bind-mounts
  ([docs/installing.md](docs/installing.md#where-data-lives)).

- Docs: the maintainer's server now follows `main` with a pull agent instead of running a release tag, so a merge
  deploys within about two minutes, Dependabot's automatic merges included. Rollback is a revert pull request; a
  server is held on a version by checking out that commit, which pauses the agent. Release tags stay as signed,
  verified snapshots ([docs/upgrading.md](docs/upgrading.md#following-main)).
- Dependabot's image rebuilds (the same tag moving to a new digest: a rebuild of the same app version, with newer
  base packages) now merge automatically once every required check passes, as on homelab-atlas. The rule merges only
  a pull request whose one changed file is `compose.yaml`, whose changed lines are all `image:` lines, and whose
  image tags stay the same.
- Prowlarr and Heimdall are pinned by their linuxserver.io `version-<app version>` tag (`version-2.6.5.5623`,
  `version-v2.8.3`) instead of the build tag (`2.6.5.5623-ls163`, `v2.8.3-ls366`). Dependabot reads a build tag's
  `-lsNNN` as a suffix that must match exactly, so it never proposed a new version or build of either; with the
  `version-` tag it proposes both. The digests are unchanged, so the images are exactly the ones pinned before.
  qBittorrent keeps its build tag while it is held at 4.5.5.
- Dependabot's major updates now merge automatically too, once every required check passes (owner 2026-10-14), so
  they deploy to the maintainer's server unattended. A major can migrate a service's data one way: the nightly
  backup and `scripts/restore.sh` are the way back, not a revert alone. An update Dependabot can't classify still
  waits for the maintainer; qBittorrent stays held and the Minecraft server's version is still set by hand.

### Fixed

- qBittorrent may keep 65536 files open again (`ulimits: nofile`). On a server whose Docker Engine uses
  containerd 2.x (Docker Engine 29's packages), containers start with a limit of 1024, which a torrent client with a
  few large torrents can run out of ("Too many open files"); containerd 1.7 gave about a million.
- `scripts/backup.sh` no longer leaves a service down when stopping it fails. A process that can't exit in time
  (stuck writing to a network share) made the stop fail while its container was still on its way down; the backup
  gave up, started the services again at once (Compose skipped the container, which still ran) and the service stayed
  stopped once it exited, as `restart: unless-stopped` doesn't restart after a stop. The rest of the backup and the
  copy off the host were never made. Now the backup waits up to `BACKUP_STOP_WAIT` seconds (default 120) for the
  container to exit and carries on; if it still runs then, the backup fails and waits once more before starting
  anything. Every service that was running when the backup began must be running again at the end, or the backup
  fails and names it (the scheduled backup reports that to the push monitor).
- qBittorrent gets a minute to stop (`stop_grace_period: 1m`) instead of Docker's 10 s, so it can finish writing to
  `/incomplete` and exit cleanly rather than be killed in the middle of a write. Deploying this recreates its
  container.
- `scripts/backup.sh` and `scripts/restore.sh` no longer race the pull agent. On a server whose agent deploys
  `main`, they first wait for a running deploy to finish (up to 30 minutes, then fail before stopping anything) and
  hold the agent's lock until they exit, so a merge that lands during the nightly backup can no longer recreate a
  service the backup has stopped for its copy, or one a restore is filling; it deploys once they're done. Without
  the agent (CI, a workstation, a server upgraded by hand) nothing changes. On such a server `flock` (util-linux)
  is now required.
- Docs: a deploy doesn't install changed systemd units; copy `deploy/systemd/` again and reload when they change
  ([docs/upgrading.md](docs/upgrading.md#following-main)). Leftover wording from before pull deploys corrected.


## [0.2.0] - 2026-10-14

### Added

- Label `org.honeybeartech.hyperion.backup.exclude`: comma-separated paths at any depth inside a service's data
  mount that `scripts/backup.sh` leaves out of the mount's archive and `scripts/restore.sh` leaves in place. A path
  outside every data mount, or with `..` or a pattern character, fails the backup and the restore before anything
  stops. No service uses it yet.
- Every backup has a `NETWORKS` file (the address range of each network the stack joins but doesn't create, so a
  rebuilt host can recreate it the same; this stack creates its own networks, so the file holds only its header)
  and a `VERSION` file (the checkout's `git describe`, the release the host ran). The smoke test checks both.
- The smoke test owns its throwaway data directories by `PUID`:`PGID` with mode 0755, as on the host, instead of
  making them writable by everyone, so a service that couldn't write its data on the host fails in CI too.
- `.gitlab-ci.yml`, for a copy of the repository on the maintainer's self-hosted GitLab: a scheduled job mirrors
  GitHub into it, and every commit there re-runs the checks that need no Docker daemon. It does nothing until
  that GitLab project, its `MIRROR_TOKEN` variable and the schedule exist.

### Changed

- The tooling (checker, backup scripts, smoke test, workflows) follows homelab-ares, the template for the homelab
  stacks; only what is specific to this host's services differs.
- A mount inside another mount is archived on its own and left out of the outer mount's archive, and a restore of
  the outer mount leaves it in place. No service here has one, and the `backup.skip` label (qBittorrent's
  `/downloads`) works as before: backups hold exactly the same data.
- CI logs in to Docker Hub with a read-only token, when the project has one, for its image pulls and the image
  scan, and logs out before the smoke test starts any container; without the token it pulls anonymously, as
  before.
- `scripts/scheduled-backup.sh` retries the Uptime Kuma push for two minutes instead of 25 seconds.

### Security

- Every service drops every Linux capability (`cap_drop: [ALL]`) and runs with `no-new-privileges`, and adds back
  only the capabilities its image needs, all from Docker's default set: Prowlarr `CHOWN SETUID SETGID KILL`,
  qBittorrent `CHOWN DAC_OVERRIDE SETUID SETGID KILL`, Heimdall `CHOWN DAC_OVERRIDE FOWNER SETUID SETGID KILL`,
  the Minecraft server `SETUID SETGID`; Dozzle, autoheal and the socket proxy none. Dozzle, the Minecraft server
  and autoheal also get a read-only root filesystem, as the socket proxy already had (Prowlarr, qBittorrent and
  Heimdall keep a writable one: their init doesn't start without it). Settings saved in Dozzle's UI now go to a
  named volume, `dozzle-data`, so they last when it's recreated and are in the backup. The table is in
  docs/security.md#hardening.
- The policy check enforces it: new rules `no-new-privileges` and `cap-drop`, and `cap-add` now fails only on a
  capability outside Docker's default set. New rule `devices` (from homelab-deimos): no host device mapped into a
  container (a GPU reservation under `deploy.resources` is allowed). No service maps one.

### Upgrading

- **Back up before deploying this release**, and watch each service's first start. The services were tested
  with fresh data only, so this is the first run on real data. A service without capabilities can't change or
  write files it doesn't own: data adopted from another installation must be owned by `PUID`:`PGID` (the
  linuxserver.io services and the Minecraft server). A service that fails with "permission denied" (`EACCES`) on
  its first start usually has data with an unexpected owner: fix the owner, or go back to the previous release.
- The systemd units in `deploy/systemd/` haven't changed (they already run the backup in the best-effort I/O
  class at the lowest priority), so they needn't be re-installed.

## [0.1.1] - 2026-10-13

### Fixed

- The Minecraft server accepts players again. Since Bedrock 1.26.50, clients connect only over NetherNet, and a
  `server.properties` from an older version still selected the previous transport, so the server logged
  "Players will not be able to connect". `compose.yaml` now sets `TRANSPORT: nethernet`, publishes TCP 19132 (the
  handshake) and UDP 19140–19149 (one gameplay port per player), and tells clients the address to use from the new
  required setting `MINECRAFT_ADDRESS`.

### Upgrading

- Set `MINECRAFT_ADDRESS` in `.env` to the address players reach this host at. UDP 19132 is no longer published;
  players add the server by address and port 19132, since LAN discovery doesn't cross Docker's network.

## [0.1.0] - 2026-10-13

The first release: the Hyperion stack as a Compose file, every image pinned by version tag and digest for
`linux/amd64` and the Minecraft server's version pinned too, with health checks, autoheal, scheduled backups
copied off the host, and release signing around it.

### Added

- Scheduled backups copied off the host: `scripts/scheduled-backup.sh` takes a backup, copies it to
  `BACKUP_REMOTE` with rsync (`SHA256SUMS` last, so a cut-off copy is refused on restore), keeps the newest
  `BACKUP_KEEP` (3) here and `BACKUP_REMOTE_KEEP` (30) there, and reports to an Uptime Kuma push monitor. Settings
  in the optional, gitignored `backup.env` (template `backup.env.example`); systemd user units in `deploy/systemd/`
  run it nightly at 04:30 ([docs/installing.md](docs/installing.md#scheduled-backups)). `scripts/backup.sh` stops
  one service at a time, only while it copies that service's data, and compresses the copy after starting the
  service again (with pigz when it's installed); the smoke test runs the scheduled backup against a stand-in
  backup server.
- `compose.yaml`: Prowlarr, qBittorrent, Heimdall, Dozzle (with optional remote agents), a Minecraft Bedrock
  server, and autoheal behind a filtering socket proxy. Every image is pinned as `name:tag@sha256:<digest>` for
  `linux/amd64`, the Minecraft server's version is pinned too, every service has a health check, and every
  service but autoheal carries the `autoheal` label. qBittorrent's downloads are excluded from backups. The
  Minecraft server runs as `PUID`:`PGID` with its allowlist on, and won't start until `MINECRAFT_EULA=TRUE`.
- `autoheal.env.example`: an optional webhook for autoheal's restart notices, kept in the gitignored
  `autoheal.env`.
- Image updates after the first scan: Dozzle `v11.3.2`, Heimdall `v2.8.3-ls366` and the Minecraft image
  `2026.10.0`; the first triage is recorded in `docs/dependencies.md`.
- Documentation: quick start, installing, upgrading, rebuilding, architecture, interfaces, security
  requirements, assurance case, dependencies, roadmap and verifying releases.
- `.env.example` with every setting the stack reads, and a `.gitignore` that keeps settings,
  service data, downloads, backups and keys out of the repository.
- Project policies (`SECURITY.md`, `CONTRIBUTING.md`, `GOVERNANCE.md`, `SUPPORT.md`, `CODE_OF_CONDUCT.md`),
  `CODEOWNERS`, issue and pull request templates.
- `scripts/check_compose.py`: the stack's policy check (every image pinned as `name:tag@sha256:<digest>`, no
  `latest`, no build, nothing privileged, no added capabilities, host network or PID namespace, no Docker
  socket mount, a health check on every service, unless a service's `org.honeybeartech.hyperion.allow.<rule>`
  label gives the reason), and the CycloneDX SBOM of the images for releases; tests with a 90 % branch-coverage
  floor.
- `scripts/backup.sh` and `scripts/restore.sh`: back up every service's read-write data mounts and the
  settings files with a manifest and checksums (readable only by the user who ran it), and restore them after
  verifying the checksums and asking first. Paths in a service's `org.honeybeartech.hyperion.backup.skip` label
  (qBittorrent's downloads, caches, logs) are never archived, and a restore refuses to write them.
  `scripts/smoke-test.sh` starts the stack with throwaway settings (accepting the Minecraft EULA for its run
  only), waits until every service is healthy, runs a backup and restore round trip, checks that excluded paths
  are left alone and that autoheal restarts an unhealthy container.
- CI on every change: ruff, yamllint, shellcheck, actionlint, gitleaks over the whole history, the checker's
  tests, the policy check and the smoke test on an amd64 runner. CodeQL,
  OpenSSF Scorecard, dependency review, a DCO check and a weekly image scan (Trivy, `linux/amd64`) also run.
- Dependabot for the images, the Python tools and the Actions; patch and minor updates merge automatically
  once every required check passes; major updates wait for the maintainer. qBittorrent stays on 4.5.5 until
  the server has moved to this stack.
- A release workflow that publishes a source archive, the SBOM, `SHA256SUMS` signed keylessly with cosign,
  and SLSA build provenance ([docs/verifying-releases.md](docs/verifying-releases.md)).

[Unreleased]: https://github.com/HoneyBearTech/homelab-hyperion/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/HoneyBearTech/homelab-hyperion/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/HoneyBearTech/homelab-hyperion/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/HoneyBearTech/homelab-hyperion/releases/tag/v0.1.0
