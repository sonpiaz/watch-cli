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

## License

MIT. © 2026 Son Piaz.
