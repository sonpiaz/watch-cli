# Branding & messaging

Single source of truth for how watch-cli describes itself. Anyone writing user-facing copy — README, `SKILL.md`, MCP server descriptions, listing PRs, social posts — should read this first.

## Mission

watch-cli is the thin orchestrator that hands AI agents the raw materials to reason over any social video.

## Locked one-line pitch

> **Watch any social video → get an architecture diagram, working component, runnable notebook, or step-by-step cheat sheet — automatically.**

Use this line (or a tight variant that keeps the *video → concrete artifact* mapping) as the lead in any user-facing description. Don't dilute with adjectives. Don't move the artifacts list earlier than the video input.

## Two unique features

**U1 — Agent-shaped raw-materials output.** `VIDEO + FRAMES + TRANSCRIPT` in a single structured block (text today, JSON v1 next), designed for an LLM to read frames as images and transcript as text. No other CLI in this space composes the inputs in this shape.

**U2 — Prompt library that maps `watch` output → concrete deliverables.** Five prompts in `prompts/` convert raw materials into working artifacts: project files, architecture diagram, React component, runnable notebook, step-by-step cheat sheet.

Every user-facing artifact should reinforce U1, U2, or both. If it does neither, it's the wrong copy.

## Tone rules

- **Concrete over abstract.** *"Working React component"* beats *"powerful UI generation"*. Lead with outcomes the reader can touch.
- **Verb–noun phrases.** *"Watch a video, get a diagram"* beats *"AI-powered video understanding for next-gen workflows"*.
- **No hype words.** Banned: *revolutionary, powerful, magical, seamless, cutting-edge, AI-powered (about the tool itself), unleash, supercharge*.
- **Honest cost framing.** Always pay-per-use. Never *"free"* without disclosing the credit ceiling.
- **No emoji.** Except where they appear naturally in code or status output.
- **No screenshots that age fast.** Show CLI output blocks (text) instead.

## Pitch variants — good vs bad

Good:

- *"Watch any social video, get a working React component back."*
- *"Hand a YouTube link to your agent. Get an architecture diagram of your own product back."*
- *"A composable CLI that gives AI agents eyes and ears for any social video."*

Bad:

- *"The most powerful AI video understanding tool."* — hype + abstract
- *"Revolutionary multimodal pipeline."* — banned words
- *"watch-cli leverages cutting-edge AI to unlock video insights."* — filler verbs
- *"Built on Kyma, the AI gateway."* — leads with our own infra; reader doesn't care

## Where the locked pitch must appear

Audit each time the README ships, the SKILL.md changes, or a new package goes out:

- [ ] README first paragraph (above the install fold)
- [ ] `SKILL.md` `description` frontmatter field
- [ ] MCP server tool `description` field (once shipped)
- [ ] npm package `description` field (once published)
- [ ] Homebrew formula `desc` line (once shipped)
- [ ] GitHub repo description (the field next to the repo name)
- [ ] First line of any listing-submission PR body
- [ ] First sentence of any blog or social post about the tool

## Naming

- **`watch-cli`** — the project. Always lowercase, hyphenated.
- **`watch`** — the primary command. Lowercase.
- Never *"WatchCLI"*, *"WatchCli"*, or *"Watch-CLI"* in prose. GitHub auto-capitalizes the title bar; that's cosmetic and out of our control, but never mirror it in writing.
