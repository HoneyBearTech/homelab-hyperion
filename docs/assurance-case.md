# Assurance case

Why homelab-hyperion meets its [security requirements](security.md): the threat model, the trust boundaries,
the secure design principles it follows, and how common weaknesses are countered.

## Threat model

| Asset | Threat | Countered by |
| --- | --- | --- |
| The host | A compromised or malicious image | Digest pins; versions change only by reviewed pull request; no privileged, capability, host-namespace or socket access without a reasoned label, enforced by `scripts/check_compose.py` in CI and before every release |
| The host | A flaw in Dozzle or autoheal turned against the Docker API | Dozzle on the LAN only, behind access lists and its own login; autoheal never gets the socket, only the socket proxy's filtered API (list, inspect, restart, stop) on an internal network with no published port |
| The host | The Minecraft server, exposed to players, is exploited | Runs unprivileged with only its data mounted; pinned server version; allowlist on; reachable from the internet only if the operator forwards its UDP port |
| The host's network identity | qBittorrent reveals the public IP address to peers | Documented; forwarding only the listening port, never the web UI; a VPN is the operator's choice |
| The downloads | A backup or restore script touching them | Paths in a service's `org.honeybeartech.hyperion.backup.skip` label are never archived by `backup.sh`, and `restore.sh` refuses to write them even if a backup lists them; the smoke test checks both |
| The web UIs | Someone on the LAN uses a service | LAN only, behind a reverse proxy's access lists; every login the service offers turned on ([installing.md](installing.md#running-it-securely)) |
| Indexer credentials, logins | Committed to the public repository | Kept in the services' data, never in the repo; `.gitignore`; GitHub push protection; gitleaks over the history in CI |
| Indexer credentials, logins | Leaked through a backup or Dozzle's log view | `scripts/backup.sh` writes backups readable only by the user who ran it, documented as secret, to be kept off the host; Dozzle treated as admin access |
| The services' data | An upgrade that migrates and breaks it (including a Minecraft world opened by a newer server) | Backup before every update merged by hand, nightly otherwise; rollback = a revert (or the old tag) + `scripts/restore.sh`, exercised by the CI smoke test against the real stack; the Minecraft server version changes only by hand |
| The host | A bad change merged to `main` deploying by itself | The required checks (policy check, smoke test) pass before any merge; the Minecraft server's version is changed by hand, and Dependabot's majors deploy unattended with the nightly backup behind them; the pull agent only fast-forwards and backs out a change that doesn't resolve or pull; rollback is a revert pull request |
| The services' data | A crafted backup writing outside the services' data | `restore.sh` verifies `SHA256SUMS` (which covers the `MANIFEST`), accepts only plain archive names and absolute container paths without `..`, and writes only a mount the service has read-write and doesn't exclude from backups |
| Availability | A service hangs without exiting | A health check on every service and autoheal restarting unhealthy containers, checked by the smoke test |
| The release | Tampered release files | Keyless-signed `SHA256SUMS`, SLSA provenance, signed tags |
| The CI pipeline | Untrusted pull request input running with credentials | `pull_request` only, read-only token by default, untrusted values only via `env:`, actions pinned by SHA |
| Operator privacy | Hostnames, addresses, share names, paths or player names in the public repo | Placeholders only; reviewed in every pull request |

Attackers considered: a compromised upstream image or registry tag; someone on the LAN reaching a web UI; a
BitTorrent peer or Minecraft player on the internet sending hostile traffic; a malicious pull request; a tampered
backup; an honest mistake in an upgrade. Out of scope: an attacker who already has root or `docker` group access
on the host, or write access to `.env` or the services' data.

## Trust boundaries

1. **Registries → host.** Images are trusted only at the digest a reviewed commit names; the Minecraft server
   binary only at the version a reviewed commit names, downloaded over HTTPS from Minecraft's site.
2. **Repository → host.** The maintainer's host runs `main`: a pull agent fetches it and only fast-forwards,
   refusing rewritten history and local changes, so the host never runs code that wasn't merged.
   Nothing connects in to the host to deploy. (Others can run a tagged, signed release instead.)
3. **LAN → web UIs.** Not published beyond the LAN; reached through a reverse proxy with access lists.
4. **Internet → qBittorrent's listening port and the Minecraft port.** The only ports meant to face the
   internet, and only if the operator forwards them.
5. **Containers → Docker API.** Dozzle (read-only socket mount) and the socket proxy only; autoheal through the
   proxy.
6. **Containers → host.** Only each service's data directories and the downloads; no host namespaces.
7. **Pull requests → CI.** Fork pull requests get a read-only token and no secrets. The project's one
   secret, a Docker Hub token that can only read public images (once the maintainer adds it), is logged out
   before the smoke test starts any container.

## Secure design principles

- **Least privilege**: every capability dropped and only the needed defaults added back, no new privileges,
  read-only root filesystems where the images allow it, no host namespaces or devices; the Docker API only where a service can't work
  without it, filtered for autoheal; read-only CI tokens raised per job.
- **Fail-safe defaults**: the policy check fails on anything it doesn't recognise as allowed; an exception
  needs a reason, in the file, in review. `restore.sh` refuses anything in a backup it can't account for. The
  Minecraft server won't start without an explicit EULA setting.
- **Complete mediation**: every change to what runs passes through a pull request and the same checks;
  the host only fast-forwards to merged commits.
- **Economy of mechanism**: one Compose file, one standard-library checker, upstream images unchanged.
- **Separation of privilege**: secrets live with the services, settings in `.env`, configuration in git.
- **Open design**: the whole configuration, policy and release process are public.

## Common weaknesses

| Weakness | Where it could arise | How it's countered |
| --- | --- | --- |
| CWE-494 (code downloaded without integrity check) | Image pulls; the Minecraft server download | Digest pins; signed release checksums; a pinned server version over HTTPS |
| CWE-798 / CWE-312 (hard-coded or cleartext credentials) | Compose `environment:`, `.env`, docs | No secrets in the repo; gitleaks; push protection |
| CWE-250 (unnecessary privileges) | Container settings, Docker socket access | Policy rules `privileged`, `no-new-privileges`, `cap-drop`, `cap-add`, `host-*`, `docker-socket`, `devices`; every capability dropped and only the needed defaults added back, read-only root filesystems where the images allow it ([security.md](security.md#hardening)); the socket proxy for autoheal |
| CWE-306 (missing authentication for critical function) | Web UIs | LAN only, behind access lists; logins on where offered |
| CWE-532 (sensitive information in logs) | Dozzle showing every container's log, on this host and the hosts its agents run on | Dozzle treated as admin access: LAN only, behind access lists and a login |
| CWE-22 (path traversal) | Restoring a backup | `restore.sh` validates archive names and mount paths from the checksummed `MANIFEST` |
| CWE-1104 (unmaintained third-party components) | Images, tools, Actions | Dependabot weekly; image scan; triage SLAs ([dependencies.md](dependencies.md)) |
| CWE-77/78 (injection) | Workflows, scripts | Untrusted values only via `env:`; actionlint and shellcheck; CodeQL for Actions |
| CWE-20 (improper input validation) | The checker's input | It reads JSON only with the standard library, never evaluates it, and exits 2 on anything that isn't a JSON object |

## Evidence

- CI on every change: ruff (with the bandit rules), yamllint, actionlint, gitleaks over the history,
  shellcheck, pytest with a 90 % branch-coverage floor, `docker compose config`, the policy check, and a smoke
  test on amd64 that starts every pinned image, waits for its health check, round-trips a backup and restore,
  checks that excluded mounts are left alone, runs the scheduled backup against a stand-in backup server, and
  checks that autoheal restarts an unhealthy container (a dynamic test
  of the stack and the scripts).
- A weekly Trivy scan of every pinned image, and on every change to `compose.yaml` on `main`, into code scanning.
- CodeQL (Python and Actions) on every pull request and weekly; OpenSSF Scorecard weekly; dependency
  review on every pull request.
