# AGENTS.md

Guidance for AI agents maintaining this repository. `CLAUDE.md` is a symlink to
this file, and `.claude/skills` is a symlink to `.agents/skills`.

**Keep this file and the skills current.** When you learn something
non-obvious about this server (a gotcha, a new service, a changed convention),
update this file or the relevant skill in the same change. Remove anything
that turns out to be wrong.

## What this is

Configuration for a home server: a Raspberry Pi 5 (`raspberry`, arm64,
192.168.1.27) on the home intranet. **No service is exposed to the internet,
and that is intentional.** Never add port forwarding, tunnels (cloudflared,
tailscale funnel, ngrok), or anything else that makes a service reachable from
outside the LAN. Public certificates are fine only through the DNS-01 challenge,
which needs no inbound access.

| Directory     | Contents                                                        |
| ------------- | --------------------------------------------------------------- |
| `docker/`     | Docker Compose stacks (one `<stack>.yml` per stack) + `manage.sh` |
| `docker/zigbee2mqtt/` | Zigbee2MQTT config/automations bind-mounted into the container (see its README) |
| `docker/caddy/` | Caddyfile, Dockerfile (Caddy + DNS plugin), service index page (HTTPS) |
| `scenes/`     | Zigbee light scenes + `reset.py` (pixi project)                   |
| `firmware/`   | Zigbee dongle firmware + flashing tasks (pixi project)            |

## Docker stacks

Deploy with `docker/manage.sh` (`./manage.sh help`). The project name is the
file's basename: `media.yml` -> project `media`, network `media_network`.

| Stack        | Services                                                                 |
| ------------ | ------------------------------------------------------------------------ |
| `media`      | plex, qbittorrent, radarr (films), sonarr (TV), chaptarr (ebooks), prowlarr, flaresolverr |
| `smarthome`  | mosquitto, zigbee2mqtt, homebridge                                        |
| `monitor`    | diun (image update notifications), monocker (health notifications)       |
| `backup`     | rsnapshot (backs up every named volume to `/backup`)                      |
| `proxy`      | caddy (HTTPS front door for the web UIs, see below)                       |

### Port map (check before adding anything)

| Port            | Service                  | Port        | Service              |
| --------------- | ------------------------ | ----------- | -------------------- |
| 22              | host sshd                | 8191        | flaresolverr         |
| 80, 443 (+443/udp) | caddy                 | 8581 (host) | homebridge           |
| 1883            | mosquitto (9001 published but unused) | 2019 (in container) | caddy admin |
| 6881 tcp/udp    | qbittorrent (torrenting) | 8789        | chaptarr             |
| 7878            | radarr                   | 8989        | sonarr               |
| 8080            | zigbee2mqtt              | 9696        | prowlarr             |
| 8123            | qbittorrent web UI       | 32400 (host)| plex (+ udp 324xx)   |

Verify live with `ss -tlnpu` and `docker ps --format '{{.Names}}\t{{.Ports}}'`.

### Conventions (follow them for every new service)

- Prefer `lscr.io/linuxserver/*:latest` images (multi-arch, PUID/PGID/TZ).
  Images must have an arm64 build. `:latest` is fine, since diun reports updates.
- Each service sets `container_name` and `hostname` to its own name,
  `restart: unless-stopped` (`always` for smarthome), and a `healthcheck` with
  the stack's usual timings. monocker alerts on unhealthy containers, so the
  test command must exist in the image (`curl` vs `wget`).
- Environment: `TZ=${TZ}`, `PUID=${PUID}`, `PGID=${PGID}`, all from
  `docker/.envrc`.
- Config lives in a **named external volume** `<stack>_<service>` created by
  hand (`docker volume create`). Every such volume must also be added to
  `backup.yml` (mounted at `/data/<volume>` plus a `volumes:` entry).
- Services in a stack share the stack's `network` bridge and reach each other
  by hostname (e.g. `http://qbittorrent:8123`). `network_mode: host` is only
  for things that need discovery/multicast (plex, homebridge).
- Short comment above each service saying what it is.

### HTTPS (`proxy` stack, caddy)

- `https://anjos.fyi` is a tile index (`docker/caddy/site/index.html`), and each
  web UI is at `https://<service>.anjos.fyi`. The `http://raspberry.local:<port>`
  URLs still work.
- Certificates are public **Let's Encrypt** ones, obtained with the **DNS-01**
  challenge, so no device setup and no inbound port is needed. Caddy creates the
  TXT records through the Cloudflare API and renews on its own. HTTP-01 and
  TLS-ALPN need inbound access, so never use them. Issued hostnames land in public
  Certificate Transparency logs, so keep to the wildcard: per-service certificates
  would publish every service name.
- The domain `anjos.fyi` is registered and hosted at Cloudflare, with two **DNS only
  (grey cloud)** records: `@` and `*` -> `192.168.1.27`. They're public, but a private
  address leads nowhere from outside the LAN. They rely on the Pi keeping that
  address through a DHCP reservation on the router (MAC `d8:3a:dd:de:7e:76`). If the
  address changes, edit both records.
- `CF_API_TOKEN` (`docker/.envrc`) is limited to the `anjos.fyi` zone, with Zone Read
  and DNS Edit. `docker compose config` prints it, so always pass `--quiet`.
  Cloudflare's `user/tokens/verify` returns false for it even though it works.
- Caddy is a local image (`docker/caddy/Dockerfile`), since the DNS plugin isn't in
  `caddy:latest`. diun can't track it (`diun.enable=false`), so update it now and
  then: `docker compose -f proxy.yml -p proxy build --pull && ./manage.sh up proxy`.
- **Services never talk to each other through the https names.** Use
  `http://<container>:<port>` (or `localhost`/`raspberry` from host-network
  containers). The https names are for people only.
- Short aliases redirect (302) to the full name, so each app keeps one origin. The
  aliases are qbt, radr, sonr, chaptr, prowlr, z2m and hb (plex has none). Unknown
  `*.anjos.fyi` names get the connection closed.
- To add a UI: add `@name host` + `handle @name` lines to the `*.anjos.fyi` block
  (no DNS change, the wildcard covers it), a tile in `index.html` (SVG from
  homarr-labs/dashboard-icons into `site/icons/`, `--c` set to the icon's dominant
  brand colour), then
  `docker exec caddy caddy reload --config /etc/caddy/Caddyfile`. The caddy
  container joins `media_network` and `smarthome_network` (external) and reaches
  host-network services via `host.docker.internal`.
- Radarr, Sonarr and Prowlarr ignore `X-Forwarded-Proto` and redirect to
  `http://`, so their Caddyfile blocks rewrite `Location` with
  `header_down Location ^http:// https://`. Chaptarr doesn't need it.
- `443/udp` must be published: caddy advertises HTTP/3 (`alt-svc: h3`) and
  browsers remember that for 30 days.
- A caddy reload or restart drops the websockets of the Homebridge and
  Zigbee2MQTT UIs, which then reconnect (the UI flickers briefly).
- The caddy healthcheck must use `127.0.0.1:2019`, not `localhost`: busybox wget
  tries `::1` and the admin API only listens on IPv4.

### Secrets

`docker/.envrc` holds secrets (Plex claim, Pushover tokens, Cloudflare API token) and is
gitignored. Never commit it, copy its values into tracked files, or print them.
Application credentials live in the owner's personal notes; ask for them
rather than digging them out of app databases.

### Media layout (`/media`, 4 TB USB SSD, see memory on USB3 port)

```
/media/downloads            qbittorrent save path (incomplete/ = temp path)
/media/films                radarr root folder   -> plex
/media/tv-shows             sonarr root folder   -> plex
/media/books                chaptarr root folder (EPUB only, for Apple Books)
/media/{cartoons,concerts,...}  manually managed, plex only
```

The *arrs mount `/media:/media` and qbittorrent mounts
`/media/downloads:/media/downloads`, so paths are identical in every container
(no remote path mappings) and imports are hardlinks on one filesystem.
`/var/lib/plex-transcode` keeps transcoding off the media drive.

### Media automation wiring (stored in config volumes, not in this repo)

- **Prowlarr** holds the indexers and pushes them to radarr, sonarr and
  chaptarr (Settings -> Apps). Chaptarr is registered as a **Readarr**-type app
  (Prowlarr has no Chaptarr type), with sync categories 7000/7020/7040/7050/7060.
  Indexers that return no book results (YTS, EZTV, LimeTorrents, TPB...) get
  rejected by chaptarr's test, which is expected.
- **qBittorrent** categories: `radarr`, `sonarr`, `chaptarr`, plus `prowlarr`
  for manual grabs from Prowlarr's search page. Nothing imports or removes those
  automatically; tidy them by hand. Share limits are
  ratio 0.1 / 360 min with action **Stop**. Each *arr has "Remove completed
  downloads" on and deletes the torrent after import. Don't switch the action
  back to "Remove (with content)": the *arrs refuse it, and it races imports.
- Each *arr's Settings -> General -> Application URL is its https name
  (e.g. `https://radarr.anjos.fyi`), so links in Pushover notifications
  open the https UI.
- Chaptarr (a Readarr fork, `chaptarr/chaptarr`, not linuxserver) uses API
  `/api/v1`, while radarr/sonarr use `/api/v3`. Its quality profile "E-Book"
  allows EPUB only, since the owner reads in Apple Books (EPUB/PDF only). There is
  no book web reader: the owner copies EPUBs to a Mac (`open -a Books`).

Use the `arr-media-stack` skill for API access and troubleshooting.

## Workflow rules

- Validate before deploying:
  `source .envrc && docker compose -f X.yml -p X config --quiet` and
  `... up --detach --dry-run`. The dry run shows exactly which containers
  will be recreated, so confirm it only touches what you intend.
- `docker compose up -d` on a stack recreates only changed services. Still,
  recreating smarthome services drops lights/automations briefly, and recreating
  plex interrupts playback.
- rsnapshot runs 02:00 (monthly), 03:00 (Mon, weekly), 04:00 (daily), so avoid
  recreating it then.
- Commits: conventional style scoped by area, e.g. `media: ...`,
  `media(fix): ...`, `scenes: ...`, `smarthome: ...`.

## Known issues / leftovers

- `manage.sh`: `update()` echoes unset `${stack}`/`${file}` (cosmetic).
  `manage.sh` does not source `.envrc` (direnv does), so `source .envrc` first
  when running it outside a direnv-enabled shell.
- `/dev/dri` in plex is a no-op on the Pi (no HW transcoding).
- Prowlarr indexers kickasstorrents.{to,ws} and EZTV have been failing
  long-term.
- Indexer history: TheRARBG was removed upstream from Prowlarr's definitions
  (2025-10) and replaced here by Knaben (meta-search) on 2026-10-30. EBookBay
  (`ebb.la`) serves a certificate for another domain, so it can't be used.
  An "Indexers have no definition" health warning means upstream dropped that
  indexer: delete it and pick a replacement from `indexer/schema`.
- Deluge was fully removed on 2026-10-30. Old `media_deluge` copies remain
  only in rsnapshot snapshots under `/backup` until they rotate out (~12 months).
