# Cookies for login-walled videos

Most YouTube, TikTok, Reddit, Vimeo, and public X/Twitter posts work
without any cookie setup. Some platforms hide videos behind a login wall:

- **LinkedIn** — most posts require auth
- **X / Twitter** — sensitive-content or blocked-account posts
- **Facebook** — non-public posts and groups
- **Instagram** — almost everything except public reels
- **Patreon, Substack** — paid posts

For these, watch-cli needs to act as a signed-in user.

---

## Option 1 — sign in to a browser (easiest)

**You don't need to copy cookies by hand.** If you're already signed in
to the platform in **any** of these browsers, watch-cli reads the live
session directly. No F12, no DevTools, no extensions:

- Chrome (default first try)
- Firefox
- Safari (macOS)
- Edge
- Brave
- Chromium

No setup needed — just sign in normally and re-run `watch <url>`.

To force a specific browser:

```bash
WATCH_BROWSER=firefox watch <url>
```

### Why this works

`yt-dlp` reads cookies directly from your browser's local profile. The
session never leaves your machine — watch-cli does not upload, store, or
transmit cookies anywhere.

### Browser data not found?

If you've never opened a browser on this machine (e.g. fresh server,
remote SSH session, headless CI), browser auto-detect won't work. Use
Option 2 below.

---

## Option 2 — manual cookie file (servers, CI)

Export cookies as a Netscape-format `cookies.txt` from any signed-in
browser, then pass it explicitly:

```bash
watch <url> --cookies ~/path/to/cookies.txt
```

### Fastest path: one yt-dlp command, no extension

If the source machine has Chrome installed and signed in, export with
one command:

```bash
yt-dlp --cookies-from-browser chrome --cookies ~/yt-cookies.txt \
       --skip-download "https://www.linkedin.com"
```

Then `watch <url> --cookies ~/yt-cookies.txt`. Swap `chrome` for
`firefox`, `safari`, `edge`, `brave`, `chromium`, or `vivaldi` as
needed. Works for any platform yt-dlp supports.

### Recommended exporters (browser extensions)

- **Chrome / Edge / Brave**: [Get cookies.txt LOCALLY](https://chromewebstore.google.com/detail/get-cookiestxt-locally) extension
- **Firefox**: [cookies.txt extension](https://addons.mozilla.org/en-US/firefox/addon/cookies-txt/)
- **Safari**: easier to switch to Chrome/Firefox for this — Safari does
  not export Netscape format natively

### Format check

Your `cookies.txt` should start with:

```
# Netscape HTTP Cookie File
```

Lines look like:

```
.linkedin.com	TRUE	/	TRUE	1735689600	li_at	AQEDAR…
```

If your export looks like JSON, it's the wrong format — re-export with
the extensions above.

---

## Privacy

watch-cli never copies, uploads, or persists your cookies. The cookie
data flows: browser profile → `yt-dlp` (local process) → platform CDN.
Nothing else sees it.

That said: any local process running as your user can also read these
cookies. Homebrew install scripts, npm `postinstall` hooks, AI agents
with shell access, anything you `curl | bash`. This is a property of
how macOS and Linux user accounts work, not specific to watch-cli. For
sensitive accounts, use a dedicated browser profile or a separate
browser entirely.

---

## Still failing?

Common causes when both options fail:

1. **Cookie expired** — sign in again to refresh, then re-run.
2. **Platform requires re-auth** — open the post in your browser first;
   if you see a captcha or "please verify", solve it and try again.
3. **Geo-blocked** — some videos are region-locked. A VPN session in
   the right region restores access.
4. **Truly private** — the post is shared with specific people only.
   No tool can bypass this.

If none apply, file an issue with the URL pattern (no cookies pasted!)
and the platform name at the repo issues page.

---

## Under the hood

Browser auto-detect uses
[`yt-dlp --cookies-from-browser`](https://github.com/yt-dlp/yt-dlp),
which reads the browser's encrypted SQLite cookie store and decrypts
via the OS keychain. Same primitive that any "give your CLI a session"
tool uses: Python's `browser_cookie3`, Node's `chrome-cookies-secure`,
Go's `kooky`.

No magic. The decomposition story from the README applies here too: a
tool already exists for this primitive; watch-cli just composes it.
