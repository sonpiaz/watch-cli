# Offline mode (whisper.cpp)

`bin/transcribe` shipped requiring a hosted-backend or BYOK key, so
the tool could not run on an airplane, an air-gapped network, or
anywhere the configured backend was unreachable. Phase 3 adds a
third path: local whisper.cpp plus a pre-downloaded ggml model. With
it installed, the transcribe step does no outbound HTTP — removing
the structural dependency on any single backend, keeping the tool
working when an upstream is throttled or down, and addressing the
"marketing trojan" perception risk OSS reviewers flag when a CLI
defaults to a hosted provider.

This document is the contract for the local path. If `bin/transcribe`
drifts, this spec wins.

---

## Routing priority

`bin/transcribe` makes one routing decision at startup, before any
audio is read. Driven by `WATCH_AUDIO_MODE` when set, by auto-detection
when not.

### When `WATCH_AUDIO_MODE` is set

| Value | Action | Failure mode |
|---|---|---|
| `local` | Use whisper.cpp. Resolve binary, resolve model, run inference locally. | If no binary on `PATH`: exit `2`, stderr tag `missing-dep:whisper-cli`. If model file missing: exit `2`, stderr tag `missing-dep:whisper-model`. |
| `kyma` | POST to Kyma `/v1/audio/transcriptions`. | If `KYMA_API_KEY` is unset: exit `2`, stderr tag `missing-key:KYMA_API_KEY`. |
| `byok` | POST direct to BYOK provider audio endpoint. | If `GROQ_API_KEY` is unset: exit `2`, stderr tag `missing-key:GROQ_API_KEY`. |

An explicit `WATCH_AUDIO_MODE` value is a contract. The script does
not fall back to a different path when the requested one fails — if
the user said `local`, falling back to an API call would silently
violate that intent.

### When `WATCH_AUDIO_MODE` is unset

The script picks the first usable backend in this order:

1. **Local whisper.cpp**, when both: a binary named `whisper-cli` (or
   the older `main` — see *Binary detection*) is on `PATH`, **and**
   the default model file exists at
   `~/.watch-cli/models/ggml-large-v3-turbo.bin`.
2. **Kyma**, when `KYMA_API_KEY` is set.
3. **BYOK Groq**, when `GROQ_API_KEY` is set.
4. **No backend**: exit `2`, stderr tag `missing-config`, message:

   ```text
   [transcribe] error: no usable audio backend tag=missing-config
   Configure one of:
     - export KYMA_API_KEY=…           (recommended — https://kymaapi.com)
     - export GROQ_API_KEY=…           (BYOK direct)
     - install whisper.cpp + model     (fully offline — see docs/offline-mode.md)
   ```

Local is preferred over a configured API key when both exist: it costs
nothing per call, leaks no audio to a third party, and keeps working
without a network. Users who prefer the API path on a machine that has
both can force it with `WATCH_AUDIO_MODE=kyma`.

---

## whisper.cpp binary detection

watch-cli probes two binary names, in order: `whisper-cli` (current
upstream name; shipped by the Homebrew bottle and any whisper.cpp
build from roughly mid-2024 onward), then `main` (legacy name from
older builds, kept as a fallback so existing installs do not break).
Resolution is `command -v whisper-cli` first, `command -v main`
second. First hit wins; the resolved path is captured locally so
debug logs record which binary was used.

Install paths the implementer should be ready for:

- **Homebrew (macOS):** package `whisper-cpp` (with hyphen), binary
  `whisper-cli`. Bottle does not include a model.
- **Build from source (Linux / any):** upstream uses CMake —
  `git clone https://github.com/ggml-org/whisper.cpp ~/.watch-cli/whisper.cpp && cd ~/.watch-cli/whisper.cpp && cmake -B build && cmake --build build -j --config Release`.
  Binary at `~/.watch-cli/whisper.cpp/build/bin/whisper-cli`;
  `install.sh --with-local` (below) symlinks into
  `~/.local/bin/whisper-cli`.

---

## Model lifecycle

**Default model:** `ggml-large-v3-turbo` — multilingual, ~1.62 GB on
disk, fastest of the large-v3 family on Apple Silicon. Comparable
quality to the hosted `transcribe` alias.

**Storage path:** `~/.watch-cli/models/ggml-large-v3-turbo.bin`,
overridable via `WATCH_MODELS_DIR`. Multiple models in the same
directory are allowed; only the active model's file is read.

**How the model gets there — two opt-in paths:**

1. **At install time:** `install.sh --with-local` prints expected
   disk footprint, asks `Y/n`, downloads on confirmation.
2. **At first use:** if `WATCH_AUDIO_MODE=local` is set and the model
   file is missing, the script prompts:

   ```text
   [transcribe] local mode requested but no model found at
     ~/.watch-cli/models/ggml-large-v3-turbo.bin
   Download ggml-large-v3-turbo (~1.62 GB)? [y/N]
   ```

   Only explicit `y` proceeds. Anything else (default `N`, blank,
   `n`, EOF) → exit `2`, tag `missing-dep:whisper-model`. No silent
   network activity ever happens in local mode.

**Download URL:**

```text
https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
```

Verified as a 302 redirect to a signed HuggingFace CDN URL,
content-length `1624555275` bytes (≈ 1.62 GB), content-type
`application/octet-stream`. Follow redirects (`curl -fL`); report
progress on stderr.

**Integrity verification:** the script computes SHA256 and compares
against a hash pinned in `lib/model-checksums.sh` (one entry per
known model). Upstream publishes SHA1 only
(`4af2b29d7ec73d781377bfd1758ca957a807e941` for `large-v3-turbo`);
re-hash with SHA256 once at implementation time and pin it in-tree —
SHA256 is what every other watch-cli artifact uses and what
`shasum -a 256` defaults to on macOS.

Mismatch → exit `1`, tag `model-checksum-mismatch`, message with
expected/actual hashes and instructions to delete the partial file
and retry. The partial file is **not** auto-deleted; surfacing the
path lets the user inspect before losing it.

---

## Disk-space check

Before any model download, the script calls `df -P` on the target
directory and requires ≥ **2 GB free**. The model is 1.62 GB; a
strict 1.62 GB check fails on filesystems with metadata overhead.

Insufficient → exit `1`, tag `insufficient-disk`, message:

```text
[transcribe] error: insufficient disk space tag=insufficient-disk
  required: 2 GB at ~/.watch-cli/models/
  available: 0.4 GB
Free at least 2 GB or set WATCH_MODELS_DIR to a different mount.
```

---

## Invocation contract

In local mode, `bin/transcribe` runs exactly this command (`$BIN` =
`whisper-cli` or `main` per detection):

```bash
"$BIN" -m "$WATCH_MODELS_DIR/ggml-large-v3-turbo.bin" \
       -f "$AUDIO" --output-txt -of "$STEM"
```

- `-m` is the absolute model path.
- `-f` is the pre-normalized audio file from the existing ffmpeg step
  (mono 16 kHz). whisper.cpp accepts WAV and MP3 in current builds;
  keep WAV default to avoid the 16-bit-WAV-only constraint some older
  `main` builds still enforce.
- `--output-txt -of <stem>` writes the transcript to `<stem>.txt`.
  Script reads it, strips trailing newline, prints to stdout, unlinks.

whisper.cpp progress goes to stderr and is swallowed (redirected to
`/dev/null`, or to a debug log when `WATCH_DEBUG=1`).

### Silent-audio handling

An empty transcript from whisper.cpp is treated identically to an
empty transcript from any API backend: exit `4`, tag
`transcribe-silent-audio`. Text renders `null` in the `TRANSCRIPT:`
block; JSON sets `transcript` to `null`. The existing pre-flight
silence check (`ffmpeg -af volumedetect` ≥ −60 dB) runs **before**
the whisper.cpp invocation, so digitally silent input short-circuits
without spawning whisper.cpp.

---

## Cost field in v1 JSON output

The v1 schema declares `transcribe_cost_usd` as **optional**: absent
when the backend reports no cost. Local mode is exactly that case —
no per-call cost, and emitting `0` would collide with "the backend
told us this call was free". So in local mode the script **omits**
`transcribe_cost_usd` from the JSON object entirely. The key is
present in Kyma mode (real number returned), absent in local and in
BYOK Groq mode (no cost metadata).

Consumers MUST check key presence explicitly. From
[`output-schema.md`](output-schema.md): *"A `0` cost is meaningful
(cached transcript, free tier); an absent cost is 'the backend did
not tell us'."* Same rule applies in local mode.

---

## `audio-q` is API-only

`audio-q` reasons over the audio scene — tone, music, sound effects,
language, emotion — via a multimodal LLM. There is no local
open-source equivalent at the quality bar shipped today, so watch-cli
does not pretend to support offline `audio-q`.

When `WATCH_AUDIO_MODE=local` is set and any caller invokes
`audio-q`, the script fails with exit `2`, tag `audio-q-requires-api`:

```text
[audio-q] error: audio-q has no local backend tag=audio-q-requires-api
Audio scene Q&A requires a hosted model. Either:
  - unset WATCH_AUDIO_MODE to use the configured API path, or
  - export WATCH_AUDIO_MODE=kyma (or byok) for this call.
```

No silent fallback.

---

## Fallback policy

When local mode fails — model missing, binary missing, audio
unreadable, transcript empty, checksum mismatch — `bin/transcribe`
exits with the matching code from the table below. It does **not**
silently fall back to an API call. A user who chose local chose it
for privacy, cost, or network independence; silent fallback would
ship audio over the wire without consent. Users who want "prefer
local, fall back to API" can wrap `transcribe` and branch on the
exit code themselves — local-mode tags are distinct enough.

### Local-mode exit-code / tag table

| Condition | Exit | Stderr tag |
|---|---|---|
| Binary not on `PATH` | `2` | `missing-dep:whisper-cli` |
| Model file missing | `2` | `missing-dep:whisper-model` |
| User declined first-run download prompt | `2` | `missing-dep:whisper-model` |
| Insufficient disk before download | `1` | `insufficient-disk` |
| Downloaded model fails SHA256 check | `1` | `model-checksum-mismatch` |
| whisper.cpp returned non-zero | `4` | `transcribe-other` |
| whisper.cpp returned empty transcript | `4` | `transcribe-silent-audio` |

All tags are appended to the contract in [`exit-codes.md`](exit-codes.md)
under the same append-only rules as v1.

---

## `install.sh --with-local`

A new installer flag that bootstraps the local path end-to-end:

1. **Detect host OS.**
2. **macOS:** if `whisper-cli` missing, print
   `brew install whisper-cpp` (package `whisper-cpp`, binary
   `whisper-cli`) and prompt before running. Do not run brew
   automatically — brew installs touch the global environment.
3. **Debian / Ubuntu / generic Linux:** if `whisper-cli` missing,
   build from source into `~/.watch-cli/whisper.cpp/`
   (`git clone … && cmake -B build && cmake --build build -j --config Release`),
   then symlink `…/build/bin/whisper-cli` →
   `~/.local/bin/whisper-cli`. Requires `cmake` and a C++ toolchain;
   print an `apt install` hint and exit if either is missing.
4. **Disk-space check** — ≥ 2 GB free at `~/.watch-cli/models/` or
   abort with `insufficient-disk`.
5. **Download default model** with progress to stderr.
6. **SHA256-verify** against pinned hash; mismatch aborts.
7. **Print confirmation:**

   ```text
   ✓ whisper-cli installed at /usr/local/bin/whisper-cli
   ✓ model installed at ~/.watch-cli/models/ggml-large-v3-turbo.bin (1.62 GB)
   ✓ ~/.watch-cli/ now uses 1.7 GB of disk

   Try it offline:
     export WATCH_AUDIO_MODE=local
     watch https://www.youtube.com/watch?v=dQw4w9WgXcQ
   ```

`--with-local` is independent of `--with-skill` and `--with-mcp`;
combine or use any subset.

---

## Test plan

The implementer must verify, on a clean macOS or Ubuntu host:

1. **No binary, mode forced.** `WATCH_AUDIO_MODE=local`, no
   `whisper-cli` on `PATH` → exit `2`, stderr contains
   `tag=missing-dep:whisper-cli`. No download attempted.
2. **No model, mode forced, prompt declined.** Binary present, model
   absent, prompt declined → exit `2`, tag
   `missing-dep:whisper-model`. No file written under
   `~/.watch-cli/models/`.
3. **Happy path.** Binary + model + speech input → exit `0`, stdout
   contains the transcript. `watch --format json` omits
   `transcribe_cost_usd` (`jq 'has("transcribe_cost_usd")'` → `false`).
4. **Silent audio.** Local mode, silent input → exit `4`, tag
   `transcribe-silent-audio`, JSON `transcript` is `null`.
5. **Checksum mismatch.** Corrupt the model, rerun with mode forced
   → exit `1`, tag `model-checksum-mismatch`. No fallback to API
   even with `KYMA_API_KEY` set.
6. **`audio-q` blocked.** `WATCH_AUDIO_MODE=local`, `audio-q` on any
   input → exit `2`, tag `audio-q-requires-api`.
7. **No regression.** `tests/test-output-schema.sh` still passes with
   `WATCH_AUDIO_MODE` unset.

All seven are deterministic and scriptable; add to
`tests/test-offline-mode.sh` in the same PR.

---

## Anti-patterns

- **Do not commit the model binary to git.** 1.62 GB would break
  clone times, hosting limits, and CI caches. Model lives on
  HuggingFace, fetched on demand.
- **Do not auto-download models on first run without consent.** User
  must see the size and answer `y`. A 1.62 GB silent download on a
  tethered connection is an unforgivable surprise.
- **Do not silently fall back from local to any API path.** A user
  who chose local chose it for privacy, cost, or network
  independence. Falling back voids the choice.
- **Do not bundle whisper.cpp source.** Own release cadence and
  license. `install.sh --with-local` clones upstream into
  `~/.watch-cli/whisper.cpp/`; not a submodule.
- **Do not name competing hosted backends.** Per `BRANDING.md`,
  comparisons stay generic. Describe local mode as "fully offline"
  or "no API key required", not by contrast to a specific provider.

---

## Cross-references

- Exit-code semantics and tag conventions: [`exit-codes.md`](exit-codes.md).
  Eight new tags ship under the append-only v1 promise:
  `missing-dep:whisper-cli`, `missing-dep:whisper-model`,
  `missing-key:KYMA_API_KEY`, `missing-key:GROQ_API_KEY`,
  `missing-config`, `audio-q-requires-api`,
  `model-checksum-mismatch`, `insufficient-disk`.
- JSON / text shape + `transcribe_cost_usd` omission:
  [`output-schema.md`](output-schema.md).
- User-facing copy rules: [`../BRANDING.md`](../BRANDING.md).
