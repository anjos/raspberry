---
name: arr-media-stack
description: Inspect, configure and troubleshoot the media automation stack on the raspberry server (Prowlarr, Radarr, Sonarr, Chaptarr, qBittorrent, Plex) through their HTTP APIs. Use for indexer sync problems, download clients, root folders, quality profiles, stuck imports, or wiring a new *arr app.
---

# *arr media stack operations

All wiring lives in the apps' config volumes, not in git. Change it through
the APIs (reproducible, scriptable), and mention UI-only steps to the owner.

## API access

`scripts/arr-api.sh <app> <path> [curl args...]` reads the app's API key
from its `/config/config.xml` inside the container and calls
`localhost:<port>/api/<ver>/<path>`. The key never gets printed.

```sh
S=.agents/skills/arr-media-stack/scripts
$S/arr-api.sh chaptarr health | jq -c '.[]|{source,message}'
$S/arr-api.sh prowlarr applications | jq -c '.[]|{name,implementation}'
$S/arr-api.sh radarr downloadclient | jq .
$S/arr-api.sh sonarr command -X POST -H 'Content-Type: application/json' -d '{"name":"CheckHealth"}'
```

| App      | Port | API  | Notes                                             |
| -------- | ---- | ---- | ------------------------------------------------- |
| radarr   | 7878 | v3   | root `/media/films`, qBit category `radarr`        |
| sonarr   | 8989 | v3   | root `/media/tv-shows`, qBit category `sonarr`     |
| chaptarr | 8789 | v1   | root `/media/books` (folderType 2 = ebook), category `chaptarr` |
| prowlarr | 9696 | v1   | pushes indexers to the apps above                  |

qBittorrent (8123) uses cookie auth: `POST /api/v2/auth/login` with
username/password from the owner, then `/api/v2/app/preferences`,
`/api/v2/torrents/info?category=X`.

## Recipes

- **Read a schema, then fill it**: `GET <thing>/schema`, select the
  implementation with jq, set `.fields[] | select(.name==...) .value`, POST
  it back. Add `?forceSave=true` to skip *warnings* (not errors).
- **Re-sync indexers**: Prowlarr `command` with
  `{"name":"ApplicationIndexerSync","forceSync":true}`. A sync running at the
  same time as app creation can create duplicates. Check the app's `indexer`
  list and delete the extra one.
- **Field names differ per app**: radarr `movieCategory`, sonarr
  `tvCategory`, chaptarr `ebookCategory`/`audiobookCategory`.
- Undocumented chaptarr API? Grep the UI bundle:
  `docker exec chaptarr sh -c 'grep -ho "fieldName.\{0,200\}" /app/UI/*.js'`.

## Gotchas

- Chaptarr is not a native Prowlarr app: register it as **Readarr** with
  `baseUrl http://chaptarr:8789`, categories 7000/7020/7040/7050/7060.
- Indexer pushes fail with 400 "no results in the configured categories"
  for indexers without book RSS (YTS, EZTV, LimeTorrents, TPB). That is
  expected, not breakage. Prowlarr *search* still finds books there.
- Health "Indexers have no definition": upstream removed the definition.
  Delete the indexer in Prowlarr, then test a replacement:
  `POST indexer/test` with the schema entry (match `definitionName` exactly,
  it is case-sensitive, e.g. `Knaben`), and `POST indexer` only if it passes.
  A full sync then removes or adds the copies in every app.
- qBittorrent 5.3 supports per-category share limits (`categories.json`:
  `ratio_limit`, `share_limit_action`). They are all "Default" (global) today.
- qBittorrent's share-limit action must stay **Stop**. "Remove with content"
  makes chaptarr reject the client and races radarr/sonarr imports.
- New chaptarr instances start with authentication "None". The owner sets
  the login on first UI visit.
- Hostnames inside the `media_network` bridge: `qbittorrent`, `prowlarr`,
  `radarr`, `sonarr`, `chaptarr`, `flaresolverr`. Plex is on the host network.
