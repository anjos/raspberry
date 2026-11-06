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
| `docker/status/` | Hourly status job for the index page (certificates, Pi health, alert) |
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
| `proxy`      | caddy (HTTPS front door for the web UIs, see below), status (index page data) |

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
  `caddy:latest`. diun can't track it (`diun.enable=false`), so `./manage.sh update`
  rebuilds it (`./manage.sh build` alone doesn't deploy). It builds with `--no-cache`,
  because cached layers would hide new plugin versions, so every update recreates
  caddy and drops the UIs for a moment. Run it with no arguments or for `proxy`.
- The `status` container (a small Alpine image, `docker/status/`) runs `status.sh`
  hourly and writes `status.json` and `health.json` to the `proxy_status` volume for the
  index page, which reads them at `/status.json` and `/health.json`. `proxy_status` is
  tmpfs (1 MB, compose-managed, not backed up), so history restarts with the container.
- Certificates are read from what caddy serves, so the container needs no access
  to `proxy_caddy` and its keys. Caddy's `/build.json`, baked into its image, gives
  the build time and version; "update available" compares that date with the
  `caddy:latest` push on Docker Hub, so a republished image can flag with no real change.
- A Pushover alert goes out, once a day, when a certificate has under `ALERT_DAYS` (7)
  left, or none can be read. Caddy renews at about two thirds of the lifetime, so an
  alert means renewal has been failing for weeks.
- `status` has network access and the Pushover token, so it mounts only what it
  reads. **Never mount `/` or `/run` into it**: a read-only mount still lets a process
  connect to `/run/docker.sock`, and `/` would expose `.envrc` and SSH keys. Gauges
  are averages since the previous sample. `/host` is just enough of a root to run the
  host's `apt list --upgradable`, which only reads the lists kept fresh by
  `apt-daily.timer`. `/host/sys/class/net/*/statistics` shows the host's interfaces;
  `/host/proc/net` wouldn't.
- Reboot detection compares the running kernel with the newest installed one of the
  same flavour. `vcgencmd get_throttled` needs the host: past throttling isn't shown.

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
- **Fail Downloads**: every radarr and sonarr indexer has `failDownloads: [0,1]`
  (Executables + Potentially Dangerous). Without it, a fake release (`<title>.exe`)
  stays in the queue at `importPending` forever with "Caution: Found executable file",
  even though qBittorrent's Pushover says it finished. With it, the release is failed,
  blocklisted and replaced. Prowlarr doesn't manage this field, but a **newly added
  indexer starts empty**, so set it there too. Chaptarr has no such setting. Don't add
  `*.exe` to qBittorrent's excluded file names: it would likely leave an empty "complete"
  torrent, which the check can't see. Sonarr can grab fakes of unaired episodes.
- Each *arr's Settings -> General -> Application URL is its https name
  (e.g. `https://radarr.anjos.fyi`), so links in Pushover notifications
  open the https UI.
- Chaptarr (a Readarr fork, `chaptarr/chaptarr`, not linuxserver) uses API
  `/api/v1`, while radarr/sonarr use `/api/v3`. Its quality profile "E-Book"
  allows EPUB only, since the owner reads in Apple Books (EPUB/PDF only). There is
  no book web reader: the owner copies EPUBs to a Mac (`open -a Books`).

Use the `arr-media-stack` skill for API access and troubleshooting.

### Homebridge (config in the `smarthome_homebridge` volume, not in this repo)

- The Office Monitor (Samsung M8 `LS32BM801UUXEN`, Tizen, on Wi-Fi at `192.168.1.9`, MAC
  `54:44:A3:81:F2:AE`) is controlled over the LAN by `homebridge-samsung-tizen`, which needs
  that address fixed by a DHCP reservation. It replaced `homebridge-smartthings-tv` on
  2026-11-06, because SmartThings API access is now paid ($4.99/month) and PATs expire on
  2026-12-15. Don't reintroduce a SmartThings cloud integration: the Tizen plugin's optional
  SmartThings features would need that paid plan too.
- The plugin doesn't support child bridges: leave that option off, or the monitor won't appear
  in Home. Its accessory is external, so it's paired in the Home app on its own, and changing
  the plugin's config restarts all of Homebridge, briefly dropping HomeKit lights.

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

- `manage.sh` does not source `.envrc` (direnv does), so `source .envrc` first
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
