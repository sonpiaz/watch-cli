# watch-cli

Give your AI agent eyes and ears for any social video.

```bash
watch https://twitter.com/anyone/status/12345
```

You get back: a video file, evenly-spaced frames as JPGs, and the full
audio transcript. Your agent reads them and "watches" the video — works
on YouTube, X, LinkedIn, TikTok, Reddit, Vimeo, and Facebook. Login-walled
posts (LinkedIn, X, FB) fall back to your browser cookies automatically.

---

## Why this exists

Large language models can't watch video natively — they read text and
look at still images. Modern multimodal APIs *will* analyze a full video
for you, but they're slow and expensive. The trick: **you almost never
need them**.

A video is just frames + audio. Each piece has a fast, near-free tool
already:

- `yt-dlp` downloads from any social platform
- `ffmpeg` extracts evenly-spaced frames
- An ASR model transcribes the audio
- A multimodal LLM hears tone, music, SFX, language, mood

Compose them and your agent has video understanding — without burning a
multimodal LLM on every frame.

---

## What it looks like

```text
$ watch https://www.linkedin.com/posts/some-talk_activity-12345

VIDEO: /tmp/dl-video/abc123.mp4
DURATION: 218
FRAMES:
  /tmp/frames_abc123/frame_01.jpg
  /tmp/frames_abc123/frame_02.jpg
  …
TRANSCRIPT:
  Today I want to talk about how decomposition unlocks 10× cost reduction in
  multimodal pipelines …
```

Your agent reads the JPGs and the transcript. That's the whole watch.

---

## Benchmark

After noticing how much we burned on multimodal calls, we measured:

| Approach | Cost / 1-hour video | Time |
|---|---|---|
| Multimodal LLM on full video | ~$5 | 30–60s |
| watch-cli (Kyma audio) | < $0.10 | ~10–15s |
| **Ratio** | **~50× cheaper** | **~5× faster** |

The savings compound when an agent watches dozens of videos in a session.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/sonpiaz/watch-cli/main/install.sh | bash
```

Or from a clone:

```bash
git clone https://github.com/sonpiaz/watch-cli ~/.watch-cli
cd ~/.watch-cli && ./install.sh
```

The installer checks for `yt-dlp`, `ffmpeg`, `jq`, `curl`, `python3` and
symlinks the commands into `~/.local/bin`. On macOS:

```bash
brew install yt-dlp ffmpeg jq
```

On Debian/Ubuntu:

```bash
sudo apt install yt-dlp ffmpeg jq python3 curl
```

---

## Setup

```bash
export KYMA_API_KEY=kyma-xxxxxxxx
```

Get a Kyma key at [kymaapi.com](https://kymaapi.com) — 60 seconds, no card.

Prefer bring-your-own-keys? Comment in `GROQ_API_KEY` and `GOOGLE_AI_KEY`
in `.env.example` and watch-cli falls back to direct provider calls.

---

## Why Kyma

watch-cli uses Kyma as its AI backend. A few things you get for free:

![models](https://img.shields.io/endpoint?url=https://api.kymaapi.com/api/badge/models.json)
![creators](https://img.shields.io/endpoint?url=https://api.kymaapi.com/api/badge/creators.json)
![free credit](https://img.shields.io/endpoint?url=https://api.kymaapi.com/api/badge/free-credit.json)

- **One key, every model in this CLI.** `transcribe` today is Whisper v3
  turbo. When Kyma swaps in Voxtral or Whisper v4, your watch-cli scripts
  keep working with zero changes — the alias stays.
- **Per-call cost in the response.** Every transcribe gives you a real
  number, not an end-of-month dashboard surprise.
- **Auto-fallback across providers.** If the underlying audio provider is
  throttling or down, Kyma routes through another. Your script never sees
  the outage.
- **Free credit at signup.** About an hour of audio. Enough to know if
  you like it before you spend a cent.

The badges above pull live from `api.kymaapi.com/api/stats`, so the model
count and free-credit number stay current without a watch-cli release.

---

## Commands

```text
watch <url> [frame-count] [--cookies <file>]
  Orchestrator. Downloads, extracts frames, transcribes — one block out.

dl-video <url> [out-dir] [--cookies <file>]
  Just download the video. Returns the local mp4 path.

extract-frames <video> [count] [out-dir]
  Pull N evenly-spaced JPG frames. Default 8.

transcribe <audio-or-video> [language]
  Speech-to-text. Auto-extracts audio from video first.

audio-q <audio-or-video> "<question>"
  Audio scene Q&A — tone, music, SFX, language, emotion.
  Beyond pure transcription.

models [--all]
  List audio models available on Kyma (live, no hardcoded list).
  --all to see every Kyma SKU (text + image + video + audio).
```

### How `transcribe` and `audio-q` stay current

The scripts call Kyma using the `transcribe` and `audio-understand` aliases,
not raw model IDs. When Kyma swaps the underlying model (Whisper v4,
Voxtral, a faster ASR), watch-cli keeps working without an update — the
alias points to whichever model is current. Run `watch-cli models` any time
to see what's behind the alias today.

---

## Login-walled videos

Most YouTube / TikTok / Reddit / Vimeo / public X work without setup.
LinkedIn, private X posts, and Facebook need a session.

watch-cli auto-detects cookies from any signed-in browser
(Chrome → Firefox → Safari → Edge → Brave → Chromium). Just sign in
normally and re-run.

For servers / CI without browsers, pass a manual cookies file:

```bash
watch <url> --cookies ~/cookies.txt
```

Full setup walkthrough: [docs/cookies.md](docs/cookies.md).

---

## Use with Claude Code (or any agent)

```text
You have access to a `watch` command that takes a URL and returns
a video, 8 frames, and the transcript. Read the frames as images and
the transcript as text — that's enough to "watch" any social video.
```

The output block is structured so an agent can parse it without help:
`VIDEO:` line, `FRAMES:` block (one path per line), `TRANSCRIPT:` block.

---

## Prompt library

Beyond the generic prompt above, five copy-paste prompts in
[`prompts/`](prompts/) turn `watch` output into a specific artifact:

| Goal | File |
|---|---|
| Coding walkthrough → working project | [`implement-from-video.md`](prompts/implement-from-video.md) |
| System talk → interactive architecture diagram | [`extract-architecture.md`](prompts/extract-architecture.md) |
| UI / motion demo → working React component | [`clone-ux.md`](prompts/clone-ux.md) |
| Paper / research talk → runnable notebook | [`paper-to-code.md`](prompts/paper-to-code.md) |
| Long tutorial → step-by-step cheat sheet | [`tutorial-walkthrough.md`](prompts/tutorial-walkthrough.md) |

Paste the chosen prompt above the `watch` output, hand the whole thing
to your agent.

### Use as a Claude Code skill

Drop [`skills/watch-cli/`](skills/watch-cli/) into your
`~/.claude/skills/` folder and the agent will pick up `/watch <url>`
as a first-class command, including the prompt library above.

```bash
mkdir -p ~/.claude/skills
cp -r skills/watch-cli ~/.claude/skills/
```

---

## How it works

```text
URL ──▶ yt-dlp ──▶ video.mp4 ──┬──▶ ffmpeg ──▶ frames/*.jpg
                                │
                                └──▶ ffmpeg ──▶ audio.mp3 ──┬──▶ Kyma /v1/audio/transcriptions
                                                            │     (Whisper Large v3 Turbo, 228× realtime)
                                                            │
                                                            └──▶ Kyma /v1/audio/understand
                                                                  (Gemini 3 Flash audio — tone/music/SFX)
```

Each step is a primitive. None of them needs a vision LLM.

---

## Show what you build

Built something cool from a video? Drop it in
[Discussions](https://github.com/sonpiaz/watch-cli/discussions) under
**Show and tell**. Post the source URL, the prompt you used, and your
artifact. Curated highlights make it back into the README.

---

## Limitations and cost

Watch-cli is fast and cheap because it composes primitives instead of
calling a video LLM. The tradeoffs are honest.

### Cost per video

Transcription is the only paid step. Frame extraction is local ffmpeg,
free.

| Video length | Transcribe cost |
|---|---|
| 5 minutes (tweet, short demo) | ~$0.003 |
| 1 hour (LinkedIn talk, podcast) | ~$0.04 |
| 2 hours (conference talk) | ~$0.08 |

Free credit at Kyma signup covers roughly 25 hours of audio. Bring your
own Groq key and the price stays the same (Whisper v3 turbo, $0.04/hour
both ways).

### What works well

- Talking-head content: tutorials, conference talks, lectures, walkthroughs
- Architecture and system diagrams shown for at least 3 seconds
- Code that stays on screen long enough to read
- ~95 languages (anything Whisper v3 turbo supports)

### What works poorly

- Music videos, action movies, fast-cut content. Eight evenly-spaced
  frames miss key moments. Bump count: `watch <url> 24`.
- Editor sessions that scroll fast through code. Same fix.
- Audio with heavy background music and overlapping speakers. Transcript
  quality drops. Use `audio-q` for a scene description instead.
- Videos longer than ~2 hours. The transcribe provider has a 25MB audio
  cap. Watch-cli auto-downsamples but a 3-hour talk may still exceed.
  Workaround: split via `ffmpeg -ss` before piping.

### What does not work yet

- Region-locked videos (some YouTube, TikTok). yt-dlp returns an error;
  watch-cli surfaces it.
- Live streams. Download finishes only after the stream ends.
- Silent screencasts. Transcribe returns empty. Increase frame count and
  use `audio-q` for any sound design instead.

### Frame count guidance

| Video type | Recommended `frame-count` |
|---|---|
| Short tweet / clip (<2 min) | 4 to 8 (default) |
| Standard tutorial / talk (5–20 min) | 8 to 16 |
| Long talk / lecture (20–60 min) | 16 to 24 |
| Conference talk / multi-hour (>1 hr) | 24 to 32 |
| Fast-cut or dense UI demo | Double the recommendation for that length |

---

## License

MIT. © 2026 Son Piaz.
