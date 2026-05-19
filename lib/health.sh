#!/usr/bin/env bash
# Upstream platform health probe for watch-cli.
#
# Catches "yt-dlp can't reach this platform today" before the user
# wastes 30+ seconds on a doomed download. Not a gate — emits a stderr
# warning and lets the caller proceed (a stale canary URL is also a
# possible cause of a failed probe).
#
# Cache: /tmp/watch-cli-health/<domain>.<status> where status is `ok`
# or `fail`. TTL is 24h based on file mtime. Cached `ok` is silent.
# Cached `fail` re-emits the warning so the user sees it on every
# attempt within the window.

[[ -n "${WATCH_CLI_HEALTH_LOADED:-}" ]] && return 0
export WATCH_CLI_HEALTH_LOADED=1

WATCH_HEALTH_CACHE_DIR="${WATCH_HEALTH_CACHE_DIR:-/tmp/watch-cli-health}"
WATCH_HEALTH_TTL_SECONDS="${WATCH_HEALTH_TTL_SECONDS:-86400}"  # 24h.
WATCH_HEALTH_TIMEOUT_SECONDS="${WATCH_HEALTH_TIMEOUT_SECONDS:-5}"

# Map of domain → canary URL.
#
# Canaries are famous, public, evergreen videos that have been online
# for years and are unlikely to be deleted by the uploader. The probe
# fails ⇒ yt-dlp's extractor for this platform is broken today, not
# this specific URL.
#
# Update notes for future maintainers:
#   - YouTube: Rick Astley's "Never Gonna Give You Up" — uploaded
#     Oct 2009, still online 17+ years later.
#   - TikTok: Bella Poarch's "M to the B" — uploaded Aug 2020, the
#     most-liked TikTok of all time.
#   - X / Twitter: a permanent post from X's own @X account.
#   - Reddit: r/announcements top-pinned video from the platform.
#   - Vimeo: Vimeo Staff Pick "The Mountain" — 2011, frequently
#     cited as a stable Vimeo example.
#   - Facebook: Meta's own public Facebook page videos.
#   - LinkedIn: skipped — LinkedIn posts are gated even for public ones
#     and produce 401s without cookies. Probe would always fail.
_health_canary_for() {
  case "$1" in
    *youtube.com|youtu.be|*.youtube.com)
      echo "https://www.youtube.com/watch?v=dQw4w9WgXcQ" ;;
    *tiktok.com|*.tiktok.com)
      echo "https://www.tiktok.com/@bellapoarch/video/6862153058223197445" ;;
    *twitter.com|*x.com|*.twitter.com|*.x.com)
      echo "https://x.com/X/status/1631674123581607937" ;;
    *reddit.com|*.reddit.com)
      echo "https://www.reddit.com/r/announcements/" ;;
    *vimeo.com|*.vimeo.com)
      echo "https://vimeo.com/22439234" ;;
    *facebook.com|*.facebook.com|*fb.watch)
      echo "https://www.facebook.com/Meta/videos" ;;
    *)
      # No canary for this domain → skip the probe.
      return 1 ;;
  esac
}

# Strip protocol + path → bare hostname.
_health_domain_from_url() {
  local url="$1"
  local h
  h="${url#http://}"; h="${h#https://}"
  h="${h%%/*}"
  # Strip leading www. for cache stability across www / non-www.
  h="${h#www.}"
  printf '%s' "$h"
}

# Returns 0 if cache hit within TTL, 1 otherwise. Echoes the cached
# status (`ok` / `fail`) on stdout when fresh.
_health_cache_lookup() {
  local domain="$1"
  local f
  for status in ok fail; do
    f="$WATCH_HEALTH_CACHE_DIR/${domain}.${status}"
    if [[ -f "$f" ]]; then
      local mtime now age
      # `stat -c %Y` is GNU; `stat -f %m` is BSD/macOS. Try both.
      if mtime="$(stat -c %Y "$f" 2>/dev/null)" && [[ -n "$mtime" ]]; then
        :
      else
        mtime="$(stat -f %m "$f" 2>/dev/null || echo 0)"
      fi
      now="$(date +%s)"
      age=$((now - mtime))
      if (( age < WATCH_HEALTH_TTL_SECONDS )); then
        printf '%s' "$status"
        return 0
      fi
      # Stale — remove so the next call rewrites it.
      rm -f "$f"
    fi
  done
  return 1
}

# Run the actual yt-dlp simulate probe. Returns 0/1.
_health_run_probe() {
  local url="$1"
  # --simulate skips download, --quiet suppresses noise, --skip-download
  # is belt-and-suspenders. 5s timeout via the env var.
  if command -v timeout >/dev/null 2>&1; then
    timeout "$WATCH_HEALTH_TIMEOUT_SECONDS" \
      yt-dlp --simulate --quiet --skip-download --no-warnings "$url" \
      >/dev/null 2>&1
    return $?
  fi
  # macOS has no `timeout` by default. `gtimeout` from coreutils or a
  # background-PID-kill workaround would both fit; for simplicity skip
  # timeout-enforcement on those hosts and trust yt-dlp to fail fast on
  # a broken extractor (it usually does within 1-2s).
  yt-dlp --simulate --quiet --skip-download --no-warnings "$url" \
    >/dev/null 2>&1
}

# Write the cache marker.
_health_cache_write() {
  local domain="$1" status="$2"
  mkdir -p "$WATCH_HEALTH_CACHE_DIR" 2>/dev/null || return 0
  : > "$WATCH_HEALTH_CACHE_DIR/${domain}.${status}"
}

# Public entry. Returns 0 if probe ok (or no canary defined for the
# domain — silent skip), non-zero if probe failed. Always returns
# without blocking; caller decides whether to proceed.
#
# Side effects: writes a warning to stderr on failed/cached-fail.
check_platform() {
  local domain="$1"
  [[ -z "$domain" ]] && return 0

  local canary
  if ! canary="$(_health_canary_for "$domain")"; then
    return 0
  fi

  local cached
  if cached="$(_health_cache_lookup "$domain")"; then
    if [[ "$cached" == "ok" ]]; then
      return 0
    fi
    echo "[watch] WARNING: yt-dlp probe failed for $domain — recent breakage detected. Continuing anyway; run 'yt-dlp -U' if download fails. tag=platform-probe-fail" >&2
    return 1
  fi

  if _health_run_probe "$canary"; then
    _health_cache_write "$domain" ok
    return 0
  fi
  _health_cache_write "$domain" fail
  echo "[watch] WARNING: yt-dlp probe failed for $domain — recent breakage detected. Continuing anyway; run 'yt-dlp -U' if download fails. tag=platform-probe-fail" >&2
  return 1
}

# Helper for `bin/watch`: derive domain from URL, then probe.
check_platform_for_url() {
  local url="$1"
  local domain
  domain="$(_health_domain_from_url "$url")"
  [[ -z "$domain" ]] && return 0
  check_platform "$domain"
}
