# Platform support

`watch-cli` works on any platform `yt-dlp` understands. The table below
covers the ones we have explicitly tested and the cookie tier they need.

| Platform | No cookie | Auto browser | Manual `--cookies` |
|---|---|---|---|
| **YouTube** (public) | ✅ | — | — |
| **YouTube** (members-only) | ❌ | ✅ | ✅ |
| **TikTok** (public) | ✅ | — | — |
| **Reddit** (public posts) | ✅ | — | — |
| **Vimeo** (public) | ✅ | — | — |
| **X / Twitter** (public posts) | ✅ | — | — |
| **X / Twitter** (sensitive / blocked accounts) | ❌ | ✅ | ✅ |
| **LinkedIn** (most posts) | ❌ | ✅ | ✅ |
| **Facebook** (public pages) | ✅ | — | — |
| **Facebook** (groups, private posts) | ❌ | ✅ | ✅ |
| **Instagram** (public reels) | ⚠️ inconsistent | ✅ | ✅ |
| **Patreon** (paid) | ❌ | ✅ | ✅ |

Legend: ✅ works · ❌ blocked · ⚠️ partial · — not needed

## Tested versions

This matrix was last verified against:

- `yt-dlp` 2024.12.x (any recent build is fine)
- macOS 14, Linux Debian 12

If a platform fails on your machine, first run:

```bash
yt-dlp -U   # update yt-dlp to latest
```

Most platform breakages are fixed by a `yt-dlp` update — the project
ships fast (often weekly) for new platform changes.

## Adding a new platform

There's nothing to add. Any URL `yt-dlp` supports works in `watch-cli`
out of the box. The full list of 1,800+ supported sites lives at
[yt-dlp/supportedsites.md](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md).

## Breakage and recovery

`watch-cli` is a thin wrapper around `yt-dlp`. If a platform stops
working — a YouTube URL that downloaded yesterday returns 403 today,
or a TikTok URL hangs forever — the breakage is almost always a
`yt-dlp` extractor that the upstream platform has changed under.

Recovery is two steps:

1. **`yt-dlp -U`** — pulls the latest extractor patch. The project
   ships fast (often weekly) for platform changes. Most reported
   breakages are fixed within 24–72 hours of someone filing the issue.
2. **Check the issue tracker.** If `-U` didn't help, the breakage may
   be in flight: search
   [github.com/yt-dlp/yt-dlp/issues](https://github.com/yt-dlp/yt-dlp/issues)
   for the platform tag (`[youtube]`, `[tiktok]`, `[linkedin]`, …).
   An existing open issue means the fix is being worked; subscribe and
   wait. No issue means file one.

`watch-cli` runs a lightweight upstream probe before each download (a
`yt-dlp --simulate` against a known-stable canary URL per platform,
result cached 24h). On probe failure it emits a stderr warning
`tag=platform-probe-fail` and proceeds anyway — a stale canary URL is
also a possible cause, and the actual target URL may still work.
