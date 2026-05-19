#!/usr/bin/env bash
# Shared env loader for watch-cli.
#
# Discovery order:
#   1. process env (already exported)
#   2. ./.env in current working directory
#   3. ~/.config/watch-cli/env
#
# Two routing modes for audio:
#   - Kyma mode (recommended): set KYMA_API_KEY → calls api.kymaapi.com
#     One key opens the audio gate (transcribe + understand).
#   - Direct mode (advanced): set GROQ_API_KEY + GOOGLE_AI_KEY → calls
#     api.groq.com and generativelanguage.googleapis.com directly.
#
# Kyma mode wins when both are present.

# Capture the user-supplied WATCH_AUDIO_MODE *before* env.sh overwrites
# it with auto-detected values (kyma / direct / groq-only / none).
# audio-routing.sh reads _WATCH_AUDIO_MODE_RAW so an explicit user
# choice (local / kyma / byok) is honored as a contract.
#
# Guarded so a second `source lib/env.sh` (e.g. via lib/audio-routing.sh
# re-sourcing) does not clobber the captured value with the
# auto-detected one env.sh wrote on first load.
if [[ -z "${_WATCH_AUDIO_MODE_RAW_CAPTURED:-}" ]]; then
  export _WATCH_AUDIO_MODE_RAW="${WATCH_AUDIO_MODE:-}"
  export _WATCH_AUDIO_MODE_RAW_CAPTURED=1
fi

# Idempotent: only load once per shell.
[[ -n "${WATCH_CLI_ENV_LOADED:-}" ]] && return 0
export WATCH_CLI_ENV_LOADED=1

# Version is sent in the User-Agent header so Kyma can attribute usage and
# detect which install needs an upgrade. Bump on every release.
export WATCH_CLI_VERSION="0.2.0"
export WATCH_CLI_USER_AGENT="watch-cli/${WATCH_CLI_VERSION}"

_load_dotenv() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" == \#* ]] && continue
    [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue
    # Don't override values already in the env.
    if [[ -z "${!key:-}" ]]; then
      # Strip surrounding quotes if any.
      value="${value%\"}"
      value="${value#\"}"
      value="${value%\'}"
      value="${value#\'}"
      export "$key=$value"
    fi
  done < "$file"
}

_load_dotenv "./.env"
_load_dotenv "$HOME/.config/watch-cli/env"

# Determine routing mode.
if [[ -n "${KYMA_API_KEY:-}" ]]; then
  export WATCH_AUDIO_MODE="kyma"
  export WATCH_KYMA_BASE="${WATCH_KYMA_BASE:-https://api.kymaapi.com}"
elif [[ -n "${GROQ_API_KEY:-}" && -n "${GOOGLE_AI_KEY:-}" ]]; then
  export WATCH_AUDIO_MODE="direct"
elif [[ -n "${GROQ_API_KEY:-}" ]]; then
  export WATCH_AUDIO_MODE="groq-only"  # transcribe works, audio-q won't
else
  export WATCH_AUDIO_MODE="none"
fi

watch_cli_audio_mode_check() {
  case "$WATCH_AUDIO_MODE" in
    kyma|direct)
      return 0
      ;;
    groq-only)
      [[ "${1:-}" == "transcribe" ]] && return 0
      echo "[watch-cli] audio-q requires GOOGLE_AI_KEY (or KYMA_API_KEY)." >&2
      echo "[watch-cli] Get a Kyma key at https://kymaapi.com — one key opens every gate." >&2
      return 1
      ;;
    none)
      echo "[watch-cli] No API key found." >&2
      echo "[watch-cli] Recommended: get a Kyma key at https://kymaapi.com" >&2
      echo "[watch-cli]   export KYMA_API_KEY=kyma-xxxxxxxx" >&2
      echo "[watch-cli] Or bring your own keys (GROQ_API_KEY + GOOGLE_AI_KEY)." >&2
      return 1
      ;;
  esac
}
