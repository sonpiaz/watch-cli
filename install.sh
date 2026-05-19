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
#   --help, -h     Show this help and exit.

set -euo pipefail

REPO_URL="https://github.com/sonpiaz/watch-cli"
INSTALL_DIR="${WATCH_CLI_HOME:-$HOME/.watch-cli}"
BIN_LINK_DIR="${WATCH_CLI_BIN:-$HOME/.local/bin}"
CLAUDE_SKILLS_DIR="${HOME}/.claude/skills"

WITH_SKILL=0
WITH_MCP=0

red() { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
dim() { printf "\033[2m%s\033[0m\n" "$*"; }

usage() {
  cat <<'EOF'
watch-cli installer

Usage:
  curl -fsSL https://raw.githubusercontent.com/sonpiaz/watch-cli/main/install.sh | bash
  ./install.sh [--with-skill] [--with-mcp]

Flags:
  --with-skill   After install, copy SKILL.md into ~/.claude/skills/watch-cli/
                 so Claude Code picks up the watch-cli skill on next start.
  --with-mcp     Print the manual install hint for the MCP stdio server
                 (@sonpiaz/watch-cli-mcp on npm — not auto-installed yet).
  -h, --help     Show this help and exit.
EOF
}

# ── Parse args ──
while (($# > 0)); do
  case "$1" in
    --with-skill) WITH_SKILL=1; shift ;;
    --with-mcp) WITH_MCP=1; shift ;;
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
