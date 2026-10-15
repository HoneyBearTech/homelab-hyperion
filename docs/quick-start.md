# Quick start

You need a Linux host on amd64 (the reference is Ubuntu 24.04) with Docker Engine and the Compose v2 plugin, a
user in the `docker` group, and the host ports the services use free ([installing.md](installing.md#requirements)).

1. **Get the stack.**

   ```sh
   git clone https://github.com/HoneyBearTech/homelab-hyperion.git && cd homelab-hyperion
   ```

   Check out the latest release (`git checkout vX.Y.Z`) and verify it first
   ([verifying-releases.md](verifying-releases.md)). Staying on `main` instead, as the maintainer's server does,
   means every merge is an upgrade ([upgrading.md](upgrading.md#following-main)).

2. **Configure it.**

   ```sh
   cp .env.example .env && chmod 600 .env
   ```

   In `.env`, set `TZ`, `PUID`/`PGID` (a user that can write your downloads directory), `DOWNLOADS_PATH`,
   `CONFIG_ROOT` (the directory that holds each app's folder, `<app>/config`, with its settings and data),
   `MINECRAFT_LEVEL_NAME` (the world's name), `MINECRAFT_ADDRESS` (this host's LAN address, for the players), and
   `MINECRAFT_EULA=TRUE` once you've read and accepted the [Minecraft EULA](https://www.minecraft.net/eula). Never
   point a path into `/var/lib/docker/volumes` ([installing.md](installing.md#where-data-lives)). Every setting is
   described in [interfaces.md](interfaces.md#settings).

   Optionally, for a notice each time autoheal restarts a container, put a webhook URL in `autoheal.env`
   (`cp autoheal.env.example autoheal.env && chmod 600 autoheal.env`).

3. **Create the apps' folders** as the `PUID`/`PGID` user, so Docker doesn't create them owned by root. Dozzle's
   is the exception: Dozzle runs as root, so Docker creates `CONFIG_ROOT/dozzle/config` for it on the first start.

   ```sh
   . ./.env && mkdir -p "$DOWNLOADS_PATH"
   for app in prowlarr qbittorrent heimdall minecraft; do
     mkdir -p "$CONFIG_ROOT/$app/config"
   done
   ```

4. **Check and start.**

   ```sh
   docker compose config --quiet   # the file resolves with your settings
   docker compose up -d --wait     # waits until every service reports healthy
   docker compose ps
   ```

5. **Finish each service's setup in its web UI** (ports in [interfaces.md](interfaces.md#services-and-ports)).
   qBittorrent prints a temporary web UI password in its log (`docker compose logs qbittorrent`): sign in and
   change it. In Prowlarr, set a login, add your indexers and connect the media apps. The Minecraft server's
   allowlist is on: until you name the players, nobody can join. Add each one with
   `docker compose exec minecraft send-command allowlist add "<gamer tag>"`. Players add the server by this host's
   address and port 19132; it doesn't appear in their LAN list.

To upgrade later, follow [upgrading.md](upgrading.md); it starts with a backup.
