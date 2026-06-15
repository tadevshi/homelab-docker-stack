#!/usr/bin/env bash
#
# media/bootstrap.sh — wire Sonarr/Radarr/Jackett/Transmission.
#
# Requires: curl, jq. Install with: sudo apt install curl jq
# Or:        brew install curl jq
#
set -euo pipefail

# Dependency check is deferred to the main block so that `--help` works
# even if curl/jq are not installed (see the bottom of this file).

# --- URLs (overridable via --sonarr-url=... etc.) ----------------------------
SONARR_URL="${SONARR_URL:-http://localhost:8989}"
RADARR_URL="${RADARR_URL:-http://localhost:7878}"
JACKETT_URL="${JACKETT_URL:-http://localhost:9117}"          # host-side: where the bootstrap script calls Jackett from
JACKETT_BASE_URL="${JACKETT_BASE_URL:-http://jackett:9117}"    # container-side: what Sonarr/Radarr use to reach Jackett from inside their containers
TRANSMISSION_URL="${TRANSMISSION_URL:-http://localhost:9091}"
FLARESOLVERR_URL="${FLARESOLVERR_URL:-http://localhost:8191/}"               # host-side: where the bootstrap waits and probes from
FLARESOLVERR_BASE_URL="${FLARESOLVERR_BASE_URL:-http://flaresolverr:8191/}"  # container-side: what Jackett uses to reach FlareSolverr from inside its container

# --- API keys (REQUIRED; not stored in .env) ---------------------------------
# Defaulted to empty so --help works without keys. Validated in the main block.
SONARR_API_KEY="${SONARR_API_KEY:-}"
RADARR_API_KEY="${RADARR_API_KEY:-}"
JACKETT_API_KEY="${JACKETT_API_KEY:-}"

# --- Feature flags (defaults: profiles ON, jackett indexers OFF) ------------
ADD_QUALITY_PROFILES=1
ADD_JACKETT_INDEXERS=0

# --- Wait for service helper ------------------------------------------------
wait_for_url() {
  local url=$1 timeout=${2:-120} elapsed=0
  echo "→ waiting for $url (timeout ${timeout}s)"
  until curl -fsS --max-time 5 "$url" >/dev/null 2>&1; do
    sleep 2
    elapsed=$((elapsed+2))
    [[ $elapsed -ge $timeout ]] && { echo "ERROR: timeout waiting for $url" >&2; exit 1; }
  done
  echo "✓ $url is responsive"
}

# --- Retry helper for HTTP POSTs ---------------------------------------------
# Retries 3x with exponential backoff (2/4/8s) on HTTP 429 and 5xx. Hard-fails
# on other 4xx with the response body printed to stderr. On 2xx, returns 0
# and writes the response body to stdout.
#
# Usage: curl_post_json URL API_KEY BODY [MAX_ATTEMPTS]
curl_post_json() {
  local url=$1 api_key=$2 body=$3 max_attempts=${4:-3}
  local attempt=1 delay=2 response_file
  response_file=$(mktemp)
  while [[ $attempt -le $max_attempts ]]; do
    local http_code
    http_code=$(curl -sS -X POST \
      -H "X-Api-Key: $api_key" \
      -H "Content-Type: application/json" \
      -o "$response_file" \
      -w '%{http_code}' \
      -d "$body" \
      "$url" 2>/dev/null || echo "000")
    case "$http_code" in
      2*) cat "$response_file"; rm -f "$response_file"; return 0 ;;
      429|5*)
        echo "  attempt $attempt/$max_attempts: HTTP $http_code from $url, retrying in ${delay}s..." >&2
        sleep "$delay"
        delay=$((delay * 2))
        attempt=$((attempt + 1))
        ;;
      *)
        echo "ERROR: hard fail HTTP $http_code from POST $url" >&2
        cat "$response_file" >&2
        rm -f "$response_file"
        return 1
        ;;
    esac
  done
  rm -f "$response_file"
  echo "ERROR: max retries ($max_attempts) exceeded for POST $url" >&2
  return 1
}

# --- Configure Jackett's global FlareSolverr URL (idempotent) -------------
configure_jackett_flaresolverr() {
  echo "→ configuring FlareSolverr URL in Jackett"

  local current
  current=$(curl -fsS -H "X-Api-Key: $JACKETT_API_KEY" "$JACKETT_URL/api/v2.0/server/config" 2>/dev/null) || true

  if [[ -n "$current" ]] && echo "$current" | jq -e --arg u "$FLARESOLVERR_BASE_URL" '.FlareSolverrUrl == $u' >/dev/null 2>&1; then
    echo "✓ FlareSolverr URL already set in Jackett, skipping"
    return 0
  fi

  if [[ -n "$current" ]]; then
    local payload
    payload=$(echo "$current" | jq --arg u "$FLARESOLVERR_BASE_URL" '.FlareSolverrUrl = $u')
    if curl_post_json "$JACKETT_URL/api/v2.0/server/config" "$JACKETT_API_KEY" "$payload" >/dev/null; then
      echo "✓ FlareSolverr URL set in Jackett to $FLARESOLVERR_BASE_URL"
      return 0
    fi
  fi

  echo "→ API unavailable, configuring via container config file"
  if docker exec jackett sh -c "
    sed -i 's|\"FlareSolverrUrl\": *null|\"FlareSolverrUrl\": \"$FLARESOLVERR_BASE_URL\"|;
            s|\"FlareSolverrUrl\": *\"[^\"]*\"|\"FlareSolverrUrl\": \"$FLARESOLVERR_BASE_URL\"|' \
      /config/Jackett/ServerConfig.json
  " 2>/dev/null; then
    docker restart jackett >/dev/null 2>&1
    echo "✓ FlareSolverr URL set to $FLARESOLVERR_BASE_URL (via config file, Jackett restarted)"
  else
    echo "WARNING: failed to set FlareSolverr URL. Set it manually in Jackett UI > Settings > FlareSolverr URL = $FLARESOLVERR_BASE_URL" >&2
  fi
}

# --- Add download client to Sonarr ------------------------------------------
add_download_client_sonarr() {
  local name="Transmission"
  echo "→ adding Transmission download client to Sonarr"

  local existing
  existing=$(curl -fsS -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3/downloadclient")
  if echo "$existing" | jq -e --arg n "$name" '.[] | select(.name==$n)' >/dev/null 2>&1; then
    echo "✓ Transmission download client already exists in Sonarr, skipping"
    return 0
  fi

  local payload
  payload=$(jq -n \
    --arg host "transmission" \
    --arg category "tv-sonarr" \
    '{
      enable: true,
      priority: 1,
      name: "Transmission",
      implementation: "Transmission",
      implementationName: "Transmission",
      configContract: "TransmissionSettings",
      protocol: "torrent",
      removeCompletedDownloads: true,
      removeFailedDownloads: true,
      fields: [
        { name: "host",              value: $host },
        { name: "port",              value: 9091 },
        { name: "urlBase",           value: "/transmission/" },
        { name: "useSsl",            value: false },
        { name: "username",          value: "" },
        { name: "password",          value: "" },
        { name: "category",          value: $category },
        { name: "addPaused",         value: false },
        { name: "recentPriority",    value: "last" }
      ]
    }')

  if ! curl_post_json "$SONARR_URL/api/v3/downloadclient" "$SONARR_API_KEY" "$payload" >/dev/null; then
    echo "ERROR: failed to add Transmission download client to Sonarr" >&2
    return 1
  fi
  echo "✓ added Transmission download client to Sonarr"
}

# --- Add download client to Radarr ------------------------------------------
add_download_client_radarr() {
  local name="Transmission"
  echo "→ adding Transmission download client to Radarr"

  local existing
  existing=$(curl -fsS -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/downloadclient")
  if echo "$existing" | jq -e --arg n "$name" '.[] | select(.name==$n)' >/dev/null 2>&1; then
    echo "✓ Transmission download client already exists in Radarr, skipping"
    return 0
  fi

  local payload
  payload=$(jq -n \
    --arg host "transmission" \
    --arg category "radarr" \
    '{
      enable: true,
      priority: 1,
      name: "Transmission",
      implementation: "Transmission",
      implementationName: "Transmission",
      configContract: "TransmissionSettings",
      protocol: "torrent",
      removeCompletedDownloads: true,
      removeFailedDownloads: true,
      fields: [
        { name: "host",              value: $host },
        { name: "port",              value: 9091 },
        { name: "urlBase",           value: "/transmission/" },
        { name: "useSsl",            value: false },
        { name: "username",          value: "" },
        { name: "password",          value: "" },
        { name: "category",          value: $category },
        { name: "addPaused",         value: false },
        { name: "recentPriority",    value: "last" }
      ]
    }')

  if ! curl_post_json "$RADARR_URL/api/v3/downloadclient" "$RADARR_API_KEY" "$payload" >/dev/null; then
    echo "ERROR: failed to add Transmission download client to Radarr" >&2
    return 1
  fi
  echo "✓ added Transmission download client to Radarr"
}

# --- Add Jackett indexer to Sonarr -------------------------------------------
add_indexer_sonarr() {
  local name="Jackett"
  echo "→ adding Jackett indexer to Sonarr"

  local existing
  existing=$(curl -fsS -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3/indexer")
  if echo "$existing" | jq -e --arg n "$name" '.[] | select(.name==$n)' >/dev/null 2>&1; then
    echo "✓ Jackett indexer already exists in Sonarr, skipping"
    return 0
  fi

  local payload
  payload=$(jq -n \
    --arg baseUrl "${JACKETT_BASE_URL}/api/v2.0/indexers/all/results/torznab/" \
    --arg apiKey "$JACKETT_API_KEY" \
    '{
      enable: true,
      name: "Jackett",
      implementation: "Torznab",
      implementationName: "Torznab",
      configContract: "TorznabSettings",
      protocol: "torrent",
      priority: 25,
      downloadClientId: 0,
      fields: [
        { name: "baseUrl",         value: $baseUrl },
        { name: "apiPath",         value: "" },
        { name: "apiKey",          value: $apiKey },
        { name: "categories",      value: [5000, 5030, 5040, 5045, 5050, 5060, 5070, 5080] },
        { name: "animeCategories", value: [5070] },
        { name: "removeYear",      value: false },
        { name: "minimumSeeders",  value: 1 }
      ]
    }')

  if ! curl_post_json "$SONARR_URL/api/v3/indexer" "$SONARR_API_KEY" "$payload" >/dev/null; then
    echo "ERROR: failed to add Jackett indexer to Sonarr" >&2
    return 1
  fi
  echo "✓ added Jackett indexer to Sonarr"
}

# --- Add Jackett indexer to Radarr -------------------------------------------
add_indexer_radarr() {
  local name="Jackett"
  echo "→ adding Jackett indexer to Radarr"

  local existing
  existing=$(curl -fsS -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/indexer")
  if echo "$existing" | jq -e --arg n "$name" '.[] | select(.name==$n)' >/dev/null 2>&1; then
    echo "✓ Jackett indexer already exists in Radarr, skipping"
    return 0
  fi

  local payload
  payload=$(jq -n \
    --arg baseUrl "${JACKETT_BASE_URL}/api/v2.0/indexers/all/results/torznab/" \
    --arg apiKey "$JACKETT_API_KEY" \
    '{
      enable: true,
      name: "Jackett",
      implementation: "Torznab",
      implementationName: "Torznab",
      configContract: "TorznabSettings",
      protocol: "torrent",
      priority: 25,
      downloadClientId: 0,
      fields: [
        { name: "baseUrl",         value: $baseUrl },
        { name: "apiPath",         value: "" },
        { name: "apiKey",          value: $apiKey },
        { name: "categories",      value: [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060] },
        { name: "removeYear",      value: false },
        { name: "minimumSeeders",  value: 1 }
      ]
    }')

  if ! curl_post_json "$RADARR_URL/api/v3/indexer" "$RADARR_API_KEY" "$payload" >/dev/null; then
    echo "ERROR: failed to add Jackett indexer to Radarr" >&2
    return 1
  fi
  echo "✓ added Jackett indexer to Radarr"
}

# --- Add root folders --------------------------------------------------------
add_root_folders() {
  # Sonarr — /data/media/tv
  echo "→ adding root folder /data/media/tv to Sonarr"
  local existing_tv
  existing_tv=$(curl -fsS -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3/rootfolder")
  if echo "$existing_tv" | jq -e --arg p "/data/media/tv" '.[] | select(.path==$p)' >/dev/null 2>&1; then
    echo "✓ /data/media/tv root folder already exists in Sonarr, skipping"
  else
    local payload_tv
    payload_tv=$(jq -n '{path: "/data/media/tv"}')
    if ! curl_post_json "$SONARR_URL/api/v3/rootfolder" "$SONARR_API_KEY" "$payload_tv" >/dev/null; then
      echo "WARNING: failed to add /data/media/tv root folder to Sonarr" >&2
    else
      echo "✓ added /data/media/tv root folder to Sonarr"
    fi
  fi

  # Radarr — /data/media/movies
  echo "→ adding root folder /data/media/movies to Radarr"
  local existing_movies
  existing_movies=$(curl -fsS -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/rootfolder")
  if echo "$existing_movies" | jq -e --arg p "/data/media/movies" '.[] | select(.path==$p)' >/dev/null 2>&1; then
    echo "✓ /data/media/movies root folder already exists in Radarr, skipping"
  else
    local payload_movies
    payload_movies=$(jq -n '{path: "/data/media/movies"}')
    if ! curl_post_json "$RADARR_URL/api/v3/rootfolder" "$RADARR_API_KEY" "$payload_movies" >/dev/null; then
      echo "WARNING: failed to add /data/media/movies root folder to Radarr" >&2
    else
      echo "✓ added /data/media/movies root folder to Radarr"
    fi
  fi
}

# --- Add quality profiles (opt-in, best-effort) -----------------------------
add_quality_profiles() {
  echo "→ adding HD-1080p quality profiles"

  # Sonarr
  echo "→ adding HD-1080p quality profile to Sonarr"
  local existing_profile
  existing_profile=$(curl -fsS -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3/qualityprofile")
  if echo "$existing_profile" | jq -e --arg n "HD-1080p" '.[] | select(.name==$n)' >/dev/null 2>&1; then
    echo "✓ HD-1080p quality profile already exists in Sonarr, skipping"
  else
    local payload
    payload=$(jq -n '{
      name: "HD-1080p",
      upgradeAllowed: true,
      cutoff: 7,
      items: [
        { quality: { id: 1 },  allowed: true },
        { quality: { id: 2 },  allowed: true },
        { quality: { id: 4 },  allowed: true },
        { quality: { id: 7 },  allowed: true },
        { quality: { id: 8 },  allowed: true }
      ]
    }')
    if ! curl_post_json "$SONARR_URL/api/v3/qualityprofile" "$SONARR_API_KEY" "$payload" >/dev/null; then
      echo "WARNING: failed to add HD-1080p quality profile to Sonarr — skipping" >&2
    else
      echo "✓ added HD-1080p quality profile to Sonarr"
    fi
  fi

  # Radarr
  echo "→ adding HD-1080p quality profile to Radarr"
  existing_profile=$(curl -fsS -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/qualityprofile")
  if echo "$existing_profile" | jq -e --arg n "HD-1080p" '.[] | select(.name==$n)' >/dev/null 2>&1; then
    echo "✓ HD-1080p quality profile already exists in Radarr, skipping"
  else
    local payload
    payload=$(jq -n '{
      name: "HD-1080p",
      upgradeAllowed: true,
      cutoff: 7,
      items: [
        { quality: { id: 1 },  allowed: true },
        { quality: { id: 2 },  allowed: true },
        { quality: { id: 4 },  allowed: true },
        { quality: { id: 7 },  allowed: true },
        { quality: { id: 8 },  allowed: true }
      ]
    }')
    if ! curl_post_json "$RADARR_URL/api/v3/qualityprofile" "$RADARR_API_KEY" "$payload" >/dev/null; then
      echo "WARNING: failed to add HD-1080p quality profile to Radarr — skipping" >&2
    else
      echo "✓ added HD-1080p quality profile to Radarr"
    fi
  fi
}

# --- Add Jackett individual indexers (opt-in) --------------------------------
add_jackett_indexers() {
  echo "→ fetching configured Jackett indexers"

  local indexers
  indexers=$(curl -fsS \
    -H "X-Api-Key: $JACKETT_API_KEY" \
    "$JACKETT_URL/api/v2.0/indexers?configured=true" 2>&1) || {
    echo "WARNING: failed to fetch Jackett indexers — skipping" >&2
    return 0
  }

  local count
  count=$(echo "$indexers" | jq '.Indexers | length' 2>/dev/null || echo "0")
  if [[ "$count" -eq 0 ]] || [[ "$count" == "null" ]]; then
    echo "  no configured Jackett indexers found, skipping"
    return 0
  fi

  echo "  found $count configured indexer(s), adding to Sonarr and Radarr"

  echo "$indexers" | jq -r --arg jackettBaseUrl "$JACKETT_BASE_URL" --arg apiKey "$JACKETT_API_KEY" '
    .Indexers[] |
    "ADD_INDEXER=" + .name + " URL=" + $jackettBaseUrl + "/api/v2.0/indexers/" + .id + "/results/torznab/"
  ' | while IFS= read -r line; do
    idx_name=$(echo "$line" | sed 's/^ADD_INDEXER=//' | cut -d' ' -f1)
    idx_url=$(echo "$line" | sed 's/.*URL=//')

    # Sonarr
    echo "→ adding Jackett: $idx_name to Sonarr"
    existing_sonarr=$(curl -fsS -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3/indexer")
    if echo "$existing_sonarr" | jq -e --arg n "Jackett: $idx_name" '.[] | select(.name==$n)' >/dev/null 2>&1; then
      echo "✓ Jackett: $idx_name already exists in Sonarr, skipping"
    else
      payload=$(jq -n \
        --arg name "Jackett: $idx_name" \
        --arg baseUrl "$idx_url" \
        --arg apiKey "$JACKETT_API_KEY" \
        '{
          enable: true,
          name: $name,
          implementation: "Torznab",
          implementationName: "Torznab",
          configContract: "TorznabSettings",
          protocol: "torrent",
          priority: 25,
          downloadClientId: 0,
          fields: [
            { name: "baseUrl",     value: $baseUrl },
            { name: "apiPath",     value: "" },
            { name: "apiKey",      value: $apiKey },
            { name: "categories",  value: [5000, 5030, 5040, 5045, 5050, 5060, 5070, 5080] },
            { name: "animeCategories", value: [5070] },
            { name: "removeYear",  value: false },
            { name: "minimumSeeders", value: 1 }
          ]
        }')
      if ! curl_post_json "$SONARR_URL/api/v3/indexer" "$SONARR_API_KEY" "$payload" >/dev/null; then
        echo "WARNING: failed to add Jackett: $idx_name to Sonarr" >&2
      else
        echo "✓ added Jackett: $idx_name to Sonarr"
      fi
    fi

    # Radarr
    echo "→ adding Jackett: $idx_name to Radarr"
    existing_radarr=$(curl -fsS -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/indexer")
    if echo "$existing_radarr" | jq -e --arg n "Jackett: $idx_name" '.[] | select(.name==$n)' >/dev/null 2>&1; then
      echo "✓ Jackett: $idx_name already exists in Radarr, skipping"
    else
      payload=$(jq -n \
        --arg name "Jackett: $idx_name" \
        --arg baseUrl "$idx_url" \
        --arg apiKey "$JACKETT_API_KEY" \
        '{
          enable: true,
          name: $name,
          implementation: "Torznab",
          implementationName: "Torznab",
          configContract: "TorznabSettings",
          protocol: "torrent",
          priority: 25,
          downloadClientId: 0,
          fields: [
            { name: "baseUrl",     value: $baseUrl },
            { name: "apiPath",     value: "" },
            { name: "apiKey",      value: $apiKey },
            { name: "categories",  value: [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060] },
            { name: "removeYear",  value: false },
            { name: "minimumSeeders", value: 1 }
          ]
        }')
      if ! curl_post_json "$RADARR_URL/api/v3/indexer" "$RADARR_API_KEY" "$payload" >/dev/null; then
        echo "WARNING: failed to add Jackett: $idx_name to Radarr" >&2
      else
        echo "✓ added Jackett: $idx_name to Radarr"
      fi
    fi
  done
}

# --- Usage ------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Wire Sonarr, Radarr, Jackett, and Transmission via their REST APIs.

Requires API keys from each service (Settings > General > API Key).

Options:
  --sonarr-url=<url>      Sonarr URL  [default: http://localhost:8989]
  --radarr-url=<url>       Radarr URL  [default: http://localhost:7878]
  --jackett-url=<url>     Jackett URL (host-side)  [default: http://localhost:9117]
  --jackett-base-url=<url> Jackett URL (container-side, used for indexer baseUrl
                            registered in Sonarr/Radarr)
                            [default: http://jackett:9117]
  --flaresolverr-url=<url> FlareSolverr URL (host-side, used by this script to
                            wait for and probe the service)
                            [default: http://localhost:8191]
  --flaresolverr-base-url=<url> FlareSolverr URL (container-side, registered in
                            Jackett's global FlareSolverr setting)
                            [default: http://flaresolverr:8191/]
  --transmission-url=<url> Transmission URL [default: http://localhost:9091]
  --sonarr-key=<key>      Sonarr API key   (required)
  --radarr-key=<key>      Radarr API key   (required)
  --jackett-key=<key>     Jackett API key  (required)
  --no-quality-profiles   Skip quality profile creation
  --jackett-indexers      Also add each Jackett indexer individually
  -h, --help              Show this help

Examples:
  SONARR_API_KEY=... RADARR_API_KEY=... JACKETT_API_KEY=... \\
    ./media/bootstrap.sh

  ./media/bootstrap.sh \\
    --sonarr-key=... --radarr-key=... --jackett-key=... \\
    --jackett-indexers
EOF
}

# --- CLI flag parser --------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sonarr-url=*)         SONARR_URL="${1#*=}" ;;
    --radarr-url=*)         RADARR_URL="${1#*=}" ;;
    --jackett-url=*)        JACKETT_URL="${1#*=}" ;;
    --jackett-base-url=*)   JACKETT_BASE_URL="${1#*=}" ;;
    --transmission-url=*)   TRANSMISSION_URL="${1#*=}" ;;
    --flaresolverr-url=*)        FLARESOLVERR_URL="${1#*=}" ;;
    --flaresolverr-base-url=*)   FLARESOLVERR_BASE_URL="${1#*=}" ;;
    --sonarr-key=*)         SONARR_API_KEY="${1#*=}" ;;
    --radarr-key=*)         RADARR_API_KEY="${1#*=}" ;;
    --jackett-key=*)        JACKETT_API_KEY="${1#*=}" ;;
    --no-quality-profiles)  ADD_QUALITY_PROFILES=0 ;;
    --jackett-indexers)     ADD_JACKETT_INDEXERS=1 ;;
    -h|--help)              usage; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

# --- Main -------------------------------------------------------------------
# API keys: required to actually do work, but checked here so --help can exit
# before the user has to set them.
: "${SONARR_API_KEY:?SONARR_API_KEY is required (get it from Sonarr Settings > General > API Key)}"
: "${RADARR_API_KEY:?RADARR_API_KEY is required (get it from Radarr Settings > General > API Key)}"
: "${JACKETT_API_KEY:?JACKETT_API_KEY is required (get it from Jackett UI, top-right key icon)}"

for dep in curl jq; do
  command -v "$dep" >/dev/null 2>&1 || { echo "ERROR: '$dep' is required but not installed." >&2; exit 1; }
done

echo "=== Media Bootstrap ==="

echo "→ waiting for Sonarr (timeout 120s)"
sonarr_tries=60
until curl -fsS --max-time 5 -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3/system/status" >/dev/null 2>&1; do
  sleep 2; sonarr_tries=$((sonarr_tries-2))
  [[ $sonarr_tries -le 0 ]] && { echo "ERROR: timeout waiting for Sonarr" >&2; exit 1; }
done
echo "✓ Sonarr is responsive"

echo "→ waiting for Radarr (timeout 120s)"
radarr_tries=60
until curl -fsS --max-time 5 -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/system/status" >/dev/null 2>&1; do
  sleep 2; radarr_tries=$((radarr_tries-2))
  [[ $radarr_tries -le 0 ]] && { echo "ERROR: timeout waiting for Radarr" >&2; exit 1; }
done
echo "✓ Radarr is responsive"

wait_for_url "$JACKETT_URL/api/v2.0/indexers?configured=true"

# Transmission health: accept any 2xx/4xx as "up" (auth required on first call)
echo "→ waiting for Transmission (timeout 120s)"
tx_tries=60
until curl -sS -o /dev/null -w '%{http_code}' "$TRANSMISSION_URL/transmission/rpc" 2>/dev/null | grep -qE '^(2[0-9][0-9]|4[0-9][0-9])$'; do
  sleep 2
  tx_tries=$((tx_tries - 1))
  [[ $tx_tries -le 0 ]] && { echo "ERROR: Transmission not responsive"; exit 1; }
done
echo "✓ Transmission is responsive"

# FlareSolverr is optional but, if present in the stack, must be up before we POST to Jackett.
if curl -fsS --max-time 2 "http://localhost:8191/health" >/dev/null 2>&1; then
  # Container is up — wait until /health responds (timeout 180s for first-boot Chrome init)
  wait_for_url "http://localhost:8191/health" 180
else
  # Port 8191 is not even listening — assume FlareSolverr is not deployed in this stack
  echo "→ FlareSolverr not reachable on :8191, skipping FlareSolverr configuration"
fi

echo ""
# configure FlareSolverr before Sonarr/Radarr start using Jackett for indexer hits
configure_jackett_flaresolverr
add_download_client_sonarr
add_download_client_radarr
add_indexer_sonarr
add_indexer_radarr
add_root_folders

[[ "$ADD_QUALITY_PROFILES" == "1" ]] && add_quality_profiles
[[ "$ADD_JACKETT_INDEXERS" == "1" ]] && add_jackett_indexers

echo ""
echo "Done. All services wired."