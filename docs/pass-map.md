# Pass map

A short record of each piece of maintenance work: when it happened, what shipped, and where.

| Date | Job | What shipped | PR |
| --- | --- | --- | --- |
| 2026-11-20 | renovate-migrate | Dependency updates moved from Dependabot to Renovate (`.github/renovate.json5`, modelled on homelab-atlas; `.github/dependabot.yml` removed). Patch, minor and major updates and image rebuilds still merge by themselves after the required checks; new versions now wait 3 days where the registry dates them. Renovate also proposes the pins that were bumped by hand (`.gitlab-ci.yml`, workflow and script images, pre-commit hooks). Dozzle stays held; new qBittorrent versions stay hand-bumped. `requirements-dev.txt` re-locked with pip-compile's standard header (same versions). Docs updated. | [#75](https://github.com/HoneyBearTech/homelab-hyperion/pull/75) |
