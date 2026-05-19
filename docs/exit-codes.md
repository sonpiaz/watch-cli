# Exit codes

watch-cli scripts (`watch`, `dl-video`, `extract-frames`, `transcribe`,
`audio-q`, `models`) follow a small, documented set of exit codes.
Wrapping scripts and agents can branch on the code to distinguish a
missing dependency from a transient network failure from a usage
mistake, and can recover from partial success (frames extracted,
transcribe failed) without re-running the whole pipeline.

This document is the source of truth for those codes. The same number
appears as the process exit code, the `EXIT:` line at the bottom of the
text output, and the `exit_code` field of the JSON output — see
[`output-schema.md`](output-schema.md).

---

## Why callers care

A composable CLI is one a wrapping script can call without writing a
parser around its stderr. Documented exit codes are the first step:

- **Branch on partial success.** Frame extraction succeeded but the
  transcribe step failed (`exit 4`)? An agent can still read the
  frames and skip the transcript step, instead of treating the whole
  run as lost.
- **Distinguish "your tool is broken" from "my environment is broken".**
  `exit 2` (missing dependency) tells the wrapper "install yt-dlp/ffmpeg
  and retry"; `exit 1` tells it "this is a real failure, surface it".
- **Surface usage mistakes early.** `exit 64` matches `sysexits.h` —
  wrappers and shell completion can treat it as "bad invocation, do
  not retry".
- **Stay language-neutral.** Exit codes are the lowest-common-denominator
  signal between Bash, Python, Node, Go, and any agent runtime. They
  work with `if ! watch …; then …; fi`, with `subprocess.run().returncode`,
  with `child_process.spawnSync().status`, with anything.

---

## Code table

| Code | Name | Emitted when | Example stderr | Recommended caller action |
|---|---|---|---|---|
| `0` | success | The pipeline completed without errors. In `watch`, both frame extraction and transcribe succeeded. | (no error output) | Consume the stdout payload. |
| `1` | general error | An uncategorized error that doesn't fit one of the more specific codes below. Should be rare; if you see it often, the case probably deserves its own row. | `[watch] error: <message>` | Log the stderr, treat as a real failure. |
| `2` | missing dependency | A required binary (`yt-dlp`, `ffmpeg`, `ffprobe`, `jq`, `curl`, `python3`) is not on `PATH`. | `[watch] error: ffmpeg not found on PATH. Install via 'brew install ffmpeg' or 'apt install ffmpeg'.` | Install the missing tool, then retry. Do not auto-retry. |
| `3` | download failed | `yt-dlp` returned a non-zero exit. The pipeline cannot continue without a video file. The stderr line includes a `tag=…` token so callers can grep without needing extra exit codes (see below). | `[watch] error: download failed for <url> tag=download-auth — sign in to the platform in your browser and re-run, or pass --cookies <file>` | Inspect the `tag=…` value. Auth → retry with cookies. Region → try VPN. Network → wait and retry. Other → file an issue. |
| `4` | transcribe failed | Frame extraction succeeded but the transcribe step failed. Output is partial: `frame_paths` is populated, `transcript` is `null`. See *Partial success* below. The stderr line includes a `tag=…` token. | `[watch] error: transcribe failed tag=transcribe-quota — top up Kyma credit at https://kymaapi.com/billing or set GROQ_API_KEY for BYOK` | Read the partial output and decide. Quota → top up. Timeout → retry with shorter audio. Silent-audio → expected, fall through to frames only. |
| `64` | usage error | Bad invocation: missing required argument, unknown flag, malformed URL, or `-h` / `--help` was passed in a context where the caller wants a non-zero. Mirrors `sysexits.h` `EX_USAGE`. | `usage: watch <url> [frame-count] [--cookies <file>]` | Do not retry. Fix the invocation. |

### Stderr tag tokens

For codes `3` and `4`, the stderr line includes a `tag=<token>` token
so callers can match on a stable, language-neutral string instead of
parsing prose. Tags ship inside v1 and follow the same stability
promise as the rest of the schema (append-only, no rename, new tags
allowed).

**`exit 3` (download) tags:**

| Tag | Meaning |
|---|---|
| `download-auth` | The platform returned a 401/403 or yt-dlp reported the URL is login-walled. The caller's recovery path is cookies — see [`cookies.md`](cookies.md). |
| `download-region` | The video is region-locked. yt-dlp reported a geo-restriction. A VPN session in the right region is the only fix. |
| `download-network` | A transient network failure: DNS resolution, TCP reset, TLS handshake, timeout against the platform CDN. Worth retrying after a short backoff. |
| `download-other` | Anything else yt-dlp emitted: extractor breakage, deleted post, malformed URL, format unavailable. Caller should surface the raw yt-dlp stderr to the user. |

**`exit 4` (transcribe) tags:**

| Tag | Meaning |
|---|---|
| `transcribe-quota` | The transcribe backend returned a billing/quota error: out of credit, monthly cap hit, or BYOK key exhausted. Caller should not retry without action. |
| `transcribe-timeout` | The transcribe backend did not return within the script's timeout. The audio file is probably too long, or the backend is slow. Retry with split audio or wait. |
| `transcribe-silent-audio` | The audio decoded successfully but the backend returned an empty transcript. Common for music videos, screen-recordings of code without narration, and very short clips. Not a true failure — caller should fall through to frames-only consumption. |
| `transcribe-other` | Anything else: backend 5xx, malformed response, audio file rejected as too large after downsample, unknown error. Surface raw stderr. |

---

## Why stderr tags instead of more exit codes

POSIX exit codes are 0–255. The standard `sysexits.h` convention
reserves 64–113 for usage-style errors, leaving little room to safely
sub-code without colliding with shell, kernel, or upstream tool
conventions (`130` for SIGINT, `137` for SIGKILL, `139` for SIGSEGV, and
so on). Sub-coding watch-cli's failures as `3.1`, `3.2`, `3.3` is not
expressible in a single exit code, and using `131`, `132`, `133` for
download sub-cases would collide with signal codes on Linux.

The agreed convention across well-behaved CLIs is: keep the exit code
coarse, put the precise signal in a greppable stderr token. Callers
that need the sub-case `grep -o 'tag=[a-z-]*'`. Callers that don't,
just branch on the exit code. Both work in any language and any shell.

---

## Partial success

The `watch` pipeline runs three steps in order: download → frame
extraction → transcribe. If the first two succeed but the third fails:

- The script exits with `4`.
- The `frame_paths` field in JSON output (or the `FRAMES:` block in
  text output) is fully populated.
- The `transcript` field is `null` in JSON, or the literal token
  `null` inside the `TRANSCRIPT:` block in text.
- The `EXIT: 4` line still appears at the bottom of text output.
- The `exit_code` field in JSON output is `4`.

A calling agent can detect this case and still use the frames:

```bash
output=$(watch --format json "$url")
rc=$?
case $rc in
  0)  echo "$output" | jq -r .transcript ;;
  4)  echo "transcribe failed, using frames only" >&2
      echo "$output" | jq -r '.frame_paths[]' ;;
  *)  echo "fatal: exit $rc" >&2; exit $rc ;;
esac
```

This is the headline reason exit codes exist as a separate spec: any
caller that hard-fails on every non-zero exit loses the recoverable
case.

If frame extraction itself failed, the script exits with `1` (general
error) and stdout is not guaranteed to contain a parseable v1 block.
Callers should check `exit_code` first, then parse.

---

## Behavior under `set -e`

A wrapping shell script that uses `set -e` (abort on any non-zero) will
treat *every* non-zero watch-cli exit as a fatal error, including
recoverable partial-success cases like `exit 4`. The default shell
behavior swallows the chance to inspect the code.

The portable pattern is to inspect the code without aborting:

```bash
set -euo pipefail

if ! output=$(watch --format json "$url"); then
  rc=$?
  case $rc in
    2)  echo "missing dependency, install yt-dlp/ffmpeg" >&2; exit 2 ;;
    3)  echo "download failed, check cookies or VPN" >&2; exit 3 ;;
    4)  echo "transcribe failed, consuming frames only" >&2
        # do not exit; fall through to use $output ;;
    64) echo "usage error, fix invocation" >&2; exit 64 ;;
    *)  echo "watch failed: $rc" >&2; exit $rc ;;
  esac
fi

# process $output here
```

The `if ! …; then …; fi` form is the idiomatic Bash workaround. The
`exit-code-aware` body runs regardless of whether `watch` succeeded,
and `$?` is preserved across the `if` block.

For Python callers:

```python
import json, subprocess

result = subprocess.run(
    ["watch", "--format", "json", url],
    capture_output=True, text=True, check=False,
)

if result.returncode == 0:
    data = json.loads(result.stdout)
elif result.returncode == 4:
    data = json.loads(result.stdout)  # partial: frame_paths populated, transcript None
else:
    raise RuntimeError(f"watch failed: rc={result.returncode}\n{result.stderr}")
```

`check=False` is the equivalent of avoiding `set -e`: it suppresses the
implicit raise on non-zero, so the caller can branch on `returncode`
itself.

---

## Example wrapper script

A small Bash wrapper that handles every documented code:

```bash
#!/usr/bin/env bash
# wrap-watch — call watch and act on the exit code.
set -uo pipefail   # note: no -e, we inspect codes ourselves

URL="$1"

output=$(watch --format json "$URL")
rc=$?

case $rc in
  0)
    # Full success: frames + transcript.
    transcript=$(echo "$output" | jq -r .transcript)
    echo "OK — transcript length: ${#transcript} chars"
    echo "$output" | jq -r '.frame_paths[]' | while read -r f; do
      echo "frame: $f"
    done
    ;;

  2)
    echo "Missing dependency. Install yt-dlp, ffmpeg, ffprobe, jq." >&2
    exit 2
    ;;

  3)
    # Inspect the tag in stderr if you want fine-grained recovery.
    # The stderr line looks like: tag=download-auth, tag=download-region, etc.
    echo "Download failed. Try signing in to your browser or passing --cookies." >&2
    exit 3
    ;;

  4)
    # Partial success: frames OK, transcript missing.
    echo "Transcribe failed — using frames only." >&2
    echo "$output" | jq -r '.frame_paths[]' | while read -r f; do
      echo "frame: $f"
    done
    ;;

  64)
    echo "Usage error. Fix the invocation." >&2
    exit 64
    ;;

  *)
    echo "Unexpected exit $rc." >&2
    exit "$rc"
    ;;
esac
```

A few notes on this script:

- `set -uo pipefail` without `-e` is deliberate. We catch errors via
  the exit code, not via aborting.
- The `case` lists every documented code so a future watch-cli release
  that adds new behavior (always within the v1 contract) does not
  silently get treated as the catch-all.
- The `download-auth` vs `download-region` distinction lives in the
  stderr tag, not the exit code. A wrapper that wants to auto-retry
  with cookies can `grep -o 'tag=[a-z-]*' < stderr-capture` and
  branch on the token.

---

## Cross-references

- The JSON / text shape the exit code appears in:
  [`output-schema.md`](output-schema.md).
- Why a download might fail with `download-auth` and how to fix it:
  [`cookies.md`](cookies.md).
- Per-platform "is this reachable at all" matrix that affects exit 3:
  [`platforms.md`](platforms.md).
