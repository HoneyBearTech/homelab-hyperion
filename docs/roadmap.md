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
- First release (0.1.0) before Hyperion switches over, so the server is first deployed from a signed, verified
  version.
- Switch Hyperion to run the stack from a checkout of this repository, adopting the existing data, ports and
  download paths so nothing that reaches the server notices.
- Then upgrade qBittorrent from 4.5.5 to 5.x, in its own pull request.

## Next: safe upgrades and rebuilds

- Rehearse the documented rebuild ([rebuilding.md](rebuilding.md)) on a scratch machine.
- Done: scheduled backups copied off the host (`scripts/scheduled-backup.sh`, a systemd timer), reported to Uptime
  Kuma, so the Minecraft worlds and Prowlarr's indexers are never only on Hyperion. Switched on after the move.

## Later

- Tighter container settings where the images allow it (read-only root filesystems, dropped capabilities,
  non-root users).
- Optional services as Compose profiles, so a smaller installation can leave them out.

## Security and project health

- Keep CI, CodeQL, Scorecard, dependency review and the DCO check green on every change.
- Branch protection on `main` with required checks; private vulnerability reporting; secret scanning with
  push protection.
- Reach the OpenSSF Best Practices **Passing** and **Silver** badges, and meet **OSPS Baseline** Levels 1
  and 2.
- Signed releases with checksums, SBOM and SLSA provenance from the first release on.

## What homelab-hyperion will not do

- **Build or patch images.** It runs upstream images unchanged; bugs in the services go to their projects.
- **Configure the services' internals** (Prowlarr's indexers, qBittorrent's categories, Heimdall's links, the
  Minecraft worlds). Those are configured in each service and live in its data, which the backups cover.
- **Back up the downloads.** They are transient; the apps that import them keep their own copies.
- **Provide a VPN** or otherwise hide qBittorrent's traffic. That's a decision for each operator and network.
- **Store secrets.** No logins, tokens or keys in the repository, encrypted or not.
- **Auto-update.** Every version change is a reviewed commit.
- **Run the other services on the same host** (the media server, the transcoder, monitoring agents). They have
  their own setup, even where they share the host.
- **Be a general-purpose homelab distribution.** It describes one server; others are welcome to fork or borrow
  from it, but options that only another setup needs are out of scope.
