# Changelog

All notable changes to homelab-hyperion are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
  Heimdall keep a writable one: their init doesn't start without it). Settings saved in Dozzle's UI now last until
  it restarts rather than until it's recreated. The table is in docs/security.md#hardening.
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

[Unreleased]: https://github.com/HoneyBearTech/homelab-hyperion/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/HoneyBearTech/homelab-hyperion/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/HoneyBearTech/homelab-hyperion/releases/tag/v0.1.0
