# Security requirements

What homelab-hyperion is meant to guarantee, what it leaves to the operator and the services, and where secrets
live. The reasoning behind these requirements is in the [assurance case](assurance-case.md).

## What homelab-hyperion protects

1. **Only reviewed versions run.** Every image is pinned as `name:tag@sha256:<digest>`, and the Minecraft
   server's own version is pinned in `compose.yaml`. A registry tag that is moved or hijacked doesn't change
   what `docker compose pull` fetches; a new version arrives only as a pull request that changes the pin.
2. **No container gets more of the host than it needs.** Every service drops every Linux capability, adds back
   only the ones its image needs (never more than Docker's default set) and can't gain privileges from setuid
   binaries or file capabilities. Where an image allows it, its root filesystem is read-only
   ([Hardening](#hardening)). No service runs privileged, shares the host's
   network or PID namespace, maps a host device, or mounts the Docker socket (which is root on the host),
   unless the exception is written into the service as a reasoned label and reviewed. There are two
   exceptions: Dozzle (read-only mount, to read logs) and the socket proxy (which gives autoheal a filtered API
   instead of the socket).
3. **No secrets in the repository.** The services keep their logins, indexer credentials and API keys in their
   own data, outside the repository. `.env` holds settings only. Secret scanning with push protection and a
   gitleaks scan of the whole history in CI back this up.
4. **No host details in the repository.** It is public: no hostnames, IP addresses, domains, share names, host
   paths or player names are committed. Examples use placeholders.
5. **Releases are verifiable.** Release files are listed in a `SHA256SUMS` signed keylessly by the release
   workflow, with SLSA provenance and an SBOM of the pinned images ([verifying-releases.md](verifying-releases.md)).
6. **Backups don't leak and can't reach the downloads.** `scripts/backup.sh` writes archives readable only by
   the user who ran it (the scheduled copy off the host keeps those modes), and `scripts/restore.sh` writes only
   the mounts the backup's checksummed `MANIFEST` lists and the service still has, never the downloads directory
   or any other path a service excludes with its `org.honeybeartech.hyperion.backup.skip` label.

## Policy

`scripts/check_compose.py` enforces requirements 1 and 2 on the resolved Compose file in CI and
before every release. A service may break a rule only with the label `org.honeybeartech.hyperion.allow.<rule>` and
a non-empty reason:

| Rule | Fails when a service |
| --- | --- |
| `image` | has no `image` |
| `digest` | uses an image without both a tag and a `sha256` digest |
| `latest` | uses the `latest` tag |
| `build` | builds an image instead of pulling a pinned one |
| `privileged` | sets `privileged: true` |
| `no-new-privileges` | doesn't set `security_opt: [no-new-privileges:true]` |
| `cap-drop` | doesn't drop every capability (`cap_drop: [ALL]`) |
| `cap-add` | adds a capability outside Docker's default set (adding back one of those only narrows the default) |
| `host-network` / `host-pid` | uses the host's network or PID namespace |
| `docker-socket` | mounts the Docker socket |
| `devices` | maps a host device into the container (a GPU reservation under `deploy.resources` is allowed) |
| `healthcheck` | has no health check, or disables it (one defined only in the image isn't visible to the check) |

## Hardening

What each service runs with, beyond the policy. Every service has `cap_drop: [ALL]` and
`no-new-privileges:true` and adds back only the capabilities in this table, all from Docker's default set. The
smoke test, with the apps' folders owned by `PUID`:`PGID` as on the host (Dozzle's by root), proves each one still
starts healthy and survives a backup and restore with these settings, and that autoheal can still restart a container
through the socket proxy. Each capability was kept only after the service failed, logged an error or couldn't stop
cleanly without it.

| Service | Capabilities added back | Read-only root filesystem | Why |
| --- | --- | --- | --- |
| prowlarr | `CHOWN`, `SETUID`, `SETGID`, `KILL` | no | Its init (s6-overlay) runs as root, takes ownership of the data for `PUID`:`PGID`, runs Prowlarr as that user and signals it on shutdown. The init runs from `/run` and writes to the image's own directories, so the root stays writable (a `/run` tmpfs is mounted noexec, and the init can't start) |
| qbittorrent | `CHOWN`, `DAC_OVERRIDE`, `SETUID`, `SETGID`, `KILL` | no | As Prowlarr; the init also writes the default settings into a data directory that belongs to `PUID` |
| heimdall | `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`, `KILL` | no | As Prowlarr; the init also sets up nginx, PHP and the app in directories that belong to `PUID` and sets the mode of the app's settings file. Ports 80 and 443 need no capability: Docker lets any process in a container bind low ports |
| dozzle | none | yes (`/tmp` in memory) | Reads the Docker socket, which belongs to root, the user it runs as. Settings saved in its UI go to `/data`, its folder `CONFIG_ROOT/dozzle/config`, which Docker creates owned by root |
| minecraft | `SETUID`, `SETGID` | yes (`/tmp` in memory) | Its entrypoint starts as root and switches to `UID`:`GID` before it downloads or runs the server; the server and the world are in its data mount |
| autoheal | none | yes | Only talks to the socket proxy |
| socket-proxy | none | yes (`/run`, `/tmp` in memory) | Only reads the socket |

The root inside a container without capabilities can only reach what it owns. Data adopted from another
installation must therefore be owned as each image expects: the linuxserver.io services' and the Minecraft
server's data by `PUID`:`PGID`, Dozzle's by root; a service that fails with "permission denied" (`EACCES`) on its
first start usually has data with an unexpected owner.

## What it doesn't protect

- **The services themselves.** A vulnerability in Prowlarr, qBittorrent, Heimdall, Dozzle, autoheal or the
  Minecraft server is that project's to fix; homelab-hyperion ships the fixed version once it's released
  ([dependencies.md](dependencies.md)).
- **What qBittorrent downloads and shares.** The content, and what sharing it means where you live, are the
  operator's responsibility. Peers see the host's public IP address; this stack doesn't hide it.
- **The downloads.** They aren't backed up; the apps that import them keep their own copies.
- **Access to the web UIs.** Keeping them on the LAN, behind a reverse proxy's access lists, with each service's
  login turned on, is the operator's job ([installing.md](installing.md#running-it-securely)). Anyone who can use
  Dozzle can read every container's logs.
- **Players on the Minecraft server.** Who may join (the allowlist) and whether it's reachable from the
  internet are the operator's settings.
- **The host.** Anyone with root, `docker` group membership or write access to `.env` or the services' data
  controls the stack; those are trusted.
- **Backups off the host from the host itself.** The scheduled backup can delete old backups on the backup
  server, so whoever controls this host can delete or overwrite them too. Snapshots or a versioned copy on the
  backup server, outside this host's reach, are what protect them; a recycle bin may not see deletions made over
  rsync (Synology's doesn't).
- **Upstream images' internals.** Some images run as root inside the container; that is the image's design and
  is accepted where the image offers nothing else.

## Where secrets live

| Secret | Where | Never in |
| --- | --- | --- |
| Logins of the services that have them (Prowlarr, qBittorrent, optionally Heimdall and Dozzle) | each service's data | the repository, `.env`, issues, logs you paste |
| Indexer credentials and API keys; the media apps' API keys | Prowlarr's data | same |
| autoheal's notification webhook URL (optional) | the gitignored `autoheal.env`, mode `600` | same |
| The backup push monitor's URL | `backup.env` (mode `600`, gitignored) | the repository, issues, logs you paste |
| The key for the backup server | the stack user's `~/.ssh` on the host, restricted on the server to this host | same |
| Backups of the data | off the host, mode `600` | anywhere public |
