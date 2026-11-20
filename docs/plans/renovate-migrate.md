# Plan: move dependency updates from Dependabot to Renovate

**What the owner asked for:** "remove Dependabot workflows, turn off Dependabot security updates, and turn on Renovate."

## What we found

- Dependabot covers the stack's images (`compose.yaml`, with Dozzle held back), the check tools
  (`requirements-dev.txt`) and the Actions, and the auto-merge workflow merges its patch, minor and major updates and
  same-tag image rebuilds once the required checks pass (the owner's call, 2026-10-14). A merge deploys.
- homelab-atlas already made this move, with `.github/renovate.json5`: the same automatic merging, plus a 3-day wait
  for new versions, signed and signed-off commits, and coverage of the pins Dependabot never saw (`.gitlab-ci.yml`,
  the pre-commit hooks, images started by `docker run` in workflows and scripts). That config works here with a few
  additions.
- Renovate can't read `requirements-dev.txt` as it is: its header is a one-line comment instead of the standard
  pip-compile header, and it repeats 119 of its hashes. Re-locking it fixes both.
- The required checks and `dco.yml` already accept Renovate's commits; no workflow change is needed.

## What we'll change

1. **Re-lock `requirements-dev.txt`** with pip-compile on Python 3.14, keeping every pinned version. This gives it the
   standard header and drops the repeated hashes.
   *Check:* same package versions as before; CI's checks and tests pass; Renovate's dry run reads all 11 packages.
2. **Add `.github/renovate.json5`**, adapted from homelab-atlas: Mondays from 06:00 UTC, assigned to the owner;
   images pinned by tag and digest, Actions and pre-commit hooks by commit SHA; signed commits with a sign-off line.
   Patch, minor and major updates and image rebuilds merge automatically once every required check passes, as
   today. New versions wait 3 days first; vulnerability fixes and image rebuilds don't wait. Additions for this
   stack:
   - Dozzle stays held, as today, until its fixed release is pinned by hand.
   - qBittorrent keeps today's rule: rebuilds of its tag are followed, a new qBittorrent version is bumped by hand.
   - The two Steerhouse images move together; CodeQL's actions move together.
   - Python's minor version (3.14) and the runner label stay hand-picked.
   - The idle auto-merge workflow's own action isn't updated.
   *Check:* Renovate's config validator in strict mode, and a dry run that finds every pinned file.
3. **Delete `.github/dependabot.yml`** in the same change.
4. **Update the docs that name Dependabot**: `docs/dependencies.md` (rewritten for Renovate, like atlas's),
   `GOVERNANCE.md`, `README.md`, `CONTRIBUTING.md`, `SUPPORT.md`, `docs/architecture.md`, `docs/upgrading.md`,
   `docs/assurance-case.md`, `docs/README.md`, the comments in `compose.yaml` and `.gitlab-ci.yml`, and a
   `CHANGELOG.md` entry. Older changelog entries stay as they are.
   *Check:* no doc still says Dependabot proposes updates; the wording matches the config.
5. **Job notes:** `docs/roadmap.md`, and new `docs/pass-map.md` and `docs/decisions-log.md`.

Nothing in `.github/workflows` changes. `dependabot-auto-merge.yml` stays; with Dependabot gone, nothing triggers it.

## Who's on it

Researcher (done), Engineer, QA, Security Officer, Auditor.

## Risks

- A merge deploys. Majors already merge unattended today; the new 3-day wait makes that slightly safer.
- Renovate now also proposes the hand-bumped pins (`.gitlab-ci.yml`, workflow and script images, pre-commit hooks).
  These are check and test tools, not the deployed stack, and the required checks gate them.
- Renovate's pull requests are branches in this repo, so CI runs on them with the Docker Hub secret, as homelab-atlas
  already does. CI logs out of Docker Hub before any container starts.
- The Renovate app must have access to this repo, and the repo's "Allow auto-merge" setting must stay on.

## Out of scope

- Deleting `dependabot-auto-merge.yml` and the two workflow comments that name Dependabot (workflow files).
- Repo settings and secrets.
