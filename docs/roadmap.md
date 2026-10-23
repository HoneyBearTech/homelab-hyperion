# Roadmap

Where homelab-hyperion is going over roughly the next twelve months (from October 2026). Plans change; this
file changes with them, in the same pull request.

## Now: the stack in git

- Done: the checks, backup and restore scripts, smoke test, release signing and project policies, ported from
  the sibling homelab stacks (backups skip the downloads directory).
- Done: `compose.yaml` with Prowlarr, qBittorrent, Heimdall, Dozzle, the Minecraft Bedrock server, and autoheal
  behind a socket proxy, every image pinned by tag and digest for `linux/amd64` and the Minecraft server's
  version pinned too, a health check on every service, Dependabot proposing updates; the smoke test (including
  an autoheal restart) and the image scan run against it in CI.
- Done: the first image scan, triaged ([dependencies.md](dependencies.md#current-findings)).
- Done: the first release, 0.1.0, before Hyperion switched over, so the server was first deployed from a signed,
  verified version.
- Done: Hyperion runs the stack from a checkout of this repository, with the existing data, ports and download
  paths.
- Done: Hyperion follows `main` with a pull agent, so a merge deploys within minutes, Dependabot's automatic merges
  included ([upgrading.md](upgrading.md#following-main)); releases stay as signed, verified snapshots.
- Done: qBittorrent upgraded from 4.5.5 to 5.3.0 (libtorrent 2.1), in its own pull request, once the maintainer
  lifted the hold on 2026-10-22.
- Done: Steerhouse (Ansible playbooks from a web UI) with its PostgreSQL, hosted here because its images are amd64
  only; its metrics and read-only `analytics` views published for Argus' Prometheus and Grafana, the database over
  TLS only ([installing.md](installing.md#steerhouse)).

## Next: safe upgrades and rebuilds

- Done: scheduled backups copied off the host (`scripts/scheduled-backup.sh`, a systemd timer), reported to Uptime
  Kuma, so the Minecraft worlds and Prowlarr's indexers are never only on Hyperion.
- Done: backups and restores take turns with the pull agent, so a deploy never recreates a service they stopped.
- Done (0.2.0): every service drops all capabilities and adds back only what its image needs, can't gain new
  privileges, and has a read-only root filesystem where the image allows it ([security.md](security.md)).

## Later

- Non-root users and read-only root filesystems for the images that don't allow them yet.
- Optional services as Compose profiles, so a smaller installation can leave them out.

## Security and project health

- Keep CI, CodeQL, Scorecard, dependency review and the DCO check green on every change.
- Branch protection on `main` with required checks; private vulnerability reporting; secret scanning with
  push protection.
- Done: **OSPS Baseline** Levels 1 and 2. Next: the OpenSSF Best Practices **Passing** and **Silver** badges,
  which wait on known vulnerabilities in the images being fixed within 60 days: the qBittorrent upgrade above fixed
  its share, and the rest wait for upstream releases ([dependencies.md](dependencies.md#current-findings)).
- Done: signed releases with checksums, SBOM and SLSA provenance, from the first release on.

## What homelab-hyperion will not do

- **Build or patch images.** It runs upstream images unchanged; bugs in the services go to their projects.
- **Configure the services' internals** (Prowlarr's indexers, qBittorrent's categories, Heimdall's links, the
  Minecraft worlds). Those are configured in each service and live in its data, which the backups cover.
- **Back up the downloads.** They are transient; the apps that import them keep their own copies.
- **Provide a VPN** or otherwise hide qBittorrent's traffic. That's a decision for each operator and network.
- **Store secrets.** No logins, tokens or keys in the repository, encrypted or not.
- **Auto-update from registries.** Every version change is a commit in `main` that passed CI; the server applies
  only those.
- **Run the other services on the same host** (the media server, the transcoder, monitoring agents). They have
  their own setup, even where they share the host.
- **Be a general-purpose homelab distribution.** It describes one server; others are welcome to fork or borrow
  from it, but options that only another setup needs are out of scope.
