# Changelog

All notable changes to homelab-hyperion are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

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

[Unreleased]: https://github.com/HoneyBearTech/homelab-hyperion/commits/main
