# Prompt library

Five copy-paste prompts that turn `watch` output into an artifact. Pick
the one that matches your goal, paste it above the `watch` block, hand
the whole thing to your agent.

Each prompt assumes you ran `watch <url>` and now have:

```text
VIDEO: <path>
DURATION: <seconds>
FRAMES:
  <path1>
  <path2>
  …
TRANSCRIPT:
  <full text>
```

| File | When to use |
|---|---|
| [implement-from-video.md](implement-from-video.md) | Tutorial / coding walkthrough → working code |
| [extract-architecture.md](extract-architecture.md) | System / architecture talk → interactive diagram |
| [clone-ux.md](clone-ux.md) | UI / motion demo → working React component |
| [paper-to-code.md](paper-to-code.md) | ML paper or research talk → runnable notebook |
| [tutorial-walkthrough.md](tutorial-walkthrough.md) | Long tutorial → AI type-along, step by step |

Mix and match: nothing stops you from running the same `watch` output
through two prompts and comparing artifacts.
