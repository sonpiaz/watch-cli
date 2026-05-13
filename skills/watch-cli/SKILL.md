---
name: watch-cli
description: Watch any social video (YouTube, X, LinkedIn, TikTok, Vimeo, Reddit, Facebook) by handing the URL to the local `watch` command. Skill downloads the video, extracts evenly-spaced frames, transcribes the audio, and bundles them as context the agent reasons over. Use when the user shares a video URL and wants you to watch, analyze, summarize, implement, clone, extract architecture from, or build something from it. Triggers on phrases like "watch this video", "analyze this URL", "implement this", "clone this UI", "build what's in this video", "explain this talk", "extract architecture from this video", "turn this paper into code", or when a URL from youtube.com / x.com / twitter.com / linkedin.com / tiktok.com / vimeo.com / reddit.com / facebook.com appears alongside a verb.
---

# watch-cli skill

Give the agent eyes and ears for any social video.

## When to invoke

Whenever the user shares a video URL and asks you to do something based
on what's in the video. Examples:

- "Watch this and explain how it works: <url>"
- "Implement what's in this video: <url>"
- "Extract the architecture from this talk: <url>"
- "Clone this UI: <url>"
- "Turn this paper talk into a notebook: <url>"
- "Summarize this 1h podcast: <url>"

If the user just pastes a video URL with no verb, ask one clarifying
question: "Want me to summarize, implement, clone the UI, extract the
architecture, or something else?" Then proceed.

## Workflow

### 1. Confirm watch-cli is installed

Run `which watch`. If not found, surface this install command to the
user and stop:

```bash
curl -fsSL https://raw.githubusercontent.com/sonpiaz/watch-cli/main/install.sh | bash
```

### 2. Pick a frame count from the video length and density

| Video type | `frame-count` |
|---|---|
| Short clip / tweet (<2 min) | 8 (default) |
| Standard tutorial (5–20 min) | 12 |
| Long talk / lecture (20–60 min) | 20 |
| Conference / multi-hour (>1 hr) | 32 |
| Fast-cut or dense UI demo | double the recommendation for that length |

### 3. Run watch

```bash
watch <url> <frame-count>
```

For login-walled posts (LinkedIn, private X, Facebook) watch-cli
auto-detects browser cookies. Surface any cookie error to the user
before retrying.

### 4. Parse the output block

```text
VIDEO: /tmp/dl-video/<hash>.mp4
DURATION: <seconds>
FRAMES:
  /tmp/frames_<hash>/frame_01.jpg
  /tmp/frames_<hash>/frame_02.jpg
  …
TRANSCRIPT:
  <full audio transcript>
```

Read each `FRAMES` path with the Read tool (Claude understands JPG).
Read the `TRANSCRIPT` inline as the audio. Together they are enough
for you to "watch" the video.

### 5. Pick the task-specific prompt

Match the user's intent to one of the inlined prompts below. If the
user's intent is ambiguous, ask one short clarifying question. If they
say "just watch it" or "tell me what's in it", default to a 5-line
plain-English summary.

| User intent | Inlined prompt to apply |
|---|---|
| Build / implement / replicate | [Implement from video](#prompt-implement-from-video) |
| Extract architecture / system map | [Extract architecture](#prompt-extract-architecture) |
| Clone UI / replicate interaction | [Clone UX](#prompt-clone-ux) |
| Paper / research → code | [Paper to code](#prompt-paper-to-code) |
| Tutorial → step-by-step cheat sheet | [Tutorial walkthrough](#prompt-tutorial-walkthrough) |
| Plain summary / explanation | Just summarize, no prompt needed |

### 6. Produce the artifact

Follow the chosen prompt's output contract. Hand the user the artifact,
not a transcript of your reasoning.

## Cost awareness

- 5 minutes of video: ~$0.003 transcribe
- 1 hour of video: ~$0.04 transcribe
- 2 hours of video: ~$0.08 transcribe

Free Kyma credit at signup covers roughly 25 hours of audio. For videos
longer than 1 hour, mention the rough cost before running. Skip the
disclaimer for short videos.

## Common failures

| Error | Cause | Fix |
|---|---|---|
| `cookies not found` (LinkedIn / X / FB) | User not signed in to that platform in default browser | Sign in, retry. Or pass `--cookies <file>` with a manual export |
| `25MB cap exceeded` | Video too long for one transcribe call | Split via `ffmpeg -ss <start> -t <duration>` and watch each chunk |
| `403 region locked` | yt-dlp can't fetch from this region | Ask the user for an alternate URL or a local file |
| Empty `TRANSCRIPT` | Silent video | Increase frame count, also run `audio-q "describe the sound design"` |

---

## Prompt: Implement from video

Apply when the user wants a runnable project that replicates what was
built on screen.

```
You are a senior engineer pair-programming with the user. They have
just handed you a video they want to replicate.

Below is the video's evenly-spaced frames (read each FRAMES path as an
image) and the full audio transcript. Treat the frames as ground truth
for visible code, file names, and UI. Treat the transcript as the
narrator's intent and rationale.

Your job:

1. Reconstruct the project structure visible on screen. Use the exact
   filenames, folder layout, dependencies, and CLI commands that appear
   in the frames. If something is ambiguous, prefer what the narrator
   says over what you infer.
2. Produce the final state of every file the video ends with, not the
   intermediate edits. The user wants a working clone, not a replay.
3. Write a short README explaining what this project does, how to run
   it locally, what was clipped in the video and why your reconstruction
   filled the gap.
4. List anything you could not confidently recover (a config that
   scrolled off-screen, a redacted secret). Mark those as "TODO: confirm
   from source video at <timestamp>".

Do not hallucinate libraries. If you cannot see or hear a dependency,
use the most idiomatic choice for the stack and flag it.
```

---

## Prompt: Extract architecture

Apply when the user wants a self-contained interactive diagram of a
system someone is describing.

```
You are a systems architect. The user has handed you a video where
someone explains how a product is built. Your job is to produce a
single self-contained HTML file that maps the architecture for someone
who never watched the video.

Read the FRAMES as ground truth for any diagrams, terminals, or UI
shown on screen. Read the TRANSCRIPT for the actor names, service
boundaries, and step-by-step flows the speaker describes.

Output: one HTML file, no build step, Tailwind via CDN. Three columns:

1. Actors (people / systems initiating action)
2. Surfaces (the things actors touch: dashboards, SDKs, public URLs)
3. APIs / data stores / external services

On the right, a clickable list of named flows. When a flow is selected,
highlight the actors, surfaces, and endpoints it passes through, and
show a numbered Steps panel below it with who acts, what they call,
the payload shape, and the data that gets written.

Color rules: actors blue, surfaces purple, APIs amber, data stores
green, external services gray. Dim when not part of the selected flow.

If the speaker mentions an endpoint path or table name explicitly,
quote it verbatim. If you have to infer one, mark it with a tilde
prefix (~assumed-path/foo).

Do not invent flows the speaker did not describe. Three real flows
beats ten fabricated ones.
```

---

## Prompt: Clone UX

Apply when the user wants a working React component that captures the
feel of a UI shown on screen.

```
You are a senior frontend engineer with deep taste. The user has
handed you a video showing a UI they want to clone, not pixel-for-pixel
but feel-for-feel.

Read the FRAMES as ground truth for layout, spacing, color, typography
hierarchy, and motion direction. Read the TRANSCRIPT only if the
designer narrates intent.

Output: a single React component file (TypeScript, Tailwind,
framer-motion allowed) that captures the interaction. Match the cadence
and easing you see on screen, not just the end state.

Rules:

1. Identify the single moment that makes this UI special and protect
   it. Most demos hinge on one interaction; the rest is wrapping.
2. Use real typography. If the video uses an obvious system or open
   font (Inter, IBM Plex, system-ui, serif headings), match it. If you
   cannot tell, default to Inter and say so.
3. State management stays local. No Redux, no context, no router.
4. Output one paste-ready .tsx file plus a 5-line "how to run" note.
   If the component depends on a 3rd-party lib, list the install
   commands at the top of the file as a comment.

Anti-patterns:
- Do not pad the file with placeholder content the video did not show.
- Do not ship a Storybook story unless asked.
- Do not rewrite the user's design system; use Tailwind utility classes.
```

---

## Prompt: Paper to code

Apply when the user wants a runnable notebook reproducing a method
explained in a talk.

```
You are a research engineer reproducing a paper from a talk. The user
has handed you a video where the author or a presenter explains a
method.

Read the FRAMES as ground truth for math, architecture diagrams,
pseudocode, and result tables. Read the TRANSCRIPT for the intuition,
assumptions, and any clarifications the speaker adds beyond the slides.

Output: one Jupyter notebook (.ipynb as JSON) implementing the core
method on a toy dataset that runs end-to-end on a free Colab T4.

Cells, in order:

1. Markdown — paper title, talk URL, one-paragraph plain-English summary.
2. Imports — only what you use.
3. The method itself — one minimal implementation, no premature abstraction.
4. Toy dataset — synthetic or a small public set. Justify the choice.
5. Training / inference loop — short and observable. Print loss / metric
   every N steps.
6. Results — a table or figure comparing your run to what the speaker
   claims at the end of the talk.
7. Markdown — what you simplified vs. the paper, where the speaker was
   vague, what would be needed to reproduce the headline number.

Rules:
- Prefer torch over jax unless the speaker explicitly uses jax.
- No proprietary datasets. Use what a stranger can run.
- Cite the paper formally at the top with a bibtex block.
- If the talk skipped a derivation, do not fabricate one. Note it.
```

---

## Prompt: Tutorial walkthrough

Apply when the user has a long tutorial they want as a cheat sheet they
can follow on their own machine.

```
You are a patient teacher. The user has handed you a long tutorial
video and they want the cheat sheet version they can follow on their
own machine without rewinding.

Read the FRAMES for commands, file content, and UI clicks. Read the
TRANSCRIPT for the reasoning and any "actually wait, do this instead"
corrections the slides don't show.

Output: one markdown walkthrough with these sections:

1. **What you'll build** — 2 sentences, ground truth from the end state
   in the last 30 seconds of the video.
2. **Prerequisites** — exact versions of tools / SDKs / accounts. If
   the video assumes them silently, surface them anyway.
3. **Steps** — numbered. Each step has:
   - A 1-line goal
   - Exact copy-pasteable commands or code
   - Any "if you see X, do Y" branches the speaker mentions
   - A line citing roughly where in the video this step happens
     (e.g. "≈4:30 in the video")
4. **Verification** — how to confirm each major step worked before
   moving to the next.
5. **Troubleshooting** — only items the speaker actually discussed. No
   generic Stack Overflow boilerplate.
6. **What was clipped** — note any moment where the speaker cut away,
   and what reasonable default to fill in.

Tone: imperative, second person. "Run `npm install`", not "You should
probably run npm install".
```
