#!/usr/bin/env bash
# Audio backend routing for watch-cli.
#
# Resolves which transcribe path runs at script startup, before any
# audio is read. Driven by WATCH_AUDIO_MODE when explicitly set; falls
# back to auto-detection when unset. See docs/offline-mode.md for the
# full priority table.
#
# Exports on success:
#   WATCH_AUDIO_RESOLVED_MODE  — one of: local, kyma, byok
#   WATCH_WHISPER_BIN          — absolute path to whisper-cli or main
#                                (local mode only)
#   WATCH_WHISPER_MODEL        — absolute path to the ggml model file
#                                (local mode only)
#   WATCH_MODELS_DIR           — defaults to ~/.watch-cli/models when
#                                unset
#
# On failure: emits a tagged stderr line and returns non-zero with the
# expected exit code in WATCH_AUDIO_RESOLVE_EXIT so the caller can
# `exit "$WATCH_AUDIO_RESOLVE_EXIT"`.
#
# An explicit WATCH_AUDIO_MODE value is a contract: the resolver does
# not silently fall through to a different backend when the requested
# one fails. A user who said `local` chose it for privacy, cost, or
# network independence — silently routing audio over an API would void
# that intent.

[[ -n "${WATCH_CLI_AUDIO_ROUTING_LOADED:-}" ]] && return 0
export WATCH_CLI_AUDIO_ROUTING_LOADED=1

# Pull in env defaults (KYMA_API_KEY, GROQ_API_KEY) without redefining.
# env.sh is idempotent so double-source is safe.
_AR_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env.sh
source "$_AR_SELF_DIR/env.sh"
# shellcheck source=./model-checksums.sh
source "$_AR_SELF_DIR/model-checksums.sh"

# Default model dir, overridable via WATCH_MODELS_DIR.
export WATCH_MODELS_DIR="${WATCH_MODELS_DIR:-$HOME/.watch-cli/models}"

# Probe binary, prefer `whisper-cli` (current upstream name), fall back
# to `main` (legacy name on older builds). Echoes path on stdout; empty
# string if neither is on PATH.
_resolve_whisper_bin() {
  local p
  for name in whisper-cli main; do
    p="$(command -v "$name" 2>/dev/null || true)"
    if [[ -n "$p" ]]; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

# Echo path to default model file. Empty if missing.
_resolve_whisper_model() {
  local path="$WATCH_MODELS_DIR/$WATCH_MODEL_FILE_LARGE_V3_TURBO"
  if [[ -s "$path" ]]; then
    printf '%s' "$path"
    return 0
  fi
  return 1
}

# Set exit code + tag for the caller. Returns 1 so callers can `return`.
_audio_route_fail() {
  local exit_code="$1"
  local tag="$2"
  local msg="$3"
  export WATCH_AUDIO_RESOLVE_EXIT="$exit_code"
  export WATCH_AUDIO_RESOLVE_TAG="$tag"
  echo "$msg tag=$tag" >&2
  return 1
}

# Main entry point. Caller invokes:
#
#   if ! watch_cli_resolve_audio_backend "transcribe"; then
#     exit "$WATCH_AUDIO_RESOLVE_EXIT"
#   fi
#
# Argument is the calling script name for prefixed error messages
# ("[transcribe] error: …"). Defaults to "transcribe".
watch_cli_resolve_audio_backend() {
  local prefix="${1:-transcribe}"
  local forced="${WATCH_AUDIO_MODE_FORCE:-}"

  # If WATCH_AUDIO_MODE was set in the env (by the user, not by
  # env.sh's auto-detection), preserve and honor it as a contract.
  # env.sh writes "kyma" / "direct" / "groq-only" / "none" — those are
  # *auto-detected* values, not user choices. User-set values are the
  # documented strings: local, kyma, byok.
  local user_mode=""
  if [[ -n "${WATCH_AUDIO_MODE_USER:-}" ]]; then
    user_mode="$WATCH_AUDIO_MODE_USER"
  fi

  # The most-common case: user typed `WATCH_AUDIO_MODE=local …`.
  # env.sh's auto-detect overwrites WATCH_AUDIO_MODE so we look at the
  # original by checking known user values up-front via a sentinel.
  case "${_WATCH_AUDIO_MODE_RAW:-}" in
    local|kyma|byok) user_mode="$_WATCH_AUDIO_MODE_RAW" ;;
  esac

  if [[ -n "$user_mode" ]]; then
    case "$user_mode" in
      local)
        _route_local "$prefix" || return 1
        export WATCH_AUDIO_RESOLVED_MODE="local"
        return 0
        ;;
      kyma)
        if [[ -z "${KYMA_API_KEY:-}" ]]; then
          _audio_route_fail 2 "missing-key:KYMA_API_KEY" \
            "[$prefix] error: WATCH_AUDIO_MODE=kyma but KYMA_API_KEY is unset"
          return 1
        fi
        export WATCH_KYMA_BASE="${WATCH_KYMA_BASE:-https://api.kymaapi.com}"
        export WATCH_AUDIO_RESOLVED_MODE="kyma"
        return 0
        ;;
      byok)
        if [[ -z "${GROQ_API_KEY:-}" ]]; then
          _audio_route_fail 2 "missing-key:GROQ_API_KEY" \
            "[$prefix] error: WATCH_AUDIO_MODE=byok but GROQ_API_KEY is unset"
          return 1
        fi
        export WATCH_AUDIO_RESOLVED_MODE="byok"
        return 0
        ;;
    esac
  fi

  # Auto-detect when WATCH_AUDIO_MODE is unset. Priority:
  #   1. Local whisper.cpp (binary + default model both present)
  #   2. Kyma (KYMA_API_KEY)
  #   3. BYOK Groq (GROQ_API_KEY)
  #   4. None → missing-config.
  local bin model
  if bin="$(_resolve_whisper_bin)" && model="$(_resolve_whisper_model)"; then
    export WATCH_WHISPER_BIN="$bin"
    export WATCH_WHISPER_MODEL="$model"
    export WATCH_AUDIO_RESOLVED_MODE="local"
    return 0
  fi

  if [[ -n "${KYMA_API_KEY:-}" ]]; then
    export WATCH_KYMA_BASE="${WATCH_KYMA_BASE:-https://api.kymaapi.com}"
    export WATCH_AUDIO_RESOLVED_MODE="kyma"
    return 0
  fi

  if [[ -n "${GROQ_API_KEY:-}" ]]; then
    export WATCH_AUDIO_RESOLVED_MODE="byok"
    return 0
  fi

  # No backend at all.
  export WATCH_AUDIO_RESOLVE_EXIT=2
  export WATCH_AUDIO_RESOLVE_TAG="missing-config"
  {
    echo "[$prefix] error: no usable audio backend tag=missing-config"
    echo "Configure one of:"
    echo "  - export KYMA_API_KEY=…           (recommended — https://kymaapi.com)"
    echo "  - export GROQ_API_KEY=…           (BYOK direct)"
    echo "  - install whisper.cpp + model     (fully offline — see docs/offline-mode.md)"
  } >&2
  return 1
}

# Resolve the local path: binary + model both required. Failure modes
# emit distinct tags so callers can disambiguate "no whisper" from "no
# model" without parsing prose.
_route_local() {
  local prefix="$1"
  local bin
  if ! bin="$(_resolve_whisper_bin)"; then
    _audio_route_fail 2 "missing-dep:whisper-cli" \
      "[$prefix] error: whisper-cli (or main) not found on PATH — install via 'brew install whisper-cpp' or run install.sh --with-local"
    return 1
  fi
  local model
  if ! model="$(_resolve_whisper_model)"; then
    _audio_route_fail 2 "missing-dep:whisper-model" \
      "[$prefix] error: model not found at $WATCH_MODELS_DIR/$WATCH_MODEL_FILE_LARGE_V3_TURBO — run install.sh --with-local to download"
    return 1
  fi
  export WATCH_WHISPER_BIN="$bin"
  export WATCH_WHISPER_MODEL="$model"
  return 0
}
