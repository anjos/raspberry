---
name: add-docker-service
description: Add or change a service in the raspberry home-server Docker Compose stacks (docker/*.yml) without clashing with existing ones. Use when deploying a new container, moving a service between stacks, or editing compose files in this repo.
---

# Add a Docker service to the raspberry stacks

Read `AGENTS.md` first (conventions, port map, media layout). Then follow this
checklist in order.

## 1. Research the image

- Prefer `lscr.io/linuxserver/<app>`. Otherwise confirm the image is
  maintained and has an **arm64** build:
  `curl -s 'https://hub.docker.com/v2/repositories/<ns>/<repo>/tags?page_size=5' | jq -r '.results[]|"\(.name) \(.last_updated) \([.images[].architecture]|join(","))"'`
- `docker pull` it, then inspect it **before** writing compose:
  ```sh
  docker image inspect IMG --format '{{json .Config}}' | jq '{Env,ExposedPorts,Entrypoint,Cmd,User,Healthcheck}'
  docker run --rm --entrypoint sh IMG -c 'which curl wget; cat /entrypoint.sh 2>/dev/null | head -50'
  ```
  This tells you the port, whether PUID/PGID are honoured, and which HTTP tool
  exists for the healthcheck.

## 2. Pick stack, port, paths

- Stack: the one whose services it must talk to (shared `network` bridge,
  resolve by hostname). The only cross-stack member is caddy (`proxy`), which
  joins the other stacks' networks as external networks.
- Port: must not appear in `ss -tlnpu` or the AGENTS.md port map.
- Data under `/media`: mount `/media:/media` like radarr/sonarr so paths match
  qbittorrent's (`/media/downloads`). Create new library dirs as uid 1000
  (`mkdir -p /media/<dir>` as the `andre` user).

## 3. Edit compose (copy the shape of a sibling service)

```yaml
  # One-line description of what it is
  app:
    image: lscr.io/linuxserver/app:latest
    container_name: app
    restart: unless-stopped
    hostname: app
    networks:
      - network
    ports:
      - NNNN:NNNN
    healthcheck:
      test: curl --fail localhost:NNNN || exit 1   # wget --spider --quiet if no curl
      interval: 60s
      retries: 5
      start_period: 30s
      timeout: 2s
    environment:
      - TZ=${TZ}
      - PUID=${PUID}
      - PGID=${PGID}
    volumes:
      - <stack>_app:/config
```

Add `<stack>_app: {external: true}` (block style, like the file) under
`volumes:`, and the same volume to **`backup.yml`** (mount at
`/data/<stack>_app` + `volumes:` entry). Update the AGENTS.md tables.

## 4. Deploy safely

```sh
cd docker && source .envrc
docker volume create <stack>_app
docker compose -f <stack>.yml -p <stack> config --quiet
docker compose -f <stack>.yml -p <stack> up --detach --dry-run   # must only Create/Recreate what you expect
docker compose -f <stack>.yml -p <stack> up --detach
docker inspect -f '{{.State.Health.Status}}' app                 # wait for healthy
docker compose -f backup.yml -p backup up --detach               # not 02:00-04:30
docker exec rsnapshot ls /data/                                  # new volume listed
```

## 5. Finish

- Configure the app (API where possible). Any credentials come from the
  owner; never read them out of other apps' databases, and never commit them.
- If it has a web UI, publish it over HTTPS: `handle` in the `*.anjos.fyi`
  Caddyfile block, index tile (see AGENTS.md "HTTPS"). If it's an *arr, set its Application URL
  to the https name. Wire it to other services by `http://<container>:<port>`,
  never by the https name.
- Commit with a scope prefix, e.g. `media: add <app>`.
- Record new gotchas in AGENTS.md or a skill.
