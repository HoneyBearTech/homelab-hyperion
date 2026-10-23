# Changelog

All notable changes to homelab-hyperion are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Upgrading

- **Steerhouse needs its secrets, tokens, certificate and settings on the host before this is deployed**
  ([installing.md](docs/installing.md#steerhouse)). As the `PUID` user, in the checkout: create
  `CONFIG_ROOT/steerhouse/config` and `CONFIG_ROOT/steerhouse-postgres/config`, run `scripts/steerhouse.sh secrets
  "$CONFIG_ROOT/steerhouse/secrets"` and `scripts/steerhouse.sh env steerhouse.env`, issue the database's
  certificate (`scripts/steerhouse.sh ca` once, then `scripts/steerhouse.sh cert`), and save
  `credential_encryption_key` in a password manager. Add the six `STEERHOUSE_*` settings to `.env` last: a deploy
  without them stops at `docker compose config` and changes nothing. After the deploy, run
  `scripts/steerhouse.sh grafana-role` and add the reverse proxy host.

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
- **qBittorrent 4.5.5 → 5.3.0.** qBittorrent rewrites its settings for 5.x the first time it starts, and 4.5.5
  can't read them back, so:
  1. **Back up first** (`scripts/backup.sh`, [docs/upgrading.md](docs/upgrading.md#backing-up)) and copy the backup
     off the host. It holds qBittorrent's settings and torrent list (`CONFIG_ROOT/qbittorrent/config`). The
     downloads (`DOWNLOADS_PATH`, `INCOMPLETE_PATH`) are never in a backup, by design, and the upgrade doesn't touch
     them.
  2. **Pause the torrents that are downloading** just before the deploy (in the web UI: the Downloading filter,
     select all, Pause), so nothing is half-written to `/incomplete` when the container is recreated. Seeding
     torrents can stay as they are: qBittorrent saves their state when it stops (it has a minute,
     `stop_grace_period`). A force-started torrent that you pause and start again is no longer forced.
  3. **Deploy.** On the first start, qBittorrent 5.3.0 moves these settings to new keys in `qBittorrent.conf` and
     removes the old ones: the web UI's login (user name and password), port, address, IP-subnet whitelist, server
     domains, host-header validation, reverse-proxy, HTTPS and security settings (from `[Preferences]`
     `WebUI\…` to a `[WebUI]` section), "add torrents paused" (now "add torrents stopped"), the proxy, the action
     when a share limit is reached, and the .torrent export folders (now "backup" folders). The torrent list,
     categories, tags, save paths, `/incomplete` and the listening port stay as they are; no torrent is rechecked.
     A password you set keeps working (tested with settings made by 4.5.5). 5.x calls pausing and resuming
     "stopping" and "starting": start the torrents you paused.
  4. **Right after the deploy, set qBittorrent's disk I/O:** Settings → Advanced → "Disk IO type (requires
     restart)" → **Pread/pwrite**, then Save. This build's libtorrent (2.1) reads and writes files with
     `pread`/`pwrite`, which is also what "Default" means here; 4.5.5's libtorrent (2.0) mapped the files into
     memory instead, which suits a network share badly (the share's page cache counts as qBittorrent's memory, and
     every page fault waits on the network). If the setting showed anything other than "Default", restart
     qBittorrent after saving (`docker compose restart qbittorrent`). Never choose "Memory mapped files" while the
     downloads are on a network share. This setting lives in qBittorrent's settings, not in `compose.yaml`
     ([docs/installing.md](docs/installing.md#downloads-on-a-network-share)).
  5. **Check:** you can sign in; every torrent is listed with its category and save path, and none shows "Missing
     files" or "Errored"; Settings → Downloads still names `/downloads` and `/incomplete`; Settings → WebUI still has
     your subnet whitelist, server domains and reverse-proxy settings; each media app's download client test passes
     and a new download starts.
- **What changes for the web UI and the media apps.** The listening port is now set from `TORRENTING_PORT` (6881)
  on every start; the 4.5.5 image ignored that variable and used the port in qBittorrent's settings. qBittorrent
  5.x has no default password any more: if none was ever set, it prints a temporary one for `admin` in its log on
  every start (`docker compose logs qbittorrent`) until you set one; a password already set is kept. "Server
  domains" now matches whole host names (`example.com` no longer matches `qbt.example.com`: list it, or use
  `*.example.com`). Behind a reverse proxy, the client address now comes from the nearest hop that isn't in
  "Trusted proxies list" (a fix for a whitelist bypass through a spoofed `X-Forwarded-For`), so list every proxy
  between the clients and qBittorrent there. The web UI keeps at most 15 sessions, signing out the oldest. Sonarr,
  Radarr and Lidarr support qBittorrent 5's Web API (v2.16) in their current releases; older ones don't know that
  pausing became stopping.
- **Rolling back qBittorrent means restoring its settings from the backup, not only the image.** qBittorrent 4.5.5
  starts on the migrated settings, with its torrents and categories, but finds none of the moved ones and falls
  back to its defaults (tested): the user name and password become 4.5.5's old default login `admin`/`adminadmin`,
  the subnet whitelist and the reverse-proxy settings are gone, and host-header validation is back on, which turns
  away requests that reach the web UI through a remapped port (8090 → 8080 here) with `401 Unauthorized`. On a
  server that follows `main`, so that 4.5.5 never runs on the migrated settings: check out the commit before the
  upgrade on the server (the pull agent pauses), run `scripts/restore.sh backups/<date>-<time> qbittorrent` (it
  stops qBittorrent, recreates it with 4.5.5, puts back `CONFIG_ROOT/qbittorrent/config` and starts it), merge a
  revert pull request, then `git switch main`. Torrents added after the backup drop out of the list; their files
  stay in the downloads directories.

### Added

-- Steerhouse 0.10.1 (Ansible playbooks from a web UI): its API (`steerhouse`), workers (`steerhouse-worker`), web
  UI (`steerhouse-frontend`, on `STEERHOUSE_PORT`, for the reverse proxy) and PostgreSQL 18.6
  (`steerhouse-postgres`), from Steerhouse's own deploy files without its `monitoring` profile. Data in
  `CONFIG_ROOT/steerhouse/config` and `CONFIG_ROOT/steerhouse-postgres/config` (backed up, the database stopped while
  it's copied); secrets as Docker secret files in `CONFIG_ROOT/steerhouse/secrets` (never backed up) and tokens in
  the new `steerhouse.env` (template `steerhouse.env.example`). Six new required settings: `STEERHOUSE_PORT`,
  `STEERHOUSE_PUBLIC_URL`, `STEERHOUSE_TRUSTED_PROXIES`, `STEERHOUSE_METRICS_PORT`, `STEERHOUSE_POSTGRES_PORT`,
  `STEERHOUSE_DB_SUBNET`.
- For Argus: Steerhouse's Prometheus metrics on `STEERHOUSE_METRICS_PORT` (with `METRICS_TOKEN`), and its database on
  `STEERHOUSE_POSTGRES_PORT` for Grafana's read-only role `grafana_ro` (the `analytics` views), TLS 1.3 only, with a
  certificate from your own CA.
- `scripts/steerhouse.sh`: writes Steerhouse's secret files, `steerhouse.env`, a CA and the database's certificate
  (never replacing a file), and creates `grafana_ro` with Steerhouse's own setup command.
- The smoke test runs a stack's own steps from `scripts/smoke-stack.sh`: here Steerhouse's throwaway secrets and
  certificate, and checks that `grafana_ro` reads the `analytics` views over TLS and nothing else, that connections
  without TLS and every other remote login are refused, that the metrics need the token and that the worker is
  ready, before and after the restore. It also gives a `*_SUBNET` setting a free address range, makes the folder of
  a service that runs as `user: PUID:PGID`, and leaves services with Docker secrets out of the restore's
  recreated-container check.

 qBittorrent mounts `INCOMPLETE_PATH` at `/incomplete` for torrents still downloading ("Keep incomplete torrents
  in"). Like `/downloads`, it is in qBittorrent's `backup.skip` label: never backed up, never written by a restore.

### Changed

- qBittorrent 5.3.0 replaces 4.5.5 (the maintainer lifted the hold on qBittorrent on 2026-10-22), as linuxserver.io's
  `version-5.3.0_v2.1.2` tag (build `5.3.0_v2.1.2-ls484`, libtorrent 2.1.2), with the same capabilities, ports,
  paths, limits and health check. libtorrent 2.1 reads and writes the files with `pread`/`pwrite` instead of mapping
  them into memory, which suits downloads on a network share. Dependabot no longer ignores qBittorrent, but it can't
  read this tag as a version (the `_v2.1.2` names the libtorrent): it proposes the tag's rebuilds, which merge by
  themselves like the other images', and a new qBittorrent version is bumped by hand, after its release notes and a
  check that the build still uses libtorrent 2.1 or newer
  ([docs/dependencies.md](docs/dependencies.md#qbittorrent)). linuxserver.io's first builds of 5.3.0, on
  2026-10-20 and 2026-10-21, used libtorrent 2.0 on both its main and its libtorrent 1.2 lines for some hours, and
  the floating tags (`5.3.0`, `latest`, `libtorrentv1`) follow every build: pinned to one of those, a rebuild could
  bring memory-mapped I/O back unattended.
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
  qBittorrent moves to its `version-` tag with its upgrade to 5.3.0 (above).
- Dependabot's major updates now merge automatically too, once every required check passes (owner 2026-10-14), so
  they deploy to the maintainer's server unattended. A major can migrate a service's data one way: the nightly
  backup and `scripts/restore.sh` are the way back, not a revert alone. An update Dependabot can't classify still
  waits for the maintainer; the Minecraft server's version is still set by hand, and so is a new qBittorrent
  version (above).

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

### Security

-- Steerhouse's worker keeps the `NET_ADMIN` capability (label `org.honeybeartech.hyperion.allow.cap-add`; the
  maintainer agreed on 2026-10-22) for its egress filter, which keeps playbook runs from reaching Steerhouse's API and
  cloud metadata. Every other Steerhouse service drops all capabilities; the API, workers and database have
  read-only root filesystems and the API and database run as `PUID`:`PGID`. The database's `pg_hba.conf` admits its
  own user only from its internal network and, from anywhere else, only `grafana_ro` over TLS. Dependabot ignores
  PostgreSQL majors, which can't open the old data.

 qBittorrent 5.3.0 fixes all 173 image-scan alerts on qBittorrent 4.5.5 (8 of them critical), most in its 2023
  Alpine packages (OpenSSL 3.1.3, expat, Python), and qBittorrent's own CVE-2024-51774 (before 5.0.1 it kept using an
  HTTPS connection whose certificate failed validation). A scan of the new image with the weekly scan's settings
  (Trivy, `linux/amd64`, HIGH and CRITICAL with a fix) finds nothing. qBittorrent 5.x also brings upstream's later
  security fixes, among them a bypass of the web UI's IP-subnet whitelist through a spoofed `X-Forwarded-For`
  header and SMTP header injection in notification mails (5.3.0).
- Dozzle `v11.3.4` (was `v11.3.2`): built with Go 1.27.3, which fixes CVE-2026-111943 in `crypto/x509`, Dozzle's
  one image-scan finding. Deploying this recreates Dozzle, which then reconnects to its agents.
- The image scan's findings are triaged again (352 alerts on 2026-10-22, 18 critical): every critical one in
  qBittorrent 4.5.5 turns out not to apply to this image, and Prowlarr's two critical ASP.NET Core findings wait
  for a Prowlarr release on a patched .NET runtime
  ([docs/dependencies.md](docs/dependencies.md#current-findings)).


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
