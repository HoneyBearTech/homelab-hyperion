# Dependencies and vulnerability management

How homelab-hyperion chooses, obtains, tracks and updates what it's built from, and what happens when one of
those dependencies has a vulnerability.

homelab-hyperion's dependencies are almost entirely the **container images** it runs, pinned in
[`compose.yaml`](../compose.yaml). The rest are the tools its checks and tests use and the GitHub Actions in its
workflows. Its own code, the policy checker, uses only the Python standard library.

## Choosing a dependency

A new image or tool must:

- be open source under an OSI-approved license (the services' own licenses apply to them: homelab-hyperion pins
  and runs them, it doesn't redistribute or link them);
- be actively maintained: releases in the last year, security issues answered, and **published for
  `linux/amd64`**, the host's architecture;
- come from the project itself, from its official registry; and
- be worth it: a new service needs a reason in the pull request that adds it.

**Exception: the Bedrock Dedicated Server.** The `itzg/minecraft-bedrock-server` image is open source, but the
Minecraft server it downloads and runs is Mojang's proprietary software, used under the
[Minecraft EULA](https://www.minecraft.net/eula), which each operator accepts in `.env`. It is accepted because
Bedrock clients can only join a Bedrock server. It runs with no added privileges, and its version is pinned in
`compose.yaml` and changed only by hand, after a backup.

**Exception: autoheal's `latest` tag.** `willfarrell/autoheal` publishes versioned tags only up to 1.2.0
(2021); the maintained image is `latest`, so it is pinned by digest under a reasoned `allow.latest` label.

## Obtaining dependencies

| Dependency | Declared in | Pinned by | Fetched by |
| --- | --- | --- | --- |
| The stack's images | `compose.yaml` | version tag and digest | `docker compose pull` |
| Check and test tools (pytest, coverage, ruff, yamllint, shellcheck) | [`requirements-dev.in`](../requirements-dev.in) → [`requirements-dev.txt`](../requirements-dev.txt) | exact version and SHA-256 hashes (`pip-compile --generate-hashes`) | `pip install --require-hashes --no-deps` |
| The Bedrock Dedicated Server | `compose.yaml` (the image's `VERSION`) | exact version | the image, from Minecraft's site, on start |
| Helper image for backups and the smoke test (busybox) | [`scripts/lib.sh`](../scripts/lib.sh) | version tag and digest | Docker |
| Linters and scanners used only by CI (actionlint, gitleaks, Trivy) | [`.github/workflows/ci.yml`](../.github/workflows/ci.yml), [`scan.yml`](../.github/workflows/scan.yml) | version tag and digest | Docker |
| GitHub Actions | [`.github/workflows/`](../.github/workflows/) | full commit SHA (version in a comment) | GitHub Actions |

Each release will carry a CycloneDX SBOM listing every service's image and digest
([verifying-releases.md](verifying-releases.md)).

## Tracking dependencies

- **Dependabot** ([`.github/dependabot.yml`](../.github/dependabot.yml)) checks weekly for new image versions in the Compose file, new tool versions and new Action
  versions, and opens a pull request for each. Dependabot alerts and security updates are on.
- The CI-only images in `run:` steps, the scripts' busybox image and the Minecraft server's version aren't seen
  by Dependabot; they're bumped by hand at least every quarter (the Minecraft server whenever players' clients
  need a newer one, since Bedrock clients usually join only a server of their own version).
- **Patch and minor updates merge automatically** once every required check has passed (CI with the Compose
  policy check and the smoke test, CodeQL, dependency review).
- **Major updates are merged by hand**, after reading the service's release notes: a new major version can
  migrate its data one way.
- **qBittorrent is held at 4.5.5** for now: Dependabot ignores it until the server has moved to this stack, so
  the move changes one thing at a time. The upgrade to 5.x is its own pull request, with a backup first, and
  removes the `ignore` entry.
- **A merge doesn't deploy.** The server runs what it last pulled; updates reach it when the operator pulls
  and redeploys, with a backup first ([upgrading.md](upgrading.md)).
- **Dependency review** blocks a pull request that adds or changes a Python or Actions dependency with a known
  vulnerability of moderate severity or higher, or a license outside the allowlist.
- **Nothing updates itself on the host.** Auto-updaters such as Watchtower are not used: they would run
  versions nobody reviewed.

## Policy for vulnerabilities in dependencies

Known vulnerabilities are found through Dependabot alerts, the services' and images' own advisories, and a
weekly scan of the pinned digests (Trivy, HIGH and CRITICAL findings that have a fix, for `linux/amd64`,
reported to code scanning). Each finding is triaged within 14 days:

1. **If a fixed version exists**, bump to it (a Dependabot pull request usually already does) and release.
   A fix for an exploitable critical or high-severity vulnerability goes out in a patch release within 30
   days; others go out with the next release.
2. **If upstream hasn't released a fix**, assess whether it's reachable in this stack (which ports are
   published, and whether anything beyond the LAN can reach them). If it is, mitigate it where possible (for
   example, an access list or not publishing a port) and say so in the release notes; otherwise record the
   reason when dismissing the alert. Either way, it's fixed by a bump when upstream ships one.
3. **If an image is abandoned** and keeps accumulating vulnerabilities, replace it.

### Current findings

Triaged 13 October 2026, after the first image scan (283 alerts, every one HIGH or CRITICAL with a fixed package
version somewhere upstream). Every image is maintained. autoheal and the socket proxy had none.

**Fixed by a bump.** Dozzle `v11.3.2` (all 4: the Go standard library and `golang.org/x/net`), Heimdall
`v2.8.3-ls366` (9 of 20: Alpine's `apache2-utils` and `pcre2`) and the Minecraft image `2026.10.0` (12 of 40:
Debian's OpenSSL and PCRE2, `mc-monitor`'s Go dependencies). The Minecraft server's own version is unchanged.

**Accepted until the planned upgrade: qBittorrent 4.5.5** (171, 8 of them critical). The stack starts on the
version the server already runs, so moving to it changes one thing at a time; the upgrade to 5.x follows in its
own pull request ([roadmap](roadmap.md)), and no 4.x build is newer than 2024. Nearly all the findings are in
the image's 2023 Alpine packages (OpenSSL 3.1.3, expat, PCRE2, curl, Python, musl, zlib). Two of the critical
ones don't apply: CVE-2024-3094 is the xz backdoor, which only ever shipped in xz 5.6.0 and 5.6.1 (the image has
5.4.4), and CVE-2026-31789 affects OpenSSL on 32-bit systems only. qBittorrent's own finding, CVE-2024-51774
(before 5.0.1 it keeps using an HTTPS connection whose certificate failed validation), is reachable only from
the network path of what qBittorrent fetches over HTTPS itself: RSS feeds, torrent URLs, its GeoIP database.
Mitigated by keeping the web UI on the LAN and forwarding only the listening port
([installing.md](installing.md#running-it-securely)).

**Open, waiting for upstream** (87). No newer image exists yet with the fixed package; each alert closes by
itself when Dependabot's bump to such an image is merged and the scan runs again.

- **The .NET runtime bundled into Prowlarr (8.0.27, 48; fixed in 8.0.30).** The pinned build is Prowlarr's
  newest release. Reachable through its web UI and API; mitigated by keeping them on the LAN with
  authentication on. Fixed when Prowlarr ships a release on a newer runtime.
- **PHP libraries vendored by Heimdall (11):** `league/commonmark`, `guzzlehttp/guzzle` and
  `squizlabs/php_codesniffer` (a development tool that the web app never runs). Fixed when Heimdall updates its
  dependencies; Heimdall's UI stays on the LAN.
- **The Go standard library in the Minecraft image's helper tools (28):** `set-property`, `entrypoint-demoter`,
  `easy-add` and `mc-server-runner`, built with Go 1.26.3 to 1.26.6. They run at start, on local files and the
  server process, and don't listen on the network. Fixed when the image rebuilds them with a newer Go.

## Licenses

homelab-hyperion's own files are MIT-licensed. The Python tools must be under an OSI-approved license that
dependency review allows (MIT, Apache-2.0, BSD, ISC, PSF, MPL-2.0 and similar); yamllint (GPL-3.0) is
allowed as a development tool. The images keep their own licenses (the Bedrock Dedicated Server's is proprietary, see above).

## Policy for findings from static analysis (SAST)

CodeQL analyses the checker and the workflows on every pull request and weekly, and ruff runs the
bandit security rules in CI. A CodeQL finding of medium severity or higher is fixed before the next release, or,
if it is a false positive, dismissed in code scanning with a written reason. A ruff or shellcheck finding fails
CI; a deliberate exception is a per-line `noqa` or `shellcheck disable` with the reason next to it.
