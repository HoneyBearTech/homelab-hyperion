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
| Images of the GitLab copy's pipeline (Python, Docker CLI, git, gitleaks, actionlint) | [`.gitlab-ci.yml`](../.gitlab-ci.yml) | version tag and digest | GitLab Runner (Docker executor) |

Each release will carry a CycloneDX SBOM listing every service's image and digest
([verifying-releases.md](verifying-releases.md)).

## Tracking dependencies

- **Dependabot** ([`.github/dependabot.yml`](../.github/dependabot.yml)) checks weekly for new image versions in the Compose file, new tool versions and new Action
  versions, and opens a pull request for each. Dependabot alerts and security updates are on.
- The CI-only images in `run:` steps, the images in `.gitlab-ci.yml`, the scripts' busybox image and the
  Minecraft server's version aren't seen by Dependabot; they're bumped by hand at least every quarter (the
  Minecraft server whenever players' clients need a newer one, since Bedrock clients usually join only a server
  of their own version). Nor are new qBittorrent versions: Dependabot only proposes rebuilds of qBittorrent's
  pinned tag ([below](#qbittorrent)), and a new version is bumped by hand when upstream releases one.
- **Patch and minor updates merge automatically** once every required check has passed (CI with the Compose
  policy check and the smoke test, CodeQL, dependency review).
- **Image rebuilds merge automatically too**: a pull request that only moves an image to a new digest under the
  same tag (a rebuild of the same app version, with newer base packages) and changes nothing else in `compose.yaml`.
- **Major updates merge automatically too** (owner 2026-10-14), once the same checks pass, and reach the
  maintainer's server unattended. A new major version can migrate its data one way, so a revert alone doesn't undo
  it: the nightly backup is the way back (`scripts/restore.sh`). Only an update Dependabot can't classify (a tag
  scheme it doesn't read as a version) is merged by hand.
- **linuxserver.io images are pinned by their `version-<app version>` tag**
  (`prowlarr:version-2.6.5.5623@sha256:…`), which always points at the newest build of that app version. Dependabot
  can't follow the build tags (`2.6.5.5623-ls163`): it reads `-ls163` as a suffix that must match exactly, so it
  never proposes another build. With the `version-` tag it proposes both new app versions and rebuilds (a new digest
  under the same tag). socket-proxy uses its bare version tag (`3.4.6`) for the same reason.
- **A merge deploys.** The maintainer's server follows `main` with a pull agent, so every merge, the automatic
  ones included, reaches it within about two minutes ([upgrading.md](upgrading.md#following-main)). Dependabot's
  major updates, which can migrate data, therefore deploy unattended with the nightly backup behind them; the
  changes merged by hand (the Minecraft server's version, a new qBittorrent version) get a backup first.
- **Dependency review** blocks a pull request that adds or changes a Python or Actions dependency with a known
  vulnerability of moderate severity or higher, or a license outside the allowlist.
- **Nothing on the host updates from a registry.** Auto-updaters such as Watchtower are not used: they would run
  versions nobody reviewed. The pull agent only applies commits merged into `main`.

### qBittorrent

qBittorrent was held at 4.5.5 from 2026-10-14 until the maintainer lifted the hold on 2026-10-22; it now runs
5.3.0, and Dependabot no longer ignores it. Two things about it differ from the other linuxserver.io images:

- **Its `version-` tag names the libtorrent too**: `version-5.3.0_v2.1.2` is qBittorrent 5.3.0 built on libtorrent
  2.1.2, pointing at the newest build of exactly that pair. Dependabot can't read that as a version (its tag parser
  stops at the `_v`), so it proposes only rebuilds of the pinned tag, which merge by themselves like the other
  images' rebuilds and always keep libtorrent 2.1.2. A new qBittorrent version is a pull request by hand: read its
  release notes (a new minor version can migrate the settings one way), check which libtorrent the build uses, and
  back up first. The tags Dependabot could follow are worse here: the plain version and `latest` move to whichever
  libtorrent linuxserver.io builds next, and they did build 5.3.0 on libtorrent 2.0 for some hours (on 2026-10-20,
  and on the libtorrent 1.2 line on 2026-10-21), so a rebuild under one of them could change the libtorrent
  unattended.
- **libtorrent 2.1 or newer, never memory-mapped files.** libtorrent 2.0 (qBittorrent 4.5.5's) maps every file it
  reads or writes into memory, and its own documentation calls writing that way to a network share most likely
  inferior: the share's page cache shows up as qBittorrent's memory and every page fault waits on the network. libtorrent 2.1
  reads and writes the files with `pread`/`pwrite` from a pool of threads (`pread_disk_io`, the "Pread/pwrite" disk
  I/O type, and what "Default" means on 2.1). qBittorrent's own builds use libtorrent 2.1 by default since 5.3.0.
  The disk I/O type is a qBittorrent setting, not a Compose one
  ([installing.md](installing.md#downloads-on-a-network-share)). linuxserver.io's `libtorrentv1` builds (libtorrent
  1.2, which never maps files either and reads faster when seeding a lot, upstream says) are the fallback if
  seeding suffers, at the cost of BitTorrent v2 torrents.

### Steerhouse and its PostgreSQL

Steerhouse's two images (`honeybeartech/steerhouse-backend`, which the API and the workers share, and
`-frontend`) are published for `linux/amd64` only, signed, and scanned by Steerhouse's own release workflow;
Dependabot bumps both together. A new Steerhouse version migrates its database when the API starts: read its
release notes, and run `scripts/steerhouse.sh grafana-role` afterwards so that `grafana_ro` can read any new
`analytics` view. Its database runs the official `postgres` image on a minor tag (`18.6-trixie`): Dependabot proposes
the minors, which open the same data, and ignores the majors, because PostgreSQL 19 can't open version 18's data
directory. A major upgrade is a pull request by hand, with a dump of the old database and a restore into the new
one (or `pg_upgrade`), after a backup.

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

Triaged on 2026-10-22, from the scan of `main` at `043f623`: **352 open alerts, 18 critical and 334 high** (258 at
the first triage on 2026-10-13, which bumped Dozzle, Heimdall and the Minecraft image; 94 are new since). Code
scanning opens one alert per finding and file, so a component listed in several files counts several times: the
352 alerts are 127 distinct findings (one CVE or advisory in one image). Wherever a verdict depended on what an
image contains or runs, the pinned image was inspected (its package database, binaries and entry scripts) rather
than assumed. The alerts stay open in code scanning, so each closes by itself when an update ships the fix; none
was dismissed.

**Rescan after the upgrades** (`main` at `bc0b68b`, later on 2026-10-22, with qBittorrent 5.3.0 and Dozzle v11.3.4
deployed): **181 open alerts, 10 critical and 171 high**. Every qBittorrent and Dozzle alert closed; what remains is
Prowlarr (128, all 10 critical), the Minecraft image (39) and Heimdall (14: the 11 below and 3 new nginx findings).

| Image | Open alerts (critical) | Distinct findings | Action |
| --- | --- | --- | --- |
| qBittorrent `4.5.5-r0-ls292` | 173 (8), 0 after the rescan | 78 | **Fixed by the upgrade** to 5.3.0 (`version-5.3.0_v2.1.2`, build `ls484`) once the maintainer lifted the hold on 2026-10-22: a scan of the new image with the weekly scan's settings finds nothing ([qBittorrent](#qbittorrent)) |
| Prowlarr `version-2.6.5.5623` (build `ls165`) | 128 (10) | 19 | **Wait for upstream.** Every finding is in the .NET 8.0.27 runtime Prowlarr bundles, fixed in .NET 8.0.32 (2026-10-13); no Prowlarr build ships a newer runtime yet |
| Minecraft image `2026.10.1` | 39 | 18 | **Wait for upstream.** The Go standard library in the image's helper tools, and Debian's curl |
| Heimdall `version-v2.8.3` (build `ls368`) | 11, 14 after the rescan | 11, 14 after the rescan | **Wait for upstream.** PHP libraries Heimdall vendors, and (new at the rescan) the image's nginx |
| Dozzle `v11.3.2` | 1 (0 after the rescan) | 1 | **Fixed by a bump** to `v11.3.4`, built with Go 1.27.3, which fixes CVE-2026-111943 in `crypto/x509`; a scan of `v11.3.4` finds nothing |
| autoheal, socket-proxy | 0 | 0 | |
| Steerhouse backend and frontend `0.10.1` | 0 | 0 | Scanned with the weekly scan's settings before they were added (2026-10-22) |
| PostgreSQL `18.6-trixie` (Steerhouse's database) | 26 (1) | 26 | **Not reachable.** Every finding is in the Go standard library of `gosu` 1.24.6, which the image's entrypoint only runs when it starts as root, to drop to the `postgres` user; this stack runs it as `PUID`:`PGID`, so `gosu` never runs. Fixed when the image ships a newer `gosu` |

**Every critical finding:**

| Component (image) | CVE | Fixed in | Verdict | Action |
| --- | --- | --- | --- | --- |
| xz-libs 5.4.4 (qBittorrent) | CVE-2024-3094, the xz backdoor | 5.6.1-r2 | **Doesn't apply.** The backdoor only ever shipped in xz 5.6.0 and 5.6.1; the image's package database says 5.4.4. Alpine records the fix as 5.6.1-r2, so the scanner flags every older version | Fixed by the upgrade to 5.3.0 |
| libexpat 2.5.0 (qBittorrent) | CVE-2024-45491, CVE-2024-45492 | 2.6.3 | **Don't apply.** Integer overflows on 32-bit platforms only (where `UINT_MAX` equals `SIZE_MAX`); the image is x86_64 | Fixed by the upgrade to 5.3.0 |
| PCRE2 10.42: `pcre2`, `libpcre2-16` (qBittorrent) | CVE-2025-58050 | 10.46 | **Doesn't apply.** Only PCRE2 10.45 is affected (the `(*scs:…)` verb it involves is new in 10.45); the image has 10.42 | Fixed by the upgrade to 5.3.0 |
| OpenSSL 3.1.3: `openssl`, `libssl3`, `libcrypto3` (qBittorrent) | CVE-2026-31789 | 3.5.6 | **Doesn't apply.** A heap overflow on 32-bit platforms only; the image is x86_64 | Fixed by the upgrade to 5.3.0 |
| ASP.NET Core runtime 8.0.27 (Prowlarr) | CVE-2026-70188 (security feature bypass), CVE-2026-88092 (tampering) | .NET 8.0.32 | **Reachable from the LAN.** HTTP request smuggling in Kestrel, which serves Prowlarr's web UI and API. Mitigated: the UI stays on the LAN and Prowlarr requires a login ([installing.md](installing.md#running-it-securely)) | Wait for upstream |

**Notable high findings:**

- **Prowlarr: the rest of .NET 8.0.27** (17 findings, 118 alerts): denial of service, elevation of privilege and
  security feature bypasses in the runtime and ASP.NET Core. It is one runtime, listed in up to eight `*.deps.json`
  files, so each finding counts five or eight times. Six were fixed in .NET 8.0.29 (2026-07-14) and 8.0.30
  (2026-08-11), the rest in 8.0.32 (2026-10-13), yet Prowlarr's newest release (2.6.5.5623, 2026-09-16) and its
  development branch still build on 8.0.27. The `System.Security.Cryptography.Pkcs` 8.0.1 finding (CVE-2026-84008)
  is a package reference from MimeKit; the copy Prowlarr loads is ASP.NET Core 8.0.27's own, fixed by the same
  runtime update. Reachable through the web UI and API (LAN, login required), and CVE-2026-50651 (an HTTP/2 flood
  in the HTTP client) through the indexers Prowlarr connects to. Wait for upstream.
- **qBittorrent 4.5.5** (until the upgrade to 5.3.0, which fixes all of these). Its own finding, CVE-2024-51774 (before 5.0.1 it keeps using an HTTPS connection
  whose certificate failed validation), is reachable only from what qBittorrent fetches over HTTPS itself: RSS
  feeds, torrent URLs, its GeoIP database. OpenSSL 3.1.3 (11 more findings) carries qBittorrent's own TLS
  connections (libtorrent and Qt link it): the most exposed of its findings. Python 3.11 and expat (30
  findings) are there for qBittorrent's search plugins: nothing but Python links expat or xz's `liblzma`. New since
  the first triage: curl's CVE-2026-92392 (HTTP/2 uploads). curl runs only as the health check, a plain HTTP
  request to the container itself, and libcurl otherwise only for Qt's proxy auto-configuration, which isn't set
  up; neither uploads anything, so it isn't reachable. zlib's CVE-2026-22184 is in the `untgz` demonstration
  program, which Alpine's package doesn't ship (only `libz.so`): it doesn't apply. Mitigated by keeping the web UI
  on the LAN and forwarding only the listening port ([installing.md](installing.md#running-it-securely)).
- **Minecraft image** (39 alerts). The Go standard library in five helper tools: `set-property` 0.1.6 (Go 1.26.3,
  15 alerts), `entrypoint-demoter` 0.5.1 (Go 1.26.5, 12), `easy-add` 0.8.17 (Go 1.26.6, 4), and `mc-monitor` 1.18.3
  and `mc-server-runner` 1.16.1 (Go 1.27.2, one each: CVE-2026-111943, new). Not reachable: none of them listens on
  the network or reads untrusted input. `set-property` writes `server.properties` at start, `entrypoint-demoter`
  switches to `UID`:`GID` and starts the entry script, `easy-add` only installs the other tools while the image is
  built, `mc-monitor` is the health check (a status ping to the server in the same container, no TLS), and
  `mc-server-runner` runs the server with its remote console off. The image's main branch already has `easy-add`
  and `mc-server-runner` built with Go 1.27.3 for its next release; `set-property` and `entrypoint-demoter` have no
  newer release. Debian's curl `8.14.1-2+deb13u5` (new: CVE-2026-8286, CVE-2026-8927 and CVE-2026-92392, in `curl`
  and `libcurl4t64`; fixed in `8.14.1-2+deb13u7`): not reachable, as they need STARTTLS, proxy Digest
  authentication or HTTP/2 uploads, and the entry script only downloads (the server and its version list) over
  HTTPS, with no proxy. Fixed when the image is rebuilt.
- **Heimdall** (11, unchanged): `league/commonmark` 2.8.2 (9: denial of service, and an XSS filter bypass in an
  extension; fixed in 2.9.0 to 2.10.2), `guzzlehttp/guzzle` 7.13.3 (CVE-2026-69246, a non-canonical host name gets
  past host-based checks; fixed in 7.15.2) and `squizlabs/php_codesniffer` 3.13.5 (CVE-2026-67434, command
  injection in its `gitblame` report; fixed in 3.13.6). Not reachable: commonmark comes with Laravel, and
  Heimdall's own code renders no Markdown (checked in the image); php_codesniffer is a development tool the web
  app never runs; Heimdall calls the apps it links to with Guzzle but allows or blocks nothing by host name. Fixed
  when Heimdall updates its dependencies; its UI stays on the LAN.
- **Heimdall's nginx 1.30.4** (3, new at the rescan): CVE-2026-15176 (a heap overflow that needs an `alias` together
  with a regex `rewrite`) and CVE-2026-93479 (in regex matching inside a `map`) don't apply: the image's nginx
  configuration has no `alias` and no `rewrite`, and its one `map` (`$http_upgrade`, for websockets) matches fixed
  strings only (checked in the image). CVE-2026-97205 (`ngx_http_core_module`, no details published yet) is
  reachable from the LAN, where Heimdall's UI stays. Fixed when linuxserver.io rebuilds the image on a patched nginx;
  Dependabot proposes that rebuild.

**Older than 60 days.** After the upgrade to qBittorrent 5.3.0, these findings have had a fix public for more than
60 days (as of 2026-10-22). None of them is in this repository's own code, which has no known vulnerabilities; all
are in third-party images that are already on their newest upstream release, so no update is available to apply.
Each was assessed against the pinned image:

| Image | Findings | Fix public since | Verdict |
| --- | --- | --- | --- |
| Prowlarr | 6 in the .NET 8.0.27 runtime (CVE-2026-47302, CVE-2026-50524, CVE-2026-50528, CVE-2026-50651, CVE-2026-57108, CVE-2026-62901) | .NET 8.0.29 (2026-07-14) and 8.0.30 (2026-08-11) | Reachable only from the LAN, through a web UI and API that require a login (CVE-2026-50651 also through the indexers Prowlarr connects to). No Prowlarr release ships a patched runtime yet; the update is applied as soon as one does (see the watch below) |
| Minecraft image | Go standard library in `set-property` (11) and `entrypoint-demoter` (8) | Go 1.26.4 to 1.26.6 (2026-06-02 to 2026-08-13) | Not reachable: neither tool listens on the network or reads untrusted input (they write `server.properties` and switch users at start) |
| Heimdall | 6 in vendored PHP libraries (CVE-2026-69246 in Guzzle; CVE-2026-71488, GHSA-g2gp-3wwq-f4ph, GHSA-jfm3-95jq-q3rf, GHSA-mh25-x5hq-wrqp in league/commonmark; CVE-2026-67434 in php_codesniffer) | advisories of 2026-08-03 and 2026-08-06 | Not reachable: Heimdall renders no Markdown, never runs php_codesniffer, and allows or blocks nothing by host name |

This is the basis for the OpenSSF Best Practices answer on fixing vulnerabilities within 60 days: the project fixes
what it can (it upgraded qBittorrent and Dozzle for exactly this), keeps every image on its newest release, and
records each finding it can't fix with a verdict. The other images' remaining findings reach 60 days between
2026-10-31 and 2026-12-18 unless upstream ships the fixes first; Prowlarr's .NET 8.0.32 findings, both critical ones
included, on 2026-12-12. Each is reassessed at the monthly re-triage.

**Watch: Prowlarr's .NET runtime.** Prowlarr's releases lag the runtime they bundle (its newest ships .NET 8.0.27,
from May 2026), and .NET 8 is supported only until 2026-11-10. If no Prowlarr release on a patched runtime
(.NET 8.0.32 or later, or .NET 10) has shipped by the next quarterly review (January 2027), reassess (step 3).

**Watch: the Minecraft image's `set-property` and `entrypoint-demoter`.** Last built in May and July 2026, with Go
releases that have had security fixes since. If they haven't been rebuilt by the next quarterly review (January
2027), ask upstream for a rebuild.

## Licenses

homelab-hyperion's own files are MIT-licensed. The Python tools must be under an OSI-approved license that
dependency review allows (MIT, Apache-2.0, BSD, ISC, PSF, MPL-2.0 and similar); yamllint (GPL-3.0) is
allowed as a development tool. The images keep their own licenses (the Bedrock Dedicated Server's is proprietary, see above).

## Policy for findings from static analysis (SAST)

CodeQL analyses the checker and the workflows on every pull request and weekly, and ruff runs the
bandit security rules in CI. A CodeQL finding of medium severity or higher is fixed before the next release, or,
if it is a false positive, dismissed in code scanning with a written reason. A ruff or shellcheck finding fails
CI; a deliberate exception is a per-line `noqa` or `shellcheck disable` with the reason next to it.
