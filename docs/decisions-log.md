# Decisions log

Maintenance decisions, why they were made, and what was considered instead.

## 2026-11-20 - Renovate replaces Dependabot (renovate-migrate, #75)

**Decision.** Renovate (`.github/renovate.json5`) now proposes every dependency update, and `.github/dependabot.yml`
is removed in the same change. The config follows homelab-atlas, which made the same move. Dependabot security
updates were turned off by the owner; Dependabot alerts stay on, and Renovate reads them.

**Automatic merging stays as it was.** Patch, minor and major updates and image rebuilds merge by themselves once
every required check passes (the owner's call of 2026-10-14), so a merge still deploys. New: a version waits 3 days
after its release first, where the registry reports a release date. Vulnerability fixes and image rebuilds don't
wait. The `main` ruleset (six required checks, signed commits, squash only, no bypass actors) gates every merge;
Renovate's commits are signed by GitHub and carry a sign-off line for the DCO check.

**Kept as under Dependabot.**
- Dozzle stays held (a `renovate.json5` rule now) until its fixed release is pinned by hand.
- qBittorrent: rebuilds of its tag are followed; a new qBittorrent version is bumped by hand, because a new version
  can migrate settings one way. Renovate could read the tag (a version scheme that keeps the libtorrent fixed), but
  following new versions automatically was not part of this change.

**New coverage.** Renovate also proposes the pins that were bumped by hand: the `.gitlab-ci.yml` images, the images
started by `docker run` in workflows and scripts, and the pre-commit hooks (pinned by commit SHA in its first pull
requests). Python's minor version, the runner label and the idle auto-merge workflow's own action stay hand-picked.

**`requirements-dev.txt` re-locked** with pip-compile, keeping every version: Renovate couldn't read its one-line
header, and 119 of its hashes were repeated. Every hash was checked against PyPI.

**Alternatives rejected.**
- Keep Dependabot's narrower coverage: the hand-bumped pins were the ones most often left behind.
- Require a release date for the 3-day wait (`timestamp-required`): versions from registries that report none would
  never be proposed.

**Review findings fixed.**
- Renovate's pip-compile manager turns on a periodic lock-file refresh by default. It would re-resolve every tool to
  its newest version with no release dates, skipping the 3-day wait, and merge. It is now off. (homelab-atlas's
  config has the same gap.)
- The docs now say the wait applies only where a registry dates its releases; that autoheal's `latest` tag means a
  rebuild can be a new autoheal version; that Renovate's pull requests run CI with the Docker Hub secret, including
  ones that update workflow Actions; and that the pre-commit hooks get their SHA pins in Renovate's first pull
  requests.

**Review findings rejected.**
- "The auto-merge workflow is only idle once Dependabot security updates are off": they already are (the owner
  turned them off for every repository before this job).

**Left as is.** `.github/workflows/dependabot-auto-merge.yml` and the Dependabot comments in `ci.yml` and `scan.yml`
are unchanged, because workflow files are outside this job. The workflow only acts on Dependabot's pull requests, so
it no longer runs.
