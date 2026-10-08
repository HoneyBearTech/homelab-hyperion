# Quick start

> **Planned:** `compose.yaml` isn't in the repository yet, so step 4 has nothing to start. The steps are the
> ones the stack will use.

You need a Linux host on amd64 (the reference is Ubuntu 24.04) with Docker Engine and the Compose v2 plugin, a
user in the `docker` group, and the host ports the services use free ([installing.md](installing.md#requirements)).

1. **Get the stack.**

   ```sh
   git clone https://github.com/HoneyBearTech/homelab-hyperion.git && cd homelab-hyperion
   ```

   Once releases exist, check out the latest one (`git checkout vX.Y.Z`) and verify it first
   ([verifying-releases.md](verifying-releases.md)).

2. **Configure it.**

   ```sh
   cp .env.example .env && chmod 600 .env
   ```

   In `.env`, set `TZ`, `PUID`/`PGID` (a user that can write your downloads directory), `DOWNLOADS_PATH`, the
   data paths, and `MINECRAFT_EULA=TRUE` once you've read and accepted the
   [Minecraft EULA](https://www.minecraft.net/eula). Every setting is described in
   [interfaces.md](interfaces.md#settings).

3. **Create the data directories** as your user, so Docker doesn't create them owned by root:

   ```sh
   . ./.env && mkdir -p "$PROWLARR_CONFIG_PATH" "$QBITTORRENT_CONFIG_PATH" "$DOWNLOADS_PATH" \
     "$HEIMDALL_CONFIG_PATH" "$MINECRAFT_DATA_PATH"
   ```

4. **Check and start.**

   ```sh
   docker compose config --quiet   # the file resolves with your settings
   docker compose up -d --wait     # waits until every service reports healthy
   docker compose ps
   ```

5. **Finish each service's setup in its web UI** (ports in [interfaces.md](interfaces.md#services-and-ports)).
   qBittorrent prints a temporary web UI password in its log (`docker compose logs qbittorrent`): sign in and
   change it. In Prowlarr, set a login, add your indexers and connect the media apps. In the Minecraft server's
   `allowlist.json`, name the players who may join.

To upgrade later, follow [upgrading.md](upgrading.md); it starts with a backup.
