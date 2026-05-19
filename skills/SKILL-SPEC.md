# SKILL.md specification

This document is the contract for the portable `SKILL.md` that watch-cli
ships. The actual `SKILL.md` file is authored against this spec during
the Phase 2 implementation; this document is the source of truth for
its shape.

Cross-references:

- Output contract the skill body references: [`../docs/output-schema.md`](../docs/output-schema.md)
- Exit codes the skill body references: [`../docs/exit-codes.md`](../docs/exit-codes.md)
- Pitch and tone rules the skill body must follow: [`../BRANDING.md`](../BRANDING.md)

---

## Purpose

A single `SKILL.md` that is valid in Claude Code, OpenClaw, and
hermes-agent without modification — one file, three platforms. All
three consume the same Anthropic Agent Skills grammar: YAML frontmatter
between `---` markers at the top, prose body underneath. The platform
differences live in optional `metadata.*` blocks that are harmless on
platforms that ignore them. Widening the frontmatter to OpenClaw's
shape unlocks OpenClaw and hermes-agent with zero cost on Claude Code.

---

## Where the canonical file lives

The canonical file lives at the repository root as `SKILL.md`. A
symlink at `skills/watch-cli/SKILL.md` points to the root file so
existing instructions (the README references `skills/watch-cli/` for
the Claude Code drop-in copy) keep working.

Per-platform expectations:

| Platform | Path the platform reads |
|---|---|
| Claude Code | `~/.claude/skills/watch-cli/SKILL.md` (user copies or symlinks `skills/watch-cli/` from the repo into `~/.claude/skills/`). |
| OpenClaw | `skills/watch-cli/SKILL.md` inside the user's OpenClaw project tree, or auto-detected from any compatible bundle that ships a `SKILL.md` with the OpenClaw `metadata.openclaw.*` block. |
| hermes-agent | `optional-skills/<domain>/watch-cli/SKILL.md` inside the hermes-agent install. Default domain is `research`. |
| Bundled install | `install.sh --with-skill` copies the canonical file into `~/.claude/skills/watch-cli/` on the local machine (Phase 2 item #10 in `.omc/plans/defend-the-niche-4-6-weeks.md`). |

The repo always ships the canonical file. Per-platform installation is
a copy or symlink step the user (or `install.sh --with-skill`) performs;
no per-platform forks of the markdown are maintained.

---

## Required frontmatter fields

YAML between two `---` markers at the top of `SKILL.md`. The keys below
are required for the file to be valid in all three target platforms.

| Key | Type | Value rule |
|---|---|---|
| `name` | string | Always `watch-cli`. Lowercase, hyphenated. Matches the project name from `BRANDING.md`. |
| `description` | string | The locked pitch from `BRANDING.md` verbatim, or a tight variant that keeps the *video → concrete artifact* mapping. Single line. ≤ 350 characters so it renders cleanly in agent UIs. |
| `homepage` | string | `https://github.com/sonpiaz/watch-cli`. |

---

## Optional frontmatter fields

These keys are read by OpenClaw and ignored by Claude Code and
hermes-agent. They are safe to include unconditionally.

```yaml
metadata:
  openclaw:
    emoji: ""
    requires:
      bins:
        - watch
    install:
      - id: curl-install
        kind: shell
        command: "curl -fsSL https://raw.githubusercontent.com/sonpiaz/watch-cli/main/install.sh | bash"
        bins:
          - watch
        label: "Install watch-cli (curl)"
```

Field-by-field rule:

| Key | Rule |
|---|---|
| `metadata.openclaw.emoji` | Empty string. `BRANDING.md` bans emoji in docs; OpenClaw renders the field but tolerates empty. Do not invent one. |
| `metadata.openclaw.requires.bins` | Array of strings. List `watch` here so OpenClaw shows an install prompt when `watch` is not on the user's `PATH`. Do not list `yt-dlp`, `ffmpeg`, `jq` — `install.sh` is responsible for surfacing those. |
| `metadata.openclaw.install` | Array. One entry describing the curl one-liner. `id` is a stable token; `kind: shell` tells OpenClaw to run `command` in a shell; `bins` lists what the install provides; `label` is the human-readable button text. |

The `command` field must contain the exact curl install line currently
in `README.md` § *Install*. If `README.md` updates the install URL, this
field updates with it.

---

## Body content rules

Everything after the second `---` is prose markdown. The body has the
following sections in this order.

### 1. Lead paragraph

The first paragraph after the frontmatter must contain the locked pitch
from `BRANDING.md` (or a tight variant per the rule above). Do not
move it later. This is the line agent UIs surface in skill discovery.

### 2. When to invoke

Three to four concrete user signals that should make the agent reach
for `watch`. Each signal is a single bullet, written as the user-facing
verb plus the URL pattern. Examples (illustrative, not the final
wording):

- The user pastes a video URL with no verb.
- The user asks to "summarize", "explain", or "walk me through" content
  at a video URL.
- The user asks to "implement", "clone", "build", or "replicate" what
  is in a video.
- The user asks to "extract architecture from" or "turn this paper talk
  into code" at a video URL.

### 3. What you get back

Plain prose that mirrors the README *What you can build* table. Cover
all five mappings: coding walkthrough → working project files; system
talk → interactive architecture diagram; UI demo → working React
component; paper / research talk → runnable notebook; long tutorial →
step-by-step cheat sheet. No tables in the body — prose is more robust
to skill-host renderers.

### 4. Parse rules

Document the v1 output contract by reference, not by duplicating it.

- Prefer `watch <url> --format json` and parse the single-line JSON
  object against the field reference in [`../docs/output-schema.md`](../docs/output-schema.md).
- Text-mode parse rules are a fallback for hosts that capture stdout as
  a free-text block (Claude Code does this today). Treat the leading
  `WATCH_OUTPUT_VERSION: 1` line as the version signal; everything
  below is labeled blocks per the same doc.
- Exit-code behavior — including the partial-success rule (exit 4 with
  frames populated and transcript null) — is documented in
  [`../docs/exit-codes.md`](../docs/exit-codes.md). Reference it; do not
  restate it.

### 5. Invocation example

Exactly one invocation line, no code blocks beyond that one line:

```bash
watch <url> [frame-count]
```

Do not include curl install snippets, jq pipelines, multi-step bash
recipes, or Python wrappers in the skill body. The README and the
docs in `docs/` are the place for those.

---

## Anti-patterns

The skill is rejected (or starts to drift) if it does any of the
following. This list comes directly from OpenClaw manifest review
guidance plus the watch-cli `BRANDING.md` tone rules.

- **Do not put runtime entrypoints in the frontmatter.** OpenClaw is
  explicit: the skill manifest declares dependencies, not runtime
  behavior. Let the agent shell out to `watch` based on the body prose
  and the `requires.bins` declaration.
- **Do not duplicate README content.** Link to the README and to the
  two source-of-truth docs in `docs/`. A long skill body ages faster
  than a short one and drifts from the README.
- **Do not localize.** English only. Skill hosts ship globally; the
  contract is one language.
- **Do not include API keys, key paths, or environment-variable values
  in the body.** Reference `README.md` § *Setup* for `KYMA_API_KEY`
  guidance; do not surface the variable name in a way an agent might
  paste it into chat.
- **Do not include emoji.** `BRANDING.md` bans them. The
  `metadata.openclaw.emoji` field stays empty.
- **Do not embed step-by-step prompt templates.** The five prompts in
  `prompts/` are linked from the README; the skill body says "pick a
  prompt from `prompts/`" and stops there.

---

## Validation

Before the implementer commits the authored `SKILL.md`, run these
manual checks. They are not automated in Phase 2; they may become a CI
check in a later phase.

1. **Frontmatter parses as YAML.** Pipe the frontmatter block through a
   YAML parser (`python3 -c 'import sys, yaml; yaml.safe_load(sys.stdin)'`
   or `yq .`) and confirm no errors.
2. **Locked pitch matches `BRANDING.md`.** The `description` field is
   either character-for-character identical to the locked pitch in
   `BRANDING.md`, or a tight variant that keeps the *video → concrete
   artifact* mapping. The reviewer judges variants by the rule in
   `BRANDING.md` § *Locked one-line pitch*.
3. **Description length.** `description` is ≤ 350 characters so it
   renders in skill-host list UIs without truncation.
4. **Required fields present.** `name`, `description`, `homepage` all
   present and non-empty.
5. **Symlink works.** `skills/watch-cli/SKILL.md` exists and resolves
   to the root `SKILL.md`. From the repo root: `readlink skills/watch-cli/SKILL.md`
   returns `../../SKILL.md` (or equivalent).
6. **No emoji in the file.** `grep -P '[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]' SKILL.md`
   returns empty.

Length budget for the authored `SKILL.md`: the body (everything after
the frontmatter) should sit between 80 and 200 lines. Anything longer
duplicates the README; anything shorter usually omits the parse rules
or the "when to invoke" signals.
