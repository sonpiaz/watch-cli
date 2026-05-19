# watch-cli — Defend the Niche: 4-6 Week Plan

## Ranked work items

### 1. Version the output schema

**Why:** Counters threat #1 ("just a wrapper"). A versioned, machine-parseable output contract is the difference between a convenience script and a composable tool. yt-dlp's `-j` JSON output is the thing that made it embeddable into 10,000 downstream tools. Today `watch` prints an ad-hoc `VIDEO:/FRAMES:/TRANSCRIPT:` block with no version marker, no machine-parse mode, and no stability promise. One breaking change (add a field, change indentation) silently breaks every downstream consumer.

**Deliverable:**
- Add `--format json` flag to `bin/watch` that emits a single JSON object: `{"version":"1","video":"/path","duration":218,"frames":["/path1",...],"transcript":"..."}`.
- Add `WATCH_OUTPUT_VERSION: 1` header line to the existing text format.
- Add `docs/output-schema.md` documenting both formats with the contract: "v1 fields are append-only; removals or type changes bump the major version."
- Add a shell test (`tests/test-output-schema.sh`) that parses both formats and asserts field presence.

**Effort:** 1 day

**Depends on:** Nothing. Ship first.

---

### 2. Offline/local transcription path (whisper.cpp)

**Why:** Counters threat #1 AND #2. The loudest "just a wrapper" objection is "but I need an API key." The strongest durability trait of yt-dlp/ffmpeg is zero external service dependency. Today watch-cli cannot function without Kyma or Groq. Adding a local whisper.cpp path means: (a) the tool works on an airplane, (b) it works if Kyma/Groq go down, (c) it removes the "marketing trojan" suspicion for HN, (d) the BYOK section becomes "BYOK or fully offline."

**Deliverable:**
- New routing mode in `lib/env.sh`: `WATCH_AUDIO_MODE=local` when `whisper-cpp` (or `whisper`) is on `$PATH` and no API key is set.
- `bin/transcribe` gains a `local` case that calls `whisper-cpp -m <model> -f <audio> --output-txt`.
- `install.sh` gains an optional `--with-local` flag that downloads the `ggml-large-v3-turbo` model (~1.5GB) into `~/.watch-cli/models/`.
- README gets a "Fully offline" section with 3-line setup.
- `audio-q` stays API-only (Gemini native audio has no local equivalent worth shipping). Document this honestly.

**Effort:** 2 days

**Depends on:** Nothing. Can run parallel to #1.

---

### 3. Structured error handling with exit codes

**Why:** Counters threat #2 (upstream breakage). Today, if yt-dlp 403s on a LinkedIn URL or Kyma returns a 500, the user sees a raw curl/yt-dlp error piped to stderr. A composable tool needs: (a) documented exit codes so a wrapping script can branch, (b) actionable error messages ("yt-dlp returned 403 on linkedin.com -- sign in to Chrome and retry, or pass --cookies"), (c) no silent failures (the current `|| true` on frame extraction swallows ffmpeg errors).

**Deliverable:**
- `docs/exit-codes.md` defining the contract: 0=success, 1=general error, 2=missing dependency, 3=download failed (with sub-message: auth-required / region-locked / network), 4=transcribe failed (with sub-message: quota / timeout / silent-audio), 64=usage error.
- Refactor all 6 `bin/*` scripts to use these codes consistently. Remove the `|| true` in `extract-frames` (replace with frame-count validation after the loop).
- `watch` emits a final `EXIT: <code>` line in JSON mode (or sets `"exit_code"` in JSON output) so a wrapping agent can programmatically detect partial success (e.g., frames OK but transcribe failed).

**Effort:** 1 day

**Depends on:** #1 (output schema version) should ship first so the exit code can be part of v1.

---

### 4. Cross-platform CI matrix (macOS + Ubuntu + basic Windows)

**Why:** Counters threat #1. yt-dlp and ffmpeg are cross-platform from day 1. watch-cli claims the same (bash scripts + standard tools) but has zero CI and zero Windows testing. A GitHub Actions matrix that runs `install.sh` + a dry-run `watch` on macOS and Ubuntu proves the claim. Windows/WSL can be a stretch goal.

**Deliverable:**
- `.github/workflows/ci.yml`: matrix of `macos-latest` + `ubuntu-latest`. Steps: install deps, run `install.sh`, run `watch --help` + `transcribe --help` + `extract-frames --help` (smoke), run `tests/test-output-schema.sh` from #1.
- Badge in README: `![CI](https://github.com/sonpiaz/watch-cli/actions/workflows/ci.yml/badge.svg)`.
- One `stat -f%z` vs `stat -c%s` portability issue already exists in `transcribe` and `audio-q` (macOS vs Linux `stat` flag). CI will catch this. Fix both scripts to use `wc -c < "$file"` (POSIX) instead.

**Effort:** half day

**Depends on:** #1 (needs a test to run in CI). Can otherwise ship after #1.

---

### 5. Upstream health probe in `watch`

**Why:** Counters threat #2 directly. When yt-dlp breaks on a platform (happens weekly for TikTok, monthly for LinkedIn), the user blames watch-cli. A 2-second pre-flight check against a known-good URL per platform, cached for 24h, can surface "yt-dlp cannot reach tiktok.com right now -- run `yt-dlp -U` to update" before wasting 30 seconds on a doomed download.

**Deliverable:**
- `lib/health.sh` with a `check_platform <domain>` function. Tries `yt-dlp --simulate --quiet <canary-url>` for the detected platform. Caches result in `/tmp/watch-cli-health/<domain>.ok` with a 24h TTL.
- `bin/watch` calls `check_platform` before `dl-video`. On failure, prints actionable message and exits with code 3.
- `docs/platforms.md` gets a "Breakage and recovery" section: "If a platform stops working, run `yt-dlp -U`. If that doesn't fix it, check github.com/yt-dlp/yt-dlp/issues."

**Effort:** half day

**Depends on:** #3 (exit codes).

---

### 6. HN re-submission with karma + show-and-tell content

**Why:** Counters threat #1 by proving the tool's value through real artifacts, not claims. The previous HN submit was auto-flagged due to low karma. The 14-day cooldown expires ~May 26. Between now and then: (a) build karma via genuine HN participation (comments, not posts), (b) create 2-3 "show and tell" examples that demonstrate the prompt library producing real artifacts (architecture diagram from a conference talk, working clone from a tutorial), (c) post the Show HN with these as inline evidence.

**Deliverable:**
- `examples/` directory with 2-3 subdirectories, each containing: the watch output (redacted transcript snippet, not full), the prompt used, the final artifact (HTML file, .tsx file, or notebook), and a 3-line writeup.
- HN post draft in `.internal/hn-show-draft.md` -- title, body, talking points for comments.
- Karma target: 30+ before May 26.

**Effort:** 1 week (spread across the period, not continuous)

**Depends on:** #1 and #2 should be shipped before the post so the README reflects a versioned schema and an offline path.

---

### 7. `watch --pipe` for stdin/stdout composability

**Why:** Counters threat #1. The deepest durability trait of Unix tools is composability via pipes. Today `watch` requires a URL argument. Adding `--pipe` (or detecting stdin) means: `echo "https://..." | watch --pipe --format json | jq .transcript` works. This is the primitive that lets watch-cli slot into shell pipelines, Makefiles, and CI scripts without wrapping.

**Deliverable:**
- `bin/watch` reads from stdin when `--pipe` is passed or when stdin is not a TTY and no URL argument is given.
- Accepts one URL per line; outputs one JSON object per line (JSONL) when `--format json` + `--pipe`.
- `examples/batch-watch.sh`: a 5-line script that reads a file of URLs and produces a directory of artifacts.

**Effort:** half day

**Depends on:** #1 (JSON output format).

---

## Refuse-to-build list

| Temptation | Why refuse |
|---|---|
| **Built-in video summarizer** | Moves watch-cli from "give the agent raw materials" to "be the agent." The prompt library already handles this without code. Adding a `--summarize` flag couples the tool to a specific LLM and opinion about what a summary looks like. |
| **Frame deduplication / smart frame selection** | Sounds valuable, but requires a vision model or perceptual hashing -- both add a dependency and slow the pipeline. The current "evenly spaced, skip first/last" heuristic is dumb and fast. Users who need smarter selection should pipe frames through their own tool. |
| **TUI / interactive mode** | Violates composability. A TUI cannot be piped. It appeals to demo videos but repels the actual audience (agents and shell scripts). |
| **Multi-video batch dashboard / progress UI** | Scope creep toward a "video research platform." Batch is solved by `xargs` or the `--pipe` mode in item #7. A dashboard is a different product. |
| **Native Windows `.exe` or `.ps1` port** | WSL covers 95% of Windows developer use cases. A native port doubles the maintenance surface for a platform where the dependency chain (yt-dlp, ffmpeg, python3) is already painful. Support WSL in docs; don't port. |

---

## Top recommendation: the single highest-leverage durability investment

**Ship the versioned JSON output schema (#1) before anything else.**

This is the direct parallel to how yt-dlp achieved its durability. yt-dlp's `-j`/`--dump-json` flag is what made it embeddable into Tartube, ArchiveBox, Tube Archivist, and thousands of custom scripts. The JSON output is a contract: downstream tools depend on it, which creates switching cost and community investment. yt-dlp's extractors break weekly, but the output schema has been stable for years.

watch-cli's current text block is already close -- it is structured and parseable. But it has no version marker, no machine format, and no stability promise. Adding `--format json` with a `"version":"1"` field turns watch-cli from "a script I might rewrite" into "a contract I build on top of." Every subsequent item in this plan (exit codes, pipe mode, CI tests, examples) depends on or benefits from having a stable schema to reference.

Once the schema exists, the prompt library and Claude Code skill can reference it by version. Other agents (Cursor, Cline, Roo Code) can write parsers against it. And the README can honestly say: "v1 output is append-only. Your scripts won't break."

That is the sentence that turns a wrapper into infrastructure.

---

# Distribution & Agent-Integration Layer (added 2026-05-19)

The original 7 items defend the niche on the **durability** axis. This section adds the **reach** axis: making watch-cli the tool that production coding/research agents actually pick up — concretely OpenClaw (`openclaw/openclaw`, 373K stars, MIT, TS, plugin + skill system, speaks MCP natively) and hermes-agent (`NousResearch/hermes-agent`, 157K stars, MIT, Python, ships FastMCP stdio bridge + ACP adapter + optional-skills folder).

Current distribution coverage ≈ 15% of what mature CLI tools have. Two channels active (`curl ... | bash`, manual `cp -r skills/`), 10+ channels missing. The biggest gap is **agent-side integration formats** — exactly where watch-cli has structural advantage over yt-dlp/ffmpeg.

## Ranked items

### 8. Ship a portable `SKILL.md` at the repo root

**Why:** Single highest-leverage agent-integration. OpenClaw (`skills/<name>/SKILL.md`), Hermes (`optional-skills/<domain>/<name>/SKILL.md`), and Claude Code (`~/.claude/skills/<name>/`) all consume the **same** Anthropic-spec markdown grammar — YAML frontmatter (`name`, `description`) + prose. One file, four production agents reached same day. The existing `skills/watch-cli/SKILL.md` only addresses Claude Code; widening the frontmatter to OpenClaw's shape (`metadata.openclaw.requires.bins: ["watch"]` + `install[]`) is harmless on Claude Code and unlocks OpenClaw + Hermes for free.

**Deliverable:**
- Move `skills/watch-cli/SKILL.md` → repo-root `SKILL.md` (or both, with the root one being canonical and the `skills/` one a symlink for backward compat).
- Frontmatter shape: `name`, `description`, `homepage`, `metadata.openclaw.requires.bins: ["watch"]`, `metadata.openclaw.install[]` entry pointing at the curl-install one-liner.
- Body: ~150 words on what `watch` does, when to invoke it, parse rules for both text and JSON output (depends on #1).
- `docs/agent-integrations.md` cross-links explaining "this same SKILL.md works in Claude Code, OpenClaw, and Hermes" with install one-liners per agent.

**Effort:** 1 hour (file edits) + 1 hour (cross-doc).

**Depends on:** #1 (so SKILL.md can reference `--format json` as the canonical output for tool callers).

---

### 9. Ship an MCP stdio server (`@sonpiaz/watch-cli-mcp` or built-in `watch --mcp-serve`)

**Why:** MCP is the lingua franca by 2026. Claude Code, Claude Desktop, Cursor, Codex, OpenClaw, Hermes, Zed, Continue.dev, Cline, Windsurf, Kiro, VS Code Copilot — all consume it. Writing one MCP server reaches 12+ agents; writing per-IDE plugins is the anti-pattern. Hermes's `mcp_serve.py` comment ("Matches OpenClaw's 9-tool MCP channel bridge surface") is direct evidence both target agents speak MCP natively.

**Deliverable:**
- New `mcp-server/` directory (or `--mcp-serve` subcommand on the existing `watch` script if simpler).
- Implementation: TypeScript with `@modelcontextprotocol/sdk`, OR Python with `mcp` package. TS preferred because OpenClaw is TS and the Anthropic SDK is more polished.
- One tool exposed: `watch` with input schema `{url: string, frames?: number}` returning `{video_path: string, frame_paths: string[], transcript: string, duration: number, version: 1}`.
- Wire format: JSON-RPC over stdin/stdout, newline-delimited, UTF-8, no embedded newlines (per [MCP spec 2025-03-26](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports)).
- Publish to npm as `@sonpiaz/watch-cli-mcp` (or scoped under future `@kyma-api/`).
- README adds: "Run as MCP server: `npx @sonpiaz/watch-cli-mcp`. Register in your agent's MCP config…" with snippets for Claude Desktop config, Cursor mcp config, Hermes config.

**Effort:** 1 day (server itself) + ½ day (npm publish + docs).

**Depends on:** #1 (server returns the v1 JSON schema directly — no parsing of the text block).

---

### 10. Auto-install Claude Code skill in `install.sh`

**Why:** watch-cli's biggest agent differentiator vs raw yt-dlp + ffmpeg is the skill — but install is manual `cp -r`. Adding `--with-skill` to install.sh (or auto-detect `~/.claude/skills/` and offer) turns the differentiator from "if you read the README" to "happened automatically on `curl | bash`."

**Deliverable:**
- `install.sh --with-skill` flag (or interactive prompt if `~/.claude/` exists): copies/symlinks `skills/watch-cli/` (or the new root `SKILL.md`) into `~/.claude/skills/`.
- Optional: `install.sh --with-mcp` for the MCP server (after #9 ships).
- README install section adds a one-liner: `curl ... | bash -s -- --with-skill`.

**Effort:** ½ day.

**Depends on:** #8 (skill content stable in tree).

---

### 11. GitHub Releases + semver tags + auto-update CI

**Why:** Foundation for every package manager. Homebrew formulas reference tagged releases. Docker tags reference releases. npm publish workflow needs `v*` tags to fire. Today watch-cli has **0 tags, 0 releases** — `install.sh` permanently points at `main` HEAD, which is fragile (one bad commit breaks everyone). yt-dlp's auto-update relies on its release cadence.

**Deliverable:**
- `.github/workflows/release.yml`: on `v*` tag push, build a sourceball tar + upload `install.sh` as a release asset.
- Tag v1.0.0 covering current state (after #1 + #3 schema/exit-code stability promised).
- Subsequent versions follow semver: bump major if output schema changes incompatibly, minor for new features, patch for bug fixes.
- README updates `install.sh` URL to point at the latest release tag instead of `main`.

**Effort:** ½ day.

**Depends on:** #1 + #3 (need stable schema + exit codes before "v1.0.0" claim is honest).

---

### 12. Homebrew tap (`brew install sonpiaz/tap/watch-cli`)

**Why:** Mac dev = primary audience. Tap (not core) is 10× easier than upstreaming homebrew-core. Lands watch-cli in the same install command users already type for yt-dlp and ffmpeg.

**Deliverable:**
- New repo `sonpiaz/homebrew-tap` with `Formula/watch-cli.rb` referencing the GH release tarball + SHA256.
- Formula declares deps on `yt-dlp`, `ffmpeg`, `jq` (so `brew install` handles the dep chain automatically — current `install.sh` only warns).
- CI workflow in the watch-cli repo bumps the tap formula on every release.
- README install section adds: `brew install sonpiaz/tap/watch-cli` as the first option for macOS.

**Effort:** 1 day (formula + bump automation).

**Depends on:** #11 (tap formulas point at versioned release artifacts).

---

### 13. Listings — places where watch-cli should APPEAR, not BUILD

Zero-code distribution. Submit watch-cli to:

| Listing | When |
|---|---|
| [`anthropics/skills`](https://github.com/anthropics/skills) marketplace PR | After #8 ships |
| `awesome-claude-code` GH list | After #8 ships |
| `awesome-mcp-servers` GH list | After #9 ships |
| MCP server registry (modelcontextprotocol.io) | After #9 ships |
| OpenClaw plugin marketplace (when it opens — currently no public marketplace, but `openclaw/openclaw/skills/` accepts PRs) | After #8 ships |
| Hermes `optional-skills/research/` PR | After #8 ships |
| yt-dlp wiki "Alternative tools / wrappers" page | After #11 (versioned release exists) |
| Reddit r/ClaudeAI, r/LocalLLaMA, r/SideProject (show-and-tell) | After #6 (HN re-submit content) is built |

**Effort:** ~½ day per listing × 8 = 4 days of writing, spread over the rollout.

**Depends on:** Each listing depends on its respective build item above.

---

## Updated refuse-to-build list (additions for the distribution layer)

| Temptation | Why refuse |
|---|---|
| **Bespoke plugin per IDE agent** (one each for Cursor, Cline, Roo Code, Continue, Windsurf, Kiro) | All consume MCP. Writing N plugins is the lock-in trap. MCP server in #9 reaches all of them via one codebase. |
| **Mixing runtime entrypoints into SKILL.md** | OpenClaw's manifest spec is explicit: "Do not use it for registering runtime behavior, declaring code entrypoints, or npm install metadata." Keep `SKILL.md` to prose + `requires.bins` declaration; let the agent shell out. Mixing surfaces will get the skill rejected by reviewers. |
| **Making the human-readable VIDEO:/FRAMES:/TRANSCRIPT: block the canonical contract** | Claude Code parses it today only because Son's global `~/.claude/CLAUDE.md` has the parse rules baked in. No other agent has that context. Cross-agent integrations MUST consume `--format json` (#1) or the MCP tool response (#9), never the text block. |
| **OpenAI function-calling JSON schema as primary** | Lowest ROI: agents that read tool schemas mostly read MCP today. Ship it only as a `examples/openai-tools.json` snippet, never as the primary integration. |
| **Auto-installing the MCP server into every agent at install time** | Agents have per-user MCP config (`~/Library/Application Support/Claude/claude_desktop_config.json` for Claude Desktop, `.cursor/mcp.json` for Cursor, etc.). install.sh should *generate config snippets* the user can paste, not silently edit those files. |

---

## Revised top recommendation (supersedes the prior one)

Ship in this exact sequence, because each one is the **enabling foundation** for the next:

1. **#1 versioned JSON output schema** — still the foundation. Without it, the MCP server and SKILL.md have no stable contract to reference. Ship in week 1.
2. **#8 portable SKILL.md** — 1–2 hours of work, immediately puts watch-cli into OpenClaw, Hermes, and Claude Code skill systems. Ship in week 1 alongside #1.
3. **#9 MCP stdio server** — unlocks every MCP-capable agent (12+) in one stroke. Ship in week 2.

This three-step sequence converts watch-cli from "a tool with a curl installer" into "a tool that every production AI agent can pick up by typing one line." It's the precise distribution move that mature CLIs (yt-dlp's `-j` flag → Tartube + ArchiveBox + Tube Archivist, ffmpeg's libavcodec → every video tool on earth) used to become irreplaceable infrastructure.

---

## Revised 4–6 week sequencing (all 12 items)

| Week | Items | Theme |
|---|---|---|
| **1** | #1 schema version + #4 CI matrix + #3 exit codes + #8 SKILL.md | Foundation: contract + skill |
| **2** | #2 offline whisper.cpp + #9 MCP server + #7 `--pipe` | Resilience + agent integration |
| **3** | #11 GH Releases + #10 install.sh auto-skill + #12 Homebrew tap + #5 health probe | Packaging + reach |
| **4** | #13 listing submissions (anthropics/skills, awesome-mcp, OpenClaw PR, Hermes PR) + #6 HN re-submit prep | Distribution rollout |
| **5–6** | #6 HN re-submit (karma ≥ 30, cooldown done) + iterate on feedback | Public surface |

Total effort estimate: **~12 days of focused work**, fits 4–6 weeks at 10h/week with buffer for breakage.

---

# Locked Unique Features (2026-05-19)

Two features that no other CLI in this space ships. Every downstream artifact (README tagline, SKILL.md description, MCP tool description, listing PRs, HN post) MUST reinforce one or both. Anything that doesn't is scope creep.

## U1 — Agent-shaped raw-materials output

`VIDEO + FRAMES + TRANSCRIPT` in a single structured block designed for LLM consumption. Agents read frames as images and transcript as text. This is the composition no upstream tool does:

- `yt-dlp` → video file only
- `ffmpeg` → frames only
- `whisper` / `whisper.cpp` → transcript only
- Subscription summary tools → polished human summary (wrong artifact)
- Multimodal video APIs → opinionated text recap (wrong artifact)

Watch-cli is the **only tool that composes the raw materials in the shape an LLM agent actually consumes them.**

Verifiable in: `bin/watch` text output today, and the `--format json` schema landing in Phase 1.

## U2 — Prompt library mapping watch output → concrete deliverables

Five prompts in `prompts/` that convert `watch` output into specific artifacts:

| Prompt | Input | Output |
|---|---|---|
| `implement-from-video.md` | Coding walkthrough video | Working project files |
| `extract-architecture.md` | System / talk video | Interactive architecture diagram |
| `clone-ux.md` | UI / motion demo | Working React component |
| `paper-to-code.md` | Paper / research talk | Runnable notebook |
| `tutorial-walkthrough.md` | Long tutorial | Step-by-step cheat sheet |

No other CLI ships this. The Affitor-architecture demo (102K views on FB) is direct proof of U2 working in the wild.

## Locked one-line pitch

> **watch any social video → get an architecture diagram, working component, runnable notebook, or step-by-step cheat sheet — automatically.**

Reuse this exact pitch (or close variants) in: README tagline, SKILL.md description, MCP server `description` field, listing PR descriptions, HN post first line, social posts.

---

# Phase Plan with Sub-Spec Gates (2026-05-19)

Restructures the 13 items above into 5 phases. **Big tasks marked `🔍 needs sub-spec`** — author the sub-spec document BEFORE implementation. Each phase has an exit criterion.

## Phase 0 — Lock positioning (½ day, no code)

Goal: U1 + U2 visible within the first scroll of README and propagated to SKILL.md (Phase 2 input).

| Task | Effort |
|---|---|
| Rewrite README tagline + first paragraph to lead with the locked one-line pitch | 1h |
| Add a "What you can build" section above install: 5 rows linking to `prompts/` files, each with a 1-line outcome | 1h |
| Lock pitch language in a new `BRANDING.md` (1-pager, internal) — single source of truth for taglines, anti-patterns, words to avoid | 1h |

**Exit:** README rendered on GitHub shows U1 + U2 above the install fold. Every later artifact references `BRANDING.md`.

---

## Phase 1 — Foundation contract (~3 days, week 1)

Goal: stable schema + exit codes + CI. The contract every downstream consumer (skill, MCP, brew, npm) depends on.

| Task | Effort | Sub-spec? |
|---|---|---|
| **#1 Versioned JSON output schema** | 1d | 🔍 `docs/output-schema.md` |
| **#3 Structured exit codes** | 1d | 🔍 `docs/exit-codes.md` |
| #4 CI matrix (macOS + Ubuntu) + fix `stat` portability | ½d | no |

### 🔍 Sub-spec: `docs/output-schema.md`

Must cover before implementing #1:
- v1 JSON shape: every key with type + optional/required (`version`, `video_path`, `duration_sec`, `frame_paths`, `transcript`, `transcribe_cost_usd`, `exit_code`)
- v1 text shape: leading `WATCH_OUTPUT_VERSION: 1` header line, block markers (`VIDEO:`, `FRAMES:`, `TRANSCRIPT:`), trailing `EXIT: <code>` line
- Stability promise: append-only within v1; breaking change → v2; how a consumer detects version safely
- 2 worked examples (text + JSON) for the same input
- Anti-example: what NOT to depend on (raw stderr, exact whitespace inside transcript)

### 🔍 Sub-spec: `docs/exit-codes.md`

Must cover before implementing #3:
- Code table: 0 / 1 (general) / 2 (missing dep) / 3.x (download — auth-required, region-locked, network) / 4.x (transcribe — quota, timeout, silent-audio) / 64 (usage)
- For each code: when emitted, exact stderr message, recommended user action
- Partial-success rule: frames OK + transcribe failed → exit 4.x, JSON still emits `frame_paths` filled and `transcript: null`
- Behavior under `set -e` in calling scripts

**Exit:** both sub-specs merged → schema + exit-codes implemented to spec → CI green on macOS+Ubuntu → ready to tag v1.0.0 (foundation for Phase 4).

---

## Phase 2 — Agent surfaces (~2 days, week 1–2)

Goal: pickupable by Claude Code + OpenClaw + Hermes + any MCP agent. Both U1 and U2 surfaced through agent-native channels.

| Task | Effort | Sub-spec? |
|---|---|---|
| **#8 Portable SKILL.md** (Claude Code + OpenClaw + Hermes compatible) | 1h | 🔍 `skills/SKILL-SPEC.md` (1-pager) |
| **#9 MCP stdio server** | 1d | 🔍 `mcp-server/SPEC.md` |
| #10 `install.sh --with-skill` auto-install flag | ½d | no |

### 🔍 Sub-spec: `skills/SKILL-SPEC.md`

Must cover before implementing #8:
- Frontmatter shape that's valid in all 3 platforms (Anthropic spec required: `name`, `description`; OpenClaw extras: `metadata.openclaw.requires.bins`, `install[]`; Hermes inherits Anthropic spec)
- File location rule: canonical at repo-root `SKILL.md`, symlinked to `skills/watch-cli/SKILL.md` for back-compat
- Description text uses locked pitch from `BRANDING.md`
- Body parse rules reference `docs/output-schema.md` (v1 JSON, not text regex)
- Install one-liners per platform documented in `docs/agent-integrations.md`

### 🔍 Sub-spec: `mcp-server/SPEC.md`

Must cover before implementing #9:
- Tool definition: name (`watch`), input schema (`{url: string, frames?: number}`), output schema (must match `docs/output-schema.md` v1 JSON exactly — no divergence)
- Lifecycle: stdio server, JSON-RPC line-delimited, terminates on EOF, no embedded newlines
- Error model: which MCP error codes for which scenarios (auth-required, network, transcribe-failed, usage)
- Language choice: TS preferred (Anthropic SDK polish, OpenClaw is TS). Alternative: built into `watch --mcp-serve` subcommand to avoid second package
- Package layout: standalone `mcp-server/` OR built-in subcommand — decide in spec, document why
- npm publish: package name `@sonpiaz/watch-cli-mcp`, version mirrors watch-cli release (so MCP v1.2.0 = watch-cli v1.2.0)
- Test plan: integration test via `mcporter call watch.watch url=<known-good-yt-url>` in CI

**Exit:** `npx @sonpiaz/watch-cli-mcp` boots; tool `watch` callable from Claude Desktop + mcporter; SKILL.md drops cleanly into `~/.claude/skills/`, `openclaw/skills/`, and `hermes-agent/optional-skills/research/`.

---

## Phase 3 — Resilience (~2.5 days, week 2)

Goal: handle upstream breakage gracefully + enable fully offline transcribe.

| Task | Effort | Sub-spec? |
|---|---|---|
| **#2 Offline whisper.cpp path** | 2d | 🔍 `docs/offline-mode.md` |
| #5 Upstream health probe | ½d | no (depends on Phase 1 exit codes) |
| #7 `watch --pipe` stdin/stdout mode | ½d | no |

### 🔍 Sub-spec: `docs/offline-mode.md`

Must cover before implementing #2:
- Detection: routing priority order — `WATCH_AUDIO_MODE` env override > whisper-cpp on PATH + no KYMA_API_KEY > BYOK Groq > Kyma (default)
- Model lifecycle: which model is default (`ggml-large-v3-turbo` ~1.5GB), where stored (`~/.watch-cli/models/`), how downloaded (`install.sh --with-local` triggers, otherwise on-demand prompt at first `transcribe`)
- `audio-q` honest disclaimer: stays API-only (no local Gemini-native-audio equivalent), document this without competitor naming
- Disk-space check before download, error message if insufficient
- Fallback policy when local fails: error code 4.x, don't silently fall back to API (user explicitly chose offline)

**Exit:** `watch <yt-url>` works on a fresh machine with network disconnected after install + model download.

---

## Phase 4 — Packaging (~2 days, week 3)

Goal: install friction → near-zero (one brew or npm line). Enables Phase 5 listings.

| Task | Effort | Sub-spec? |
|---|---|---|
| **#11 GH Releases + semver tags + release.yml workflow** | ½d | 🔍 `docs/releases.md` (½-pager) |
| **#12 Homebrew tap (`sonpiaz/homebrew-tap`)** | 1d | 🔍 `docs/homebrew.md` (½-pager) |
| Bump automation: tap formula auto-updates on each watch-cli release | ½d | no |

### 🔍 Sub-spec: `docs/releases.md`

Must cover before implementing #11:
- Semver policy: major bump if output schema changes incompatibly (per Phase 1 spec); minor for new features; patch for bug fixes
- Release notes template (changes, install line, schema version)
- Install URL strategy: `install.sh` URL points at `latest` release tarball, not `main`
- GH Actions workflow: on `v*` tag → build sourceball → upload `install.sh` + checksums → trigger Homebrew tap formula bump (via PAT to tap repo)

### 🔍 Sub-spec: `docs/homebrew.md`

Must cover before implementing #12:
- Tap repo layout: `sonpiaz/homebrew-tap` with `Formula/watch-cli.rb`
- Formula content: deps on `yt-dlp`, `ffmpeg`, `jq`; downloads release tarball; installs `bin/*` to brew prefix; runs `--version` smoke as `test do`
- Auto-bump: GitHub Action in the watch-cli release workflow opens a PR in tap repo with new version + sha256

**Exit:** `brew install sonpiaz/tap/watch-cli` and `npx @sonpiaz/watch-cli-mcp` both succeed on a fresh machine.

---

## Phase 5 — Public launch (week 4–6, spread)

Goal: discovery via listings + HN. No big specs; this is content authoring + submission workflow.

| Task | Effort | Notes |
|---|---|---|
| #13 listing PRs (anthropics/skills + awesome-mcp + awesome-claude-code + OpenClaw skills + Hermes optional-skills + MCP registry + yt-dlp wiki) | 4d spread | Each PR ½d. Author per-channel description from `BRANDING.md` |
| #6 HN re-submit content prep | spread across phases 1–4 | 2–3 `examples/` artifacts (output + prompt + final artifact), HN post draft |
| Karma building on HN (≥30 before submit) | parallel | Thoughtful comments on 5–10 unrelated threads |

**Exit:** at least 4 of 7 listings live; HN re-submit posted; karma threshold cleared; comments engaged within 30min response time.

---

# Sub-spec authoring rule

Before writing code for any item marked 🔍:
1. Open the sub-spec file path listed above
2. Write the sub-spec (½–1 page typically)
3. Show it to me (Son) for sign-off
4. Only then implement

Sub-spec docs ship into `docs/` (public, tracked) or `mcp-server/SPEC.md` etc. They become permanent reference for future contributors and for downstream agents (anyone wanting to consume watch-cli's contract).

---

# Updated top recommendation (supersedes both prior ones)

The single highest-leverage thing for watch-cli now is **Phase 0 + Phase 1 together**: lock the pitch around U1 + U2, then ship the foundation contract (schema + exit codes) with sub-specs. That sequence converts watch-cli from "a wrapper with one differentiator" into "an agent-readable infrastructure tool with a documented contract and two unique value props" — within ~3.5 days of focused work.

Everything else in the plan (MCP server, brew tap, listings, HN) becomes 2–3× more effective once those foundations exist, because every downstream artifact references the same locked pitch and the same versioned contract.
