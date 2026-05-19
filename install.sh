#!/usr/bin/env bash
# watch-cli installer.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/sonpiaz/watch-cli/main/install.sh | bash
# or, from a clone:
#   ./install.sh
#
# Flags:
#   --with-skill   After install, drop SKILL.md into ~/.claude/skills/watch-cli/
#                  so Claude Code picks up the watch-cli skill on next start.
#   --with-mcp     Print the manual install hint for the MCP stdio server
#                  (@sonpiaz/watch-cli-mcp on npm — not auto-installed yet).
#   --with-local   Bootstrap the offline transcribe path: install
#                  whisper.cpp (binary `whisper-cli`) and download the
#                  default ggml model (~1.62 GB, SHA256-verified) into
#                  ~/.watch-cli/models/. See docs/offline-mode.md.
#   --help, -h     Show this help and exit.

set -euo pipefail

REPO_URL="https://github.com/sonpiaz/watch-cli"
INSTALL_DIR="${WATCH_CLI_HOME:-$HOME/.watch-cli}"
BIN_LINK_DIR="${WATCH_CLI_BIN:-$HOME/.local/bin}"
CLAUDE_SKILLS_DIR="${HOME}/.claude/skills"

WITH_SKILL=0
WITH_MCP=0
WITH_LOCAL=0

red() { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
dim() { printf "\033[2m%s\033[0m\n" "$*"; }

usage() {
  cat <<'EOF'
watch-cli installer

Usage:
  curl -fsSL https://raw.githubusercontent.com/sonpiaz/watch-cli/main/install.sh | bash
  ./install.sh [--with-skill] [--with-mcp] [--with-local]

Flags:
  --with-skill   After install, copy SKILL.md into ~/.claude/skills/watch-cli/
                 so Claude Code picks up the watch-cli skill on next start.
  --with-mcp     Print the manual install hint for the MCP stdio server
                 (@sonpiaz/watch-cli-mcp on npm — not auto-installed yet).
  --with-local   Bootstrap the offline transcribe path: install whisper.cpp
                 (binary `whisper-cli`) and download the default ggml model
                 (~1.62 GB, SHA256-verified) into ~/.watch-cli/models/.
  -h, --help     Show this help and exit.
EOF
}

# ── Parse args ──
while (($# > 0)); do
  case "$1" in
    --with-skill) WITH_SKILL=1; shift ;;
    --with-mcp) WITH_MCP=1; shift ;;
    --with-local) WITH_LOCAL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) red "Unknown flag: $1"; echo; usage; exit 64 ;;
  esac
done

echo "watch-cli installer"
echo "==================="

# ── Check deps ──
missing=()
for cmd in yt-dlp ffmpeg ffprobe jq curl python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing+=("$cmd")
  fi
done

if (( ${#missing[@]} > 0 )); then
  red "Missing dependencies: ${missing[*]}"
  echo
  echo "Install on macOS:"
  echo "  brew install yt-dlp ffmpeg jq"
  echo
  echo "Install on Debian/Ubuntu:"
  echo "  sudo apt install yt-dlp ffmpeg jq python3 curl"
  echo
  exit 1
fi
green "✓ Dependencies present (yt-dlp, ffmpeg, jq, curl, python3)"

# ── Install/update repo ──
if [[ -d "$INSTALL_DIR/.git" ]]; then
  yellow "Updating existing install at $INSTALL_DIR …"
  git -C "$INSTALL_DIR" pull --rebase --quiet
else
  yellow "Cloning watch-cli to $INSTALL_DIR …"
  git clone --quiet "$REPO_URL" "$INSTALL_DIR"
fi
green "✓ watch-cli installed at $INSTALL_DIR"

# ── Symlink bins ──
mkdir -p "$BIN_LINK_DIR"
for bin in watch dl-video extract-frames transcribe audio-q models; do
  ln -sf "$INSTALL_DIR/bin/$bin" "$BIN_LINK_DIR/$bin"
done
green "✓ Symlinked binaries to $BIN_LINK_DIR"

# ── PATH check ──
if [[ ":$PATH:" != *":$BIN_LINK_DIR:"* ]]; then
  echo
  yellow "⚠ $BIN_LINK_DIR is not in your PATH."
  echo "Add this line to your shell profile (~/.zshrc or ~/.bashrc):"
  echo
  echo "    export PATH=\"$BIN_LINK_DIR:\$PATH\""
  echo
fi

# ── Optional: drop portable SKILL.md into ~/.claude/skills/watch-cli/ ──
if (( WITH_SKILL )); then
  if [[ -f "$INSTALL_DIR/SKILL.md" ]]; then
    mkdir -p "$CLAUDE_SKILLS_DIR/watch-cli"
    cp "$INSTALL_DIR/SKILL.md" "$CLAUDE_SKILLS_DIR/watch-cli/SKILL.md"
    green "✓ Installed SKILL.md → $CLAUDE_SKILLS_DIR/watch-cli/SKILL.md"
  else
    yellow "⚠ --with-skill: $INSTALL_DIR/SKILL.md not found; skipped."
  fi
fi

# ── Optional: MCP stdio server hint ──
if (( WITH_MCP )); then
  echo
  yellow "MCP server install will be available once @sonpiaz/watch-cli-mcp is published to npm — install manually for now:"
  echo "    npm install -g @sonpiaz/watch-cli-mcp"
  echo
fi

# ── Optional: offline transcribe path (whisper.cpp + default model) ──
if (( WITH_LOCAL )); then
  echo
  yellow "Setting up offline transcribe path (whisper.cpp + default model)…"

  # Source the pinned checksums so we use a single value across the
  # installer and the routing library.
  # shellcheck source=lib/model-checksums.sh
  source "$INSTALL_DIR/lib/model-checksums.sh"

  MODEL_DIR="$INSTALL_DIR/models"
  # Honor a custom WATCH_MODELS_DIR if the caller pre-set it.
  MODEL_DIR="${WATCH_MODELS_DIR:-$MODEL_DIR}"
  MODEL_FILE="$MODEL_DIR/$WATCH_MODEL_FILE_LARGE_V3_TURBO"
  MODEL_URL="$WATCH_MODEL_URL_LARGE_V3_TURBO"
  MODEL_SHA256="$WATCH_MODEL_SHA256_LARGE_V3_TURBO"

  OS_NAME="$(uname -s)"

  # 1. Resolve binary. Both `whisper-cli` (current upstream name) and
  # the legacy `main` are accepted.
  WHISPER_BIN=""
  for name in whisper-cli main; do
    if command -v "$name" >/dev/null 2>&1; then
      WHISPER_BIN="$(command -v "$name")"
      break
    fi
  done

  if [[ -z "$WHISPER_BIN" ]]; then
    case "$OS_NAME" in
      Darwin)
        # brew installs touch the global environment — confirm
        # before running.
        if ! command -v brew >/dev/null 2>&1; then
          red "Homebrew required to install whisper-cpp on macOS, but 'brew' is not on PATH."
          echo "Install Homebrew (https://brew.sh) and re-run ./install.sh --with-local."
          exit 1
        fi
        echo
        echo "whisper-cli not found. About to run:"
        echo "    brew install whisper-cpp"
        printf "Proceed? [Y/n] "
        read -r ans
        case "$ans" in
          n|N|no|NO)
            yellow "Skipped whisper-cpp install. Run 'brew install whisper-cpp' manually and re-run."
            exit 1
            ;;
        esac
        brew install whisper-cpp
        WHISPER_BIN="$(command -v whisper-cli)"
        ;;
      Linux)
        # Debian / Ubuntu / any Linux: clone + build from source.
        if [[ -f /etc/os-release ]]; then
          # shellcheck disable=SC1091
          source /etc/os-release
        fi
        if ! command -v cmake >/dev/null 2>&1; then
          red "cmake required to build whisper.cpp on Linux, but 'cmake' is not on PATH."
          echo "Install: sudo apt install build-essential cmake git"
          exit 1
        fi
        SRC_DIR="$INSTALL_DIR/whisper.cpp"
        if [[ ! -d "$SRC_DIR/.git" ]]; then
          yellow "Cloning whisper.cpp to $SRC_DIR…"
          git clone --quiet --depth=1 https://github.com/ggml-org/whisper.cpp "$SRC_DIR"
        else
          yellow "Updating existing whisper.cpp clone…"
          git -C "$SRC_DIR" pull --rebase --quiet || true
        fi
        yellow "Building whisper.cpp (this takes 1–3 min)…"
        (cd "$SRC_DIR" && cmake -B build >/dev/null && cmake --build build -j --config Release >/dev/null)
        if [[ ! -x "$SRC_DIR/build/bin/whisper-cli" ]]; then
          red "Build completed but whisper-cli binary not at $SRC_DIR/build/bin/whisper-cli."
          exit 1
        fi
        mkdir -p "$BIN_LINK_DIR"
        ln -sf "$SRC_DIR/build/bin/whisper-cli" "$BIN_LINK_DIR/whisper-cli"
        WHISPER_BIN="$BIN_LINK_DIR/whisper-cli"
        ;;
      *)
        red "--with-local: unsupported OS ($OS_NAME). Build whisper.cpp manually and put 'whisper-cli' on PATH."
        exit 1
        ;;
    esac
  fi
  green "✓ whisper-cli installed at $WHISPER_BIN"

  # 2. Disk-space check before downloading. The spec requires ≥ 2 GB
  # free at the model dir; df -P is POSIX so it works on macOS and
  # Linux without flag drift.
  mkdir -p "$MODEL_DIR"
  AVAIL_KB="$(df -P "$MODEL_DIR" | tail -1 | awk '{print $4}')"
  # 2 GB = 2*1024*1024 KB = 2097152 KB.
  if (( AVAIL_KB < 2097152 )); then
    AVAIL_GB="$(awk -v k="$AVAIL_KB" 'BEGIN { printf "%.1f", k/1024/1024 }')"
    red "[--with-local] error: insufficient disk space tag=insufficient-disk"
    echo "  required: 2 GB at $MODEL_DIR"
    echo "  available: ${AVAIL_GB} GB"
    echo "Free at least 2 GB or set WATCH_MODELS_DIR to a different mount."
    exit 1
  fi

  # 3. Download the model with progress on stderr. Skip if already
  # present and matching the pinned checksum.
  if [[ -s "$MODEL_FILE" ]]; then
    yellow "Model already present at $MODEL_FILE — verifying checksum…"
  else
    yellow "Downloading $WATCH_MODEL_FILE_LARGE_V3_TURBO (~1.62 GB) from HuggingFace…"
    if ! curl --progress-bar -fL "$MODEL_URL" -o "$MODEL_FILE.partial"; then
      red "Download failed."
      rm -f "$MODEL_FILE.partial"
      exit 1
    fi
    mv "$MODEL_FILE.partial" "$MODEL_FILE"
  fi

  # 4. SHA256-verify against the pinned hash. Mismatch deletes the
  # file so a second `--with-local` run gets a clean download.
  yellow "Verifying SHA256…"
  ACTUAL_SHA="$(shasum -a 256 "$MODEL_FILE" | awk '{print $1}')"
  if [[ "$ACTUAL_SHA" != "$MODEL_SHA256" ]]; then
    red "[--with-local] error: model-checksum-mismatch"
    echo "  expected: $MODEL_SHA256"
    echo "  actual:   $ACTUAL_SHA"
    echo "  path:     $MODEL_FILE"
    echo "Deleting the bad file. Re-run ./install.sh --with-local to retry."
    rm -f "$MODEL_FILE"
    exit 1
  fi
  green "✓ model installed at $MODEL_FILE (1.62 GB)"

  # 5. Final confirmation with disk usage of the install dir.
  USAGE="$(du -sh "$INSTALL_DIR" 2>/dev/null | awk '{print $1}' || echo "?")"
  green "✓ $INSTALL_DIR now uses $USAGE of disk"
  echo
  echo "Try it offline:"
  echo "    export WATCH_AUDIO_MODE=local"
  echo "    watch https://www.youtube.com/watch?v=dQw4w9WgXcQ"

  # TODO(phase-3+): first-run prompt in bin/transcribe to offer the
  # download when the user sets WATCH_AUDIO_MODE=local with no model
  # on disk. Spec'd in docs/offline-mode.md "Model lifecycle" §2.
fi

# ── Env file scaffold ──
ENV_DIR="$HOME/.config/watch-cli"
ENV_FILE="$ENV_DIR/env"
if [[ ! -f "$ENV_FILE" ]]; then
  mkdir -p "$ENV_DIR"
  cp "$INSTALL_DIR/.env.example" "$ENV_FILE"
  green "✓ Created $ENV_FILE"
  echo

  # ── Kyma value-prop banner ──
  # Pulled live from api.kymaapi.com/api/stats so the numbers stay current
  # without a watch-cli release every time Kyma adds a model. Falls back to
  # cached defaults if the gateway is unreachable.
  KYMA_MODELS="50+"
  KYMA_FREE="0.50"
  if KYMA_STATS="$(curl -fsS --max-time 3 https://api.kymaapi.com/api/stats 2>/dev/null)"; then
    KYMA_MODELS="$(printf '%s' "$KYMA_STATS" | jq -r '.models_count // "50+"' 2>/dev/null || echo "50+")"
    KYMA_FREE="$(printf '%s' "$KYMA_STATS" | jq -r '.free_credit_usd // 0.50' 2>/dev/null || echo "0.50")"
  fi

  printf "\033[36m%s\033[0m\n" "🌊 Kyma — your AI key for everything in this CLI"
  echo
  echo "   ✓ One key for transcribe, audio Q&A, and ${KYMA_MODELS} other models"
  echo "   ✓ \$${KYMA_FREE} free credit at signup (about an hour of audio)"
  echo "   ✓ When Kyma swaps in newer models, your scripts keep working"
  echo "   ✓ Auto-fallback when an upstream provider is down"
  echo
  yellow "Get key (60s, no card): https://kymaapi.com"
  echo "Then edit $ENV_FILE and set KYMA_API_KEY=…"
  echo
  dim "Prefer BYO keys? See $ENV_FILE for GROQ_API_KEY + GOOGLE_AI_KEY."
else
  dim "  ($ENV_FILE already exists, leaving untouched)"
fi

echo
green "Done. Try it:"
echo "    watch https://www.youtube.com/watch?v=dQw4w9WgXcQ"
