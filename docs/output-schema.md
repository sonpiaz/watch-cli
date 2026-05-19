# Output schema (v1)

watch-cli emits a single, structured payload on stdout. That payload is
a contract. Agents, MCP servers, shell wrappers, and CI scripts read it
and branch on its fields. Once a consumer has been written against this
shape, it should keep working across watch-cli patch and minor releases
without code changes.

This document is the source of truth for that contract: every field, the
stability promise around it, and the things consumers must *not* depend
on. The shipping `bin/watch` script and the future MCP server both
conform to this spec — if any of them drift, this document wins and the
implementation gets a bug fix.

---

## Two output formats, one schema

watch-cli supports two output formats in v1:

- **Text format** (default) — a human-skimmable, agent-parseable block.
  This is what `watch <url>` prints today.
- **JSON format** (opt-in via `--format json`) — a single compact JSON
  object on one line. Designed for `jq`, language-native parsers, and
  the MCP tool response shape.

Both formats carry the same data. Pick by audience: humans + Claude
Code read the text block fine; anything that wants to programmatically
extract a single field should use JSON.

---

## Version 1 — text format

The text block is a sequence of labeled lines and indented sub-blocks.
Line markers appear in this exact order:

```
WATCH_OUTPUT_VERSION: 1
VIDEO: <absolute-path-to-video-file>
DURATION: <integer-seconds>
FRAMES:
  <absolute-path-to-frame-1>
  <absolute-path-to-frame-2>
  …
TRANSCRIPT:
  <line 1 of transcript>
  <line 2 of transcript>
  …
EXIT: <integer-exit-code>
```

### Line markers, in order

| Marker | Required | Meaning |
|---|---|---|
| `WATCH_OUTPUT_VERSION: 1` | yes | First line of stdout. Lets a consumer detect the schema version before parsing anything else. A future v2 increments this number. |
| `VIDEO: <path>` | yes | One line. Absolute filesystem path to the downloaded video file. Always exists when this line appears — download succeeded. |
| `DURATION: <int>` | yes | Video length in whole seconds, derived from `ffprobe`. Integer, not float; consumers that need sub-second precision should re-probe the file. |
| `FRAMES:` | yes | Header line. Followed by N indented lines, one per extracted frame. |
| `  <path>` (under `FRAMES:`) | yes | Two-space-indented absolute paths to JPG frames. Order is "earliest-in-video first". The number of lines matches the requested frame count (default 8). |
| `TRANSCRIPT:` | yes | Header line. Followed by the indented transcript body. |
| `  <text>` (under `TRANSCRIPT:`) | yes | Two-space-indented transcript lines. If the transcribe step failed, this block contains the single literal token `null` on one indented line — see *Partial success* below. |
| `EXIT: <int>` | yes | Final line of stdout. Mirrors the process exit code. Documented in [`exit-codes.md`](exit-codes.md). |

### Whitespace and trailing newline

- Indentation under `FRAMES:` and `TRANSCRIPT:` is exactly two ASCII
  spaces. Consumers that need to be defensive can strip leading
  whitespace; do not depend on the exact count beyond "at least one".
- The block may or may not end with a trailing newline. Treat presence
  of trailing newline as undefined.
- Blank lines inside the transcript body are preserved with their
  indent intact.

### What appears on stderr

Progress lines (`[watch] downloading <url> …`, `[watch] transcribing
audio …`) and any error messages go to **stderr**, not stdout. The
stdout block is for consumers; stderr is for humans. See *What
consumers should not depend on* below.

---

## Version 1 — JSON format

`watch --format json <url>` emits exactly one line on stdout: a UTF-8
JSON object terminated by a single `\n`. The object has the following
fields.

### Field reference

| Field | Type | Required | Meaning |
|---|---|---|---|
| `version` | integer | yes | Always `1` in this schema. A future incompatible change ships as `2`. |
| `video_path` | string | yes | Absolute filesystem path to the downloaded video file. Same value as the text-format `VIDEO:` line. |
| `duration_sec` | number | yes | Video length in seconds. Emitted as a JSON number; may be integer or float depending on what `ffprobe` returned. |
| `frame_paths` | array of string | yes | Absolute paths to extracted JPG frames. Ordered earliest-in-video first. Length matches the requested frame count. |
| `transcript` | string or null | yes | Full transcript text, or `null` if the transcribe step failed (in which case `exit_code` will be `4`). The field is always present — its value, not its presence, signals failure. |
| `exit_code` | integer | yes | Final exit code from `bin/watch`. Mirrors the text-format `EXIT:` line and the process exit. See [`exit-codes.md`](exit-codes.md). |
| `transcribe_cost_usd` | number | no | Per-call transcribe cost in US dollars, when the backend reports it. Absent (key not present) when unknown — for example, when running with a BYOK key against a provider that does not return cost metadata. |

### Required vs optional

"Required" means the key is guaranteed to be present in every v1 JSON
output, regardless of success or failure. "Optional" means the key may
be absent. Consumers should treat absence as "value unknown", not as
zero or empty.

A consumer that wants the cost field should check key presence
explicitly (`if "transcribe_cost_usd" in obj` in Python, `.transcribe_cost_usd
// empty` in `jq`) rather than defaulting absent values to `0`. A `0`
cost is meaningful (cached transcript, free tier); an absent cost is
"the backend did not tell us".

---

## Stability promise

The shape above is **v1**. The promise inside v1 is:

- **Append-only.** Adding a new optional JSON field, or a new text-block
  marker that consumers can ignore, is a **minor** release. Existing
  consumers keep working without changes.
- **No renames within v1.** A field will not be renamed inside v1. If
  the field is misnamed, it is corrected in v2.
- **No type changes within v1.** A field will not change its JSON type
  inside v1. `duration_sec` stays numeric; `frame_paths` stays an array
  of strings; `transcript` stays "string or null".
- **No removals within v1.** A required field will not be removed inside
  v1. An optional field can be deprecated in a minor release with a
  changelog note but stays parseable.

Anything outside that promise — renaming a field, removing a field,
changing a field type, changing the meaning of a value — is a
**major** version bump. v2 will increment `WATCH_OUTPUT_VERSION:` (text)
and `"version": 2` (JSON). v1 output continues to be available via an
opt-in flag for at least one major release after v2 ships.

### How a consumer detects the version

- **Text mode:** parse the first line of stdout. It is always
  `WATCH_OUTPUT_VERSION: <int>`. Switch on the integer.
- **JSON mode:** parse the line as JSON, read `obj.version`. Switch on
  the integer.

Do not detect the version by sniffing for fields. A field that exists
in v1 today may exist with different semantics in v3. The version
number is the only correct signal.

---

## Worked examples

Same hypothetical input for both: a 218-second YouTube video at
`https://www.youtube.com/watch?v=abc123`, requesting the default 8
frames.

### Example 1 — text format

```text
$ watch https://www.youtube.com/watch?v=abc123
WATCH_OUTPUT_VERSION: 1
VIDEO: /tmp/dl-video/abc123.mp4
DURATION: 218
FRAMES:
  /tmp/frames_abc123/frame_01.jpg
  /tmp/frames_abc123/frame_02.jpg
  /tmp/frames_abc123/frame_03.jpg
  /tmp/frames_abc123/frame_04.jpg
  /tmp/frames_abc123/frame_05.jpg
  /tmp/frames_abc123/frame_06.jpg
  /tmp/frames_abc123/frame_07.jpg
  /tmp/frames_abc123/frame_08.jpg
TRANSCRIPT:
  Today I want to talk about how decomposition unlocks ten times cost
  reduction in multimodal pipelines. The core idea is that a video is
  just frames plus audio, and each of those already has a fast,
  near-free primitive that has existed for years.
EXIT: 0
```

Stderr during the same run (informational, not part of the contract):

```text
[watch] downloading https://www.youtube.com/watch?v=abc123 …
[watch] video: /tmp/dl-video/abc123.mp4
[watch] extracting 8 frames …
[watch] transcribing audio …
```

### Example 2 — JSON format

```text
$ watch --format json https://www.youtube.com/watch?v=abc123
```

Resulting stdout (formatted across multiple lines for readability — the
actual output is one line):

```json
{
  "version": 1,
  "video_path": "/tmp/dl-video/abc123.mp4",
  "duration_sec": 218,
  "frame_paths": [
    "/tmp/frames_abc123/frame_01.jpg",
    "/tmp/frames_abc123/frame_02.jpg",
    "/tmp/frames_abc123/frame_03.jpg",
    "/tmp/frames_abc123/frame_04.jpg",
    "/tmp/frames_abc123/frame_05.jpg",
    "/tmp/frames_abc123/frame_06.jpg",
    "/tmp/frames_abc123/frame_07.jpg",
    "/tmp/frames_abc123/frame_08.jpg"
  ],
  "transcript": "Today I want to talk about how decomposition unlocks ten times cost reduction in multimodal pipelines. The core idea is that a video is just frames plus audio, and each of those already has a fast, near-free primitive that has existed for years.",
  "exit_code": 0,
  "transcribe_cost_usd": 0.00018
}
```

To extract a single field:

```bash
watch --format json https://www.youtube.com/watch?v=abc123 | jq -r .transcript
watch --format json https://www.youtube.com/watch?v=abc123 | jq -r '.frame_paths[]'
```

---

## Partial success

A run can extract frames successfully but fail the transcribe step (the
backend timed out, the audio is silent, the quota is exhausted). v1
represents this by:

- Setting `exit_code` / `EXIT:` to `4` (transcribe failed — see
  [`exit-codes.md`](exit-codes.md)).
- Keeping `frame_paths` populated with the frames that did extract.
- Setting `transcript` to JSON `null` (JSON mode), or printing the
  single literal token `null` inside the `TRANSCRIPT:` block (text
  mode).

This lets a calling agent still consume the frames even when the
transcript is unavailable. Branching by `exit_code` is documented in
the exit-codes spec.

---

## What consumers should *not* depend on

The contract above is what watch-cli promises to keep stable. Anything
else is implementation detail and is allowed to change in any release,
including patch releases.

Concretely, **do not** write parsers that depend on:

- **Raw stderr formatting.** The `[watch] downloading …` lines, their
  prefix, their wording, and their presence at all can change. Stderr
  is for human eyes. Programmatic consumers should ignore it.
- **Exact whitespace inside the `TRANSCRIPT:` block.** Indentation is
  guaranteed to be "at least one space"; the count, the use of tabs vs
  spaces in future versions, and the line-wrapping policy are not part
  of the contract.
- **Frame path names beyond their type.** Today frames are named
  `frame_NN.jpg` under `/tmp/frames_<id>/`. The directory name, the
  numeric prefix, the zero-padding, and even the `.jpg` extension are
  implementation details. The promise is "absolute paths to extracted
  frames, ordered earliest-first". Consume them by reading the file
  bytes, not by parsing the filename.
- **Order of optional JSON fields.** JSON object key order is unstable
  across releases; required fields are always present but their order
  inside the object is undefined. Use a real JSON parser, not regex.
- **Presence of a trailing newline.** May or may not be there. Strip if
  you care.
- **Stderr being empty on success.** It is not. Progress lines always
  print to stderr regardless of success or failure.
- **The presence of an extra blank line before `EXIT:`.** Allowed.

If a consumer needs a behavior that is not in the *required* field
table above, file an issue. Working around the implementation by
parsing fragile details guarantees breakage on the next release.

---

## Cross-references

- Exit code semantics, stderr tag conventions, partial-success rule
  details: [`exit-codes.md`](exit-codes.md).
- Platform-level "did the download succeed at all" matters:
  [`platforms.md`](platforms.md).
- Cookie-walled sources before parsing failures get blamed on schema:
  [`cookies.md`](cookies.md).
