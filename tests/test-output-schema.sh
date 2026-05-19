#!/usr/bin/env bash
# tests/test-output-schema.sh
# Smoke test for the v1 output contract: help, version, usage-error, and
# (if a transcribe key is set) the JSON shape of a real watch run.
#
# Network-free by default. The live transcribe test is skipped unless
# KYMA_API_KEY or GROQ_API_KEY is present.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH="$REPO_ROOT/bin/watch"

FAIL=0
pass() { printf "PASS: %s\n" "$1"; }
fail() { printf "FAIL: %s\n" "$1" >&2; FAIL=$((FAIL + 1)); }
note() { printf "NOTE: %s\n" "$1"; }

# 1. watch is executable and on the in-repo path
if [[ -x "$WATCH" ]]; then
  pass "bin/watch exists and is executable"
else
  fail "bin/watch missing or not executable"
fi

# 2. --help exits 0 and prints usage line
HELP_OUT="$("$WATCH" --help 2>&1)"
HELP_RC=$?
if [[ $HELP_RC -eq 0 ]] && grep -q "watch <url>" <<< "$HELP_OUT"; then
  pass "watch --help exits 0 and prints usage"
else
  fail "watch --help expected exit 0 + 'watch <url>'; got rc=$HELP_RC"
fi

# 3. --version exits 0 and prints a version string
VER_OUT="$("$WATCH" --version 2>&1)"
VER_RC=$?
if [[ $VER_RC -eq 0 ]] && [[ "$VER_OUT" =~ watch-cli ]]; then
  pass "watch --version exits 0 and prints 'watch-cli …'"
else
  fail "watch --version expected exit 0 + 'watch-cli'; got rc=$VER_RC out=$VER_OUT"
fi

# 4. No-args invocation exits 64 (usage error)
"$WATCH" >/dev/null 2>&1
NA_RC=$?
if [[ $NA_RC -eq 64 ]]; then
  pass "watch with no args exits 64"
else
  fail "watch with no args expected exit 64; got rc=$NA_RC"
fi

# 5. Unknown --format value exits 64
"$WATCH" https://example.invalid --format xml >/dev/null 2>&1
FMT_RC=$?
if [[ $FMT_RC -eq 64 ]]; then
  pass "watch --format xml exits 64"
else
  fail "watch --format xml expected exit 64; got rc=$FMT_RC"
fi

# 6. Fixture creation (1s silent mp3) — only needed for the live test below.
FIXTURE_DIR="$REPO_ROOT/tests/fixtures"
SILENT_MP3="$FIXTURE_DIR/silent.mp3"
if [[ ! -s "$SILENT_MP3" ]]; then
  if command -v ffmpeg >/dev/null 2>&1; then
    mkdir -p "$FIXTURE_DIR"
    ffmpeg -hide_banner -loglevel error -y \
      -f lavfi -i anullsrc=r=16000:cl=mono -t 1 -q:a 9 \
      "$SILENT_MP3" >/dev/null 2>&1 || true
  fi
fi

# 7. Live transcribe smoke — only if a key is set. The full watch pipeline
# needs a URL, so we test the transcribe binary directly against the
# silent fixture. It should detect silence and exit 4 with
# tag=transcribe-silent-audio. This validates the exit code contract
# without burning a real video download.
if [[ -z "${KYMA_API_KEY:-}" && -z "${GROQ_API_KEY:-}" ]]; then
  note "SKIP: live transcribe test (no KYMA_API_KEY or GROQ_API_KEY set)"
elif [[ ! -s "$SILENT_MP3" ]]; then
  note "SKIP: live transcribe test (no fixture, ffmpeg unavailable?)"
else
  TR_OUT="$("$REPO_ROOT/bin/transcribe" "$SILENT_MP3" 2>&1)"
  TR_RC=$?
  if [[ $TR_RC -eq 4 ]] && grep -q "tag=transcribe-silent-audio" <<< "$TR_OUT"; then
    pass "transcribe on silent.mp3 exits 4 with tag=transcribe-silent-audio"
  else
    fail "transcribe on silent.mp3 expected exit 4 + tag=transcribe-silent-audio; got rc=$TR_RC out=$TR_OUT"
  fi
fi

echo
if [[ $FAIL -eq 0 ]]; then
  echo "tests/test-output-schema.sh: all assertions passed"
  exit 0
else
  echo "tests/test-output-schema.sh: $FAIL assertion(s) failed" >&2
  exit 1
fi
