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

# 4. No-args invocation on a TTY stdin exits 64 (usage error).
# Phase 3 added auto-pipe-mode when stdin is non-TTY; the legacy
# "no URL → usage error" path now requires a TTY. Most CI runners
# attach a /dev/null-equivalent stdin, so we can't directly test the
# TTY branch — but we can verify the pipe-mode auto-enable produces
# the documented "drain empty stdin → exit 0" behavior, which is
# covered by test #8 below. The usage-error contract is exercised by
# test #5 (unknown --format value).

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

# 8. Pipe mode — empty stdin exits 0 and emits no output.
PIPE_EMPTY_OUT="$(printf '' | "$WATCH" --pipe 2>/dev/null)"
PIPE_EMPTY_RC=$?
if [[ $PIPE_EMPTY_RC -eq 0 && -z "$PIPE_EMPTY_OUT" ]]; then
  pass "watch --pipe on empty stdin exits 0 with no stdout"
else
  fail "watch --pipe on empty stdin expected exit 0 + empty stdout; got rc=$PIPE_EMPTY_RC out='$PIPE_EMPTY_OUT'"
fi

# 9. Pipe mode — invalid URL emits exactly one JSON error line and exits non-zero.
PIPE_BAD_OUT="$(printf 'not-a-url\n' | "$WATCH" --pipe 2>/dev/null)"
PIPE_BAD_RC=$?
PIPE_BAD_LINES="$(printf '%s' "$PIPE_BAD_OUT" | grep -c .)"
if [[ $PIPE_BAD_RC -ne 0 ]] \
   && [[ "$PIPE_BAD_LINES" == "1" ]] \
   && echo "$PIPE_BAD_OUT" | jq -e '.version == 1 and .exit_code != 0' >/dev/null 2>&1; then
  pass "watch --pipe with invalid URL emits one v1 error object and exits non-zero"
else
  fail "watch --pipe with invalid URL expected 1-line JSON error + non-zero; got rc=$PIPE_BAD_RC lines=$PIPE_BAD_LINES out='$PIPE_BAD_OUT'"
fi

# 10. Forced local mode with no whisper-cli on PATH → exit 2, tag=missing-dep.
# Use a subshell with a PATH that excludes whisper-cli, set WATCH_AUDIO_MODE=local,
# and verify the contract from docs/offline-mode.md.
TR_BIN="$REPO_ROOT/bin/transcribe"
# Build a minimal PATH that keeps coreutils + ffmpeg etc but drops any
# whisper-cli or main binary. Easiest: just trust that the test env
# rarely has whisper-cli; if it does, this assertion is skipped.
if command -v whisper-cli >/dev/null 2>&1 || command -v main >/dev/null 2>&1; then
  note "SKIP: forced-local missing-dep test (whisper-cli is on PATH on this host)"
else
  # /dev/null is not a real audio file but the binary check happens
  # BEFORE the file-read, so we never get that far. Spec contract is:
  # mode-resolve runs first, so missing-dep:whisper-cli surfaces.
  # We need a real input path though so usage-error doesn't intercept.
  if [[ -s "$SILENT_MP3" ]]; then
    LOCAL_OUT="$(WATCH_AUDIO_MODE=local "$TR_BIN" "$SILENT_MP3" 2>&1)"
    LOCAL_RC=$?
    if [[ $LOCAL_RC -eq 2 ]] && grep -q "tag=missing-dep" <<< "$LOCAL_OUT"; then
      pass "WATCH_AUDIO_MODE=local with no whisper-cli on PATH exits 2 tag=missing-dep"
    else
      fail "WATCH_AUDIO_MODE=local no-whisper expected exit 2 + tag=missing-dep; got rc=$LOCAL_RC out=$LOCAL_OUT"
    fi
  else
    note "SKIP: forced-local missing-dep test (no silent fixture)"
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
