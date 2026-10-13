# homelab-hyperion

The Docker Compose stack for Hyperion, the owner's homelab Ubuntu server (24.04, amd64, a VM, no GPU):
Prowlarr, qBittorrent, Heimdall, Dozzle, a Minecraft Bedrock server, and autoheal behind a socket proxy, every
image pinned by tag and digest so the server can be upgraded and rebuilt from this repository. Hyperion runs the
stack from a checkout of a release tag (cut over 2026-10-13); its nightly backups go off the host. Deploying a
release: `git fetch --tags && git checkout vX.Y.Z && docker compose up -d`, only when the owner asks.

## Before Making Structural Changes
Read the project's notes first. They live outside this repo, in the owner's Obsidian vault **Chronos** at
`~/Chronos/Projects/homelab-hyperion/` (every file is prefixed `homelab-hyperion-`):
- `homelab-hyperion-roadmap.md`: phases with checkboxes, the owner's open questions, the OpenSSF phase and the
  owner's manual GitHub steps
- `homelab-hyperion-Pass-Map.md`: pass-by-pass delivery log; add a row when a pass ships
- `homelab-hyperion-Architecture.md`: the host, which containers run there today and which belong in this repo,
  data flow, deployment shape, cutover plan
- `homelab-hyperion-Security-Considerations.md`: assets, threats, trust boundaries, checklist (Prowlarr holds
  every indexer credential, qBittorrent talks to the public BitTorrent swarm, and Dozzle and autoheal reach the
  Docker API: treat these notes as load-bearing)
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
  (`/srv/appdata`, `/srv/downloads`, `example.com`, `homelab-hyperion_`).
- Commit as `31805425+HoneyBearTech@users.noreply.github.com` (set as this repo's `user.email`), with
  `git commit -s` for the DCO sign-off; commits and tags are SSH-signed.
- No secrets: the services' logins, Prowlarr's indexer credentials and API keys, qBittorrent's web UI password,
  and any autoheal webhook URL stay in their data on the host (or a gitignored `<service>.env`), never in
  `compose.yaml`, `.env` or the `*.example` files. A secret a service can only take from its environment gets its
  own gitignored `<service>.env` (`env_file`) with a committed `<service>.env.example`. `.gitignore` covers
  `.env`, keys, certificates, `appdata/`, `data/`, `media/`, `downloads/`, `backups/`; extend it rather than work
  around it.
- Keep the repo on track for OpenSSF Baseline Levels 1 and 2 and the Best Practices Passing and Silver
  badges (project 15292). If a change would break a met criterion (for example unpinning an image or an
  Action, adding a workflow without `permissions:`, or dropping the coverage floor), say so before making it.

## Rules for the stack
- **Every image is pinned as `name:tag@sha256:<digest>`.** Never `latest`, never tag-only (autoheal is the
  documented `allow.latest` exception, as on atlas). Dependabot (`docker-compose` ecosystem) updates tag and
  digest together. Patch and minor updates auto-merge once the required checks pass; major updates wait for the
  owner. A merge never deploys: Hyperion changes only on a deliberate pull.
- **The Minecraft server version is pinned too.** The Bedrock image downloads the server itself on start; its
  `VERSION` is set in `compose.yaml` (never `LATEST`, never from `.env`), so a new version is a reviewed change
  (worlds upgrade one way). Dependabot doesn't see it: bump it by hand.
- **Amd64, no GPU.** Every image must publish `linux/amd64`. The smoke test runs on `ubuntu-24.04` and the image
  scan scans `linux/amd64`.
- **Downloads are never backed up, restored or deleted by this repo's scripts.** A service lists such paths in
  its `org.honeybeartech.hyperion.backup.skip` label (comma-separated container paths); `backup.sh` skips them,
  `restore.sh` refuses to write them, and the smoke test checks both. qBittorrent's must list `/downloads`.
  Paths inside a mount that a service's `org.honeybeartech.hyperion.backup.exclude` label lists are left out of
  its archive and left in place by a restore (no service uses it yet); a mount inside another mount is archived
  on its own. Each backup also writes `NETWORKS` and `VERSION`. Keep it that way when adding a service.
- **No privileged containers, added capabilities, host network/PID, Docker socket mounts or device mappings**
  unless the service carries `org.honeybeartech.hyperion.allow.<rule>: "<reason>"` and the owner agreed. Only
  Dozzle (read-only) and the socket proxy may have the socket; autoheal reaches Docker only through the proxy.
- **Every service is hardened** (`x-hardened`: `security_opt: [no-new-privileges:true]`, `cap_drop: [ALL]`) and
  adds back only the capabilities its image needs, all from Docker's default set, each with a comment saying why
  and proven by the smoke test (docs/security.md#hardening). A capability outside the default set needs
  `allow.cap-add` and the owner's agreement. `scripts/check_compose.py` enforces all of this in CI and in the
  release workflow.
- **Nightly backups as on ares and helios** (owner 2026-10-13): `scripts/scheduled-backup.sh` from a systemd user
  timer at 04:30, rsync to the backup server (keep 3 here, 30 there), Uptime Kuma push. `backup.sh` stops one
  service at a time. The backup server's name lives only in the host's `~/.ssh/config` and `backup.env`, never here.
- **Every service has a health check** and the `autoheal: "true"` label (autoheal itself excepted, as on atlas).
- **qBittorrent stays on 4.5.5** until after the cutover (Dependabot ignores it); the 5.x upgrade is its own PR,
  backup first, and removes the ignore entry.
- **Never change the live server** (Hyperion) without the owner asking: no `docker compose up`, no edits to
  service data, qBittorrent torrents, Prowlarr indexers, Minecraft worlds, or Portainer stacks. Read-only
  inspection (`docker ps`, `docker inspect`) only when asked.
- Every setting goes through `.env` (`${VAR:?…}` in compose when required) and is listed in `.env.example`
  and `docs/interfaces.md`.
- **Container paths and ports are load-bearing**: Sonarr, Radarr and Lidarr on another host reach Prowlarr and
  qBittorrent by their published ports, qBittorrent's saved torrents record their download paths, and players
  reach the Minecraft server on TCP 19132 and UDP 19140–19149 (NetherNet). Adopt the existing data and keep
  paths and ports the same; see the cutover plan in Chronos.

## Stack
- Docker Compose v2 (`compose.yaml`), upstream images: Prowlarr, qBittorrent, Heimdall
  (linuxserver.io), Dozzle, the Minecraft Bedrock server (`itzg/minecraft-bedrock-server`), autoheal, a socket
  proxy. Not in this repo: Plex, Tdarr, the Argus agent, the Portainer agent, the local Portainer server (to be
  retired).
- Tooling (from homelab-ares, the template): `scripts/check_compose.py` (Python, standard library only:
  policy check + CycloneDX SBOM), `scripts/backup.sh`, `restore.sh`, `scheduled-backup.sh`, `smoke-test.sh`,
  `lib.sh` (bash, must run on macOS' bash 3.2; `scheduled-backup.sh` also with macOS' openrsync, so no
  `--chmod`); ruff (`select = ["ALL"]`), yamllint, shellcheck, pytest + coverage (90 % branch floor), pip-tools
  for the hash-pinned `requirements-dev.txt`. CI-only: actionlint, gitleaks, CodeQL, Scorecard, dependency
  review, DCO, Trivy image scan, Dependabot auto-merge (patch/minor). CI logs in to Docker Hub with the
  read-only `DOCKERHUB_USERNAME`/`DOCKERHUB_TOKEN` secrets when they exist (owner 2026-10-13; not created yet, so
  it pulls anonymously) and logs out before the smoke test starts any container.
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
- Claude opens a PR for every change and may turn on auto-merge for it (`gh pr merge --auto --squash`), as on
  the sibling repos. Never bypass a check or the ruleset.

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
