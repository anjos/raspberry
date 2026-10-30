#!/usr/bin/env bash
# Usage: arr-api.sh <radarr|sonarr|chaptarr|prowlarr> <api-path> [curl args...]
# Calls the app's local API with the key read from its container config.
set -euo pipefail

app="${1:?app name required}"
path="${2:?api path required}"
shift 2

case "${app}" in
    radarr)   port=7878; ver=v3 ;;
    sonarr)   port=8989; ver=v3 ;;
    chaptarr) port=8789; ver=v1 ;;
    prowlarr) port=9696; ver=v1 ;;
    *) echo "unknown app: ${app}" >&2; exit 1 ;;
esac

key=$(docker exec "${app}" sh -c "sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' /config/config.xml")
exec curl -s -H "X-Api-Key: ${key}" "$@" "http://localhost:${port}/api/${ver}/${path#/}"
