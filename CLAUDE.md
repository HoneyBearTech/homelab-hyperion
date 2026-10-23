# homelab-hyperion

The Docker Compose stack for Hyperion, the owner's homelab Ubuntu server (24.04, amd64, a VM, no GPU):
Prowlarr, qBittorrent, Heimdall, Dozzle, a Minecraft Bedrock server, Steerhouse (Ansible playbooks from a web UI,
with its Postgres), and autoheal behind a socket proxy, every
image pinned by tag and digest so the server can be upgraded and rebuilt from this repository. Hyperion runs the
stack from a checkout of `main` that a pull agent deploys (see Deploys below); its nightly backups go off the host.

## Before Making Structural Changes
Read the project's notes first. They live outside this repo, in the owner's Obsidian vault **Chronos** at
`~/Chronos/Projects/homelab-hyperion/` (every file is prefixed `homelab-hyperion-`):
- `homelab-hyperion-roadmap.md`: phases with checkboxes, the owner's open questions, the OpenSSF phase and the
  owner's manual GitHub steps
- `homelab-hyperion-Pass-Map.md`: pass-by-pass delivery log; add a row when a pass ships
- `homelab-hyperion-Architecture.md`: the host, which containers run there today and which belong in this repo,
  data flow, deployment shape, cutover plan
- `homelab-hyperion-Security-Considerations.md`: assets, threats, trust boundaries, checklist (Prowlarr holds
  every indexer credential, qBittorrent talks to the public BitTorrent swarm, Dozzle and autoheal reach the
  Docker API, and Steerhouse holds the SSH keys of the machines it manages: treat these notes as load-bearing)
- `homelab-hyperion-Decisions-Log.md`: ADR-style log (entries marked **Proposed** still need the owner's call)

Keep them current as work lands: tick roadmap checkboxes, add a Pass-Map row per pass, add dated
Decisions-Log entries. **The notes never go into this repo.** Chronos is versioned in its own private repo;
only commit or push it when the owner asks. The old in-repo vault path `.obsidian-docs/` stays gitignored.

The sibling repos `~/GitHub/homelab-ares`, `~/GitHub/homelab-atlas`, `~/GitHub/homelab-deimos` and
`~/GitHub/homelab-helios` follow the same pattern. **homelab-ares is the template for the homelab stacks**
(owner 2026-10-13): tooling that isn't specific to this host's services (checker, backup scripts, smoke test,
workflows) is kept the same as ares'; a change here that isn't about this host's services goes to ares too.
homelab-atlas is the reference for Dozzle and for autoheal behind a socket proxy.

## This repo is public
- No hostnames, IP addresses, internal or public domains, host paths, NFS exports, Portainer stack names,
  Minecraft world or gamer names, or personal email addresses in anything committed: code, compose, docs,
  examples, tests, commit messages. Host facts live only in the Chronos notes. Examples use placeholders
  (`/srv/config`, `/srv/downloads`, `example.com`, `homelab-hyperion_`).
- Commit as `31805425+HoneyBearTech@users.noreply.github.com` (set as this repo's `user.email`), with
  `git commit -s` for the DCO sign-off; commits and tags are SSH-signed.
- No secrets: the services' logins, Prowlarr's indexer credentials and API keys, qBittorrent's web UI password,
  Steerhouse's secrets and any autoheal webhook URL stay in their folders under `CONFIG_ROOT` on the host (or a
  gitignored `<service>.env`), never in `compose.yaml`, `.env` or the `*.example` files. A secret a service can only take from
  its environment gets its own gitignored `<service>.env` (`env_file`) with a committed `<service>.env.example`.
  `.gitignore` covers `.env`, keys, certificates, `appdata/`, `data/`, `media/`, `downloads/`, `backups/`; extend it
  rather than work around it.
- Keep the repo on track for OpenSSF Baseline Levels 1 and 2 and the Best Practices Passing and Silver
  badges (project 15292). If a change would break a met criterion (for example unpinning an image or an
  Action, adding a workflow without `permissions:`, or dropping the coverage floor), say so before making it.

## Rules for the stack
- **Every image is pinned as `name:tag@sha256:<digest>`.** Never `latest`, never tag-only (autoheal is the
  documented `allow.latest` exception, as on atlas). Dependabot (`docker-compose` ecosystem) updates tag and digest
  together. linuxserver.io images use their `version-<app version>` tag (socket-proxy its bare version), never the
  `-lsNNN` build tag: Dependabot can't follow those. qBittorrent's (`version-5.3.0_v2.1.2`) also names its libtorrent,
  so Dependabot only proposes its rebuilds (see the qBittorrent rule below). Patch, minor
  and major updates, and image rebuilds (same tag, new digest), auto-merge once the required checks pass (owner
  2026-10-14); only an update Dependabot can't classify waits for the owner. Every merge deploys, the automatic
  ones included (see Deploys), so a major that migrates data one way reaches the server unattended: the nightly
  backup plus a revert pull request are the way back (restore from the backup to undo a migration).
- **The Minecraft server version is pinned too.** The Bedrock image downloads the server itself on start; its
  `VERSION` is set in `compose.yaml` (never `LATEST`, never from `.env`), so a new version is a reviewed change
  (worlds upgrade one way). Dependabot doesn't see it: bump it by hand.
- **Amd64, no GPU.** Every image must publish `linux/amd64`. The smoke test runs on `ubuntu-24.04` and the image
  scan scans `linux/amd64`.
- **Downloads are never backed up, restored or deleted by this repo's scripts.** A service lists such paths in
  its `org.honeybeartech.hyperion.backup.skip` label (comma-separated container paths); `backup.sh` skips them,
  `restore.sh` refuses to write them, and the smoke test checks both. qBittorrent's must list `/downloads` and `/incomplete`.
  Paths inside a mount that a service's `org.honeybeartech.hyperion.backup.exclude` label lists are left out of
  its archive and left in place by a restore (no service uses it yet); a mount inside another mount is archived
  on its own. Each backup also writes `NETWORKS` and `VERSION`. Keep it that way when adding a service.
- **No privileged containers, added capabilities, host network/PID, Docker socket mounts or device mappings**
  unless the service carries `org.honeybeartech.hyperion.allow.<rule>: "<reason>"` and the owner agreed. Only
  Dozzle (read-only) and the socket proxy may have the socket; autoheal reaches Docker only through the proxy.
  The exceptions in use: `allow.docker-socket` (Dozzle, socket-proxy), `allow.latest` (autoheal) and
  `allow.cap-add` (steerhouse-worker: `NET_ADMIN` for Steerhouse's egress filter, owner 2026-10-22).
- **Every service is hardened** (`x-hardened`: `security_opt: [no-new-privileges:true]`, `cap_drop: [ALL]`) and
  adds back only the capabilities its image needs, all from Docker's default set, each with a comment saying why
  and proven by the smoke test (docs/security.md#hardening). A capability outside the default set needs
  `allow.cap-add` and the owner's agreement. `scripts/check_compose.py` enforces all of this in CI and in the
  release workflow. Read-only root filesystems (`read_only: true` + `tmpfs` only, no image-specific env flags) for
  Dozzle, Minecraft, autoheal, the socket proxy and Steerhouse's API, worker and database; the linuxserver.io (s6)
  images stay writable (their init runs from `/run`, and a tmpfs there is noexec), and so does Steerhouse's web UI
  (its entrypoint writes the trusted-proxy config into `/etc/nginx/conf.d`). Keep it that way when adding a service.
- **Steerhouse is security-critical** (hosted here, not on Ares, because its images are amd64 only; owner
  2026-10-22): it stores the SSH keys and vault passwords of the machines it manages. Its secrets are Docker secret
  files in `CONFIG_ROOT/steerhouse/secrets` (never in the repo, `.env` or the backups; `credential_encryption_key`
  lives in the owner's password manager), its tokens (`WORKER_TOKEN`, `METRICS_TOKEN`) in `steerhouse.env`. Only the
  database and the API get secrets; the worker gets none and only the `steerhouse-workers` network. For Argus (on
  Ares; owner 2026-10-22) the API's metrics port is published (token-protected) and so is Postgres, **TLS only**:
  `pg_hba` (`PG_HBA` in compose) admits remote logins for the read-only role `grafana_ro` over `hostssl` only, the
  app's user `steerhouse` only from `steerhouse-db` (fixed range `STEERHOUSE_DB_SUBNET`), and rejects everything
  else; the certificate is from the owner's own CA (`scripts/steerhouse.sh`). Never loosen that, and never give
  another role remote access. The smoke test proves it (`scripts/smoke-stack.sh`). PostgreSQL majors are ignored by
  Dependabot (a major can't open the old data): a hand-made PR with a dump and restore.
- **Nightly backups as on ares and helios** (owner 2026-10-13): `scripts/scheduled-backup.sh` from a systemd user
  timer at 04:30, rsync to the backup server (keep 3 here, 30 there), Uptime Kuma push. `backup.sh` stops one
  service at a time. The backup server's name lives only in the host's `~/.ssh/config` and `backup.env`, never here.
- **Every service has a health check** and the `autoheal: "true"` label (autoheal itself excepted, as on atlas).
- **qBittorrent's hold was lifted** (owner 2026-10-22; it was held at 4.5.5 from 2026-10-14): it runs 5.3.0 on
  libtorrent 2.1, and Dependabot no longer ignores it. Its downloads may be on a network share, so it must never
  memory-map them: keep a build on libtorrent 2.1 or newer (its tag names the libtorrent; pread/pwrite disk I/O by
  default) and never pin a floating tag (`5.3.0`, `latest`, `libtorrentv1`), whose rebuilds can change the
  libtorrent unattended. Dependabot can't read `version-<qBittorrent>_v<libtorrent>` as a version, so it proposes
  only rebuilds of the pinned tag; a new qBittorrent version is a pull request by hand: read its release notes (its
  settings can migrate one way), check the libtorrent version, back up first. The disk I/O type is a qBittorrent
  setting (Advanced → Disk IO type: Default or Pread/pwrite), not something compose can set.
- **Never change the live server** (Hyperion) without the owner asking: merges only as **Merging** says, no
  `docker compose up`, no edits to service data, qBittorrent torrents, Prowlarr indexers, Minecraft worlds, or
  Portainer stacks. Read-only inspection (`docker ps`, `docker inspect`) only when asked.
- Every setting goes through `.env` (`${VAR:?…}` in compose when required) and is listed in `.env.example`
  and `docs/interfaces.md` (`tests/test_settings.py` checks both).
- **App data layout (owner's decision 2026-10-15, the same in all five homelab stacks):** one required setting,
  `CONFIG_ROOT` (example `/srv/config`; the owner's hosts use their home directory). Each app's settings and
  database live in `${CONFIG_ROOT:?set CONFIG_ROOT in .env}/<app>/config`, mounted at the app's data path; any other
  per-app host folder sits beside it as `${CONFIG_ROOT}/<app>/<purpose>` (cache, logs, scripts…). `<app>` is the
  lowercase service name. No per-app path settings, no named Docker volumes for app data (`tests/test_settings.py`).
  Downloads stay on `DOWNLOADS_PATH` (incomplete torrents on `INCOMPLETE_PATH`). Dozzle's folder is owned by root (it runs as root, no capabilities); the
  others by `PUID:PGID`.
- **Never point a path setting into `/var/lib/docker/volumes`, and never keep app data in named Docker volumes.**
  `docker volume prune`, `docker system prune --volumes` and Portainer's "remove unused volumes" delete every volume
  no container mounts *as a volume*, including one whose `_data` folder a service bind-mounts by path: that is how a
  prune deleted two apps' data in this homelab (2026-10-15). Keep app data under `CONFIG_ROOT`; the warning is in
  `docs/installing.md#where-data-lives`, and it stays there.
- **Container paths and ports are load-bearing**: Sonarr, Radarr and Lidarr on another host reach Prowlarr and
  qBittorrent by their published ports, qBittorrent's saved torrents record their download paths, and players
  reach the Minecraft server on TCP 19132 and UDP 19140–19149 (NetherNet). Adopt the existing data and keep
  paths and ports the same; see the cutover plan in Chronos.

## Deploys (owner's decision 2026-10-14)
- **A merge to `main` deploys.** A pull agent on Hyperion (systemd user timer `homelab-pull@hyperion`, from the
  owner's private homelab-ops repo; rolled out host by host, see Chronos) fetches `main` about every 90 s. When it
  moved, the agent fast-forwards the checkout and runs `docker compose config --quiet`, `docker compose pull` and
  `docker compose up -d --remove-orphans --wait`: a merge is live within about two minutes. It refuses local changes
  and non-fast-forward history, and moves the checkout back if config or pull fails.
- **Rollback is a revert PR**, deployed the same way. A revert doesn't undo a data migration: then the backup and
  `scripts/restore.sh` are the way back, with the owner.
- **Pinning by hand**: the owner checks out another commit or tag on the host; the agent pauses until the checkout
  is on `main` again. Release tags stay as signed, verified snapshots; they no longer drive deploys.
- **Backups and restores hold the agent's lock** (`deploy_lock` in `scripts/lib.sh`, 2026-10-14): `flock` on the
  agent's `<state dir>/hyperion/lock`, waiting up to 30 min for a deploy; a no-op where that state dir doesn't
  exist (CI, the Mac). The agent skips its runs while it's held. `pull_stack` is the only stack-specific line: keep
  the function text the same as ares'. Tests: `tests/test_deploy_lock.py` (the flock ones skip on macOS).
- **The agent never installs systemd units**: a change to `deploy/systemd/` needs a manual copy +
  `systemctl --user daemon-reload` on the host (say so in the PR).

## Stack
- Docker Compose v2 (`compose.yaml`), upstream images: Prowlarr, qBittorrent, Heimdall
  (linuxserver.io), Dozzle, the Minecraft Bedrock server (`itzg/minecraft-bedrock-server`), Steerhouse
  (`honeybeartech/steerhouse-backend` and `-frontend`, amd64 only, with `postgres`), autoheal, a socket
  proxy. Not in this repo: Plex, Tdarr, the Argus agent, the Portainer agent, the local Portainer server (to be
  retired).
- Tooling (from homelab-ares, the template): `scripts/check_compose.py` (Python, standard library only:
  policy check + CycloneDX SBOM), `scripts/backup.sh`, `restore.sh`, `scheduled-backup.sh`, `smoke-test.sh`,
  `lib.sh` (bash, must run on macOS' bash 3.2; `scheduled-backup.sh` also with macOS' openrsync, so no
  `--chmod`); ruff (`select = ["ALL"]`), yamllint, shellcheck, pytest + coverage (90 % branch floor), pip-tools
  for the hash-pinned `requirements-dev.txt`. CI-only: actionlint, gitleaks, CodeQL, Scorecard, dependency
  review, DCO, Trivy image scan, Dependabot auto-merge (patch/minor/major, rebuilds). CI logs in to Docker Hub with
  the read-only `DOCKERHUB_USERNAME`/`DOCKERHUB_TOKEN` secrets when they exist (owner 2026-10-13; Actions and
  Dependabot secrets in place, anonymous fallback for fork PRs) and logs out before the smoke test starts any
  container.
- This stack's own scripts (not in ares): `scripts/steerhouse.sh` (Steerhouse's secrets, `steerhouse.env`, CA and
  database certificate, the `grafana_ro` role) and `scripts/smoke-stack.sh` (the smoke test's stack-specific steps:
  `smoke_prepare` and `smoke_check`). The hooks that call it, the `*_SUBNET` setting rule, `user: PUID:PGID` folders
  and skipping services with Docker secrets in the restore's "moved" check are generic `smoke-test.sh` changes
  (2026-10-22) still to be ported to ares.
- GitLab copy: the owner's self-hosted GitLab (CE, LAN only; host facts in Chronos) is to hold a mirror. GitHub
  stays the home (OpenSSF badges, Scorecard, Dependabot, releases); every change goes to GitHub as a PR, never to
  GitLab. `.gitlab-ci.yml` mirrors GitHub on a schedule (fast-forward only, `MIRROR_TOKEN` CI/CD variable) and
  re-runs the daemon-free checks; the smoke test stays GitHub-only, as on homelab-ares. The owner still has to
  create the GitLab project, the `MIRROR_TOKEN` variable and the schedule; until then the file does nothing.
- Releases (`release.yml`, on a `v*.*.*` tag; it refuses to run without `compose.yaml`): policy check, source
  archive, CycloneDX SBOM, `SHA256SUMS` signed with cosign keyless, SLSA provenance, GitHub Release from the
  tag's `CHANGELOG.md` section. No images are built or published.

## Conventions
- `CHANGELOG.md` (Keep a Changelog): add to "Unreleased" with every user-visible change.
- Docs in `docs/` change in the same PR as the behaviour; anything not built yet is marked **Planned**.
- Workflows: top-level `permissions: contents: read` (Scorecard: `read-all`), raise per job; actions pinned by
  full SHA with a version comment; untrusted `${{ github.event.* }}` only through `env:`.
- Required checks in the `main` ruleset (once the owner sets it up): `CI / Checks + tests`,
  `CI / Stack smoke test`, DCO sign-off, Dependency review, CodeQL's Analyze (python) / Analyze (actions). Don't
  rename those jobs.
- **Merging (owner's decision 2026-10-14):** Claude opens a PR for every change. A merge deploys (see Deploys),
  so Claude merges once every required check is green (the owner's standing permission, 2026-10-14) and
  then says that it merged and that it's deploying to Hyperion. It asks first when the deploy needs something on
  the server (a new `.env` setting, a data migration without a recent good backup, an update this file says
  waits for the owner) or the server isn't healthy, and never turns on auto-merge (`gh pr merge --auto`)
  without the owner's OK. Never bypass a check or the ruleset.
  Dependabot's patch, minor and major updates and image rebuilds auto-merge through `dependabot-auto-merge.yml`
  once every required check passes (majors since 2026-10-14), so they deploy unattended; an update Dependabot can't
  classify waits for the owner. Claude never merges a major update itself: majors are merged only by Dependabot's
  auto-merge or by the owner. Keeping that auto-merge is the owner's call: don't change
  `dependabot-auto-merge.yml` without it.

## Commands
```sh
make test     # checker tests + coverage floor (no Docker, no network)
make lint     # ruff check, ruff format --check, yamllint --strict, shellcheck -x
make check    # docker compose config --format json | scripts/check_compose.py  (needs .env and compose.yaml)
make smoke    # scripts/smoke-test.sh: throwaway project, healthy, backup/restore round trip, scheduled backup
              # (needs Docker)
make config   # docker compose config (resolved file)
```
Release (only when the owner asks): as in homelab-ares' CLAUDE.md: CHANGELOG section in a PR, then a signed
tag (`git tag -s vX.Y.Z`) checked against `.github/allowed_signers`, pushed; verify from outside afterwards.
