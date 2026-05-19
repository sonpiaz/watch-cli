# Homebrew tap

This document is the contract for the watch-cli Homebrew tap repo,
the formula content, and the auto-bump workflow that updates the
formula on every watch-cli release.

---

## Purpose

Mac developers — watch-cli's primary audience — reach for `brew
install` first. The tool's dependencies (`yt-dlp`, `ffmpeg`, `jq`)
are already on Homebrew. Asking the same user to curl an arbitrary
`install.sh` for the wrapper is friction. A personal tap
(`sonpiaz/homebrew-tap`) is roughly 10× less work than upstreaming
to homebrew-core: no review queue, no popularity threshold, no audit
cycle, full control of release cadence. Homebrew-core submission is
explicitly out of scope for Phase 4.

---

## Tap repo

Name: **`sonpiaz/homebrew-tap`**. New public repo, implementer
creates as part of Phase 4:

```bash
gh repo create sonpiaz/homebrew-tap \
  --public \
  --description "Homebrew formulas for Son Piaz projects"
```

`brew tap sonpiaz/tap` resolves to `github.com/sonpiaz/homebrew-tap`
by Homebrew convention. The `homebrew-` prefix is mandatory in the
repo name and must not appear in the user-facing tap name.

Layout:

```
sonpiaz/homebrew-tap/
├── Formula/
│   └── watch-cli.rb
└── README.md
```

`Formula/` is required by Homebrew. Future formulas sit alongside
`watch-cli.rb`. Top-level `README.md` is a 2–3 paragraph blurb
pointing at each project's homepage — not a place to duplicate
watch-cli docs.

---

## Formula spec

File: `Formula/watch-cli.rb`. Ruby class extending `Formula`. The
sketch at the end of this section is what the implementer turns into
the real formula.

### Metadata

| Field | Value |
|---|---|
| `desc` | `"Turn any social video into an architecture diagram or working component"` (71 chars). Homebrew enforces `desc` under 80 chars via `brew style`. Tightened variant of the locked pitch in [`BRANDING.md`](../BRANDING.md) — preserves the U2 "video → concrete artifact" mapping (the must-keep half per BRANDING) while fitting the audit. |
| `homepage` | `"https://github.com/sonpiaz/watch-cli"` |
| `url` | `"https://github.com/sonpiaz/watch-cli/releases/download/v#{version}/watch-cli.tar.gz"` — `v#{version}` interpolation lets the auto-bump edit only `version` and `sha256`. |
| `sha256` | `"<filled by release automation>"` — 64-hex tarball SHA, set by the bump PR. |
| `version` | `"0.3.0"` — first tap-tracked version, updated by the auto-bump PR. |
| `license` | `"MIT"` |

### Dependencies

```ruby
depends_on "yt-dlp"
depends_on "ffmpeg"
depends_on "jq"
```

Same deps as the curl installer minus `curl` and `python3` (Homebrew
assumes those on macOS). `whisper-cpp` is **not** a default
dependency — offline is an explicit `--with-local` opt-in (see
[`offline-mode.md`](offline-mode.md)); forcing a 1.62 GB model on
every brew install would punish the 95% of users on Kyma or BYOK.
Offline users run:

```bash
brew install whisper-cpp
~/.watch-cli/install.sh --with-local
```

The `--with-local` flag stays the responsibility of `install.sh`;
the formula is a thin install of the bin scripts.

### Install block

```ruby
def install
  # Bin scripts shell-source files under lib/. Move both into the
  # formula prefix, then rewrite the bin scripts so that ROOT_DIR
  # resolves to the prefix, not "$SELF_DIR/..".
  libexec.install Dir["bin/*"]
  pkgshare.install "lib"
  pkgshare.install "prompts" if File.directory?("prompts")

  bin_files = Dir["#{libexec}/*"]
  bin_files.each do |script|
    inreplace script, %r{ROOT_DIR="\$\(cd "\$SELF_DIR/\.\." && pwd\)"},
              "ROOT_DIR=\"#{pkgshare}\""
  end

  bin.install_symlink bin_files
end
```

Bin scripts today resolve `ROOT_DIR="$(cd "$SELF_DIR/.." && pwd)"`
then `source "$ROOT_DIR/lib/...sh"`. Under Homebrew, the symlinked
binary at `$PREFIX/bin/watch` would resolve `$SELF_DIR/..` to
`$PREFIX` and look for `$PREFIX/lib/...` — wrong tree. The
`inreplace` pins `ROOT_DIR` to `pkgshare` so `source` lines find
their libraries. Real bin scripts live in `libexec`;
`bin.install_symlink` exposes them on `$PATH` (the homebrew-core
pattern for shell tools). `prompts/` is copied to `pkgshare` so the
README's "look in `prompts/`" line resolves to
`$(brew --prefix watch-cli)/share/watch-cli/prompts/`.

The implementer must verify the rewrite on a fresh `brew install`
(see *Test plan*) — bin scripts can change shape across releases and
the regex must keep matching.

### Test block

```ruby
test do
  system "#{bin}/watch", "--help"
end
```

`brew test watch-cli` runs after every install. The minimal test
asserts the binary exists, is executable, and exits 0 on `--help`.
`--help` over `--version` because it exercises lib sourcing — a
broken `ROOT_DIR` rewrite would fail to source `lib/env.sh` and the
help text would not print.

### Sketch — full formula

The implementer writes the real file; this sketch shows the shape.

```ruby
class WatchCli < Formula
  desc "Turn any social video into an architecture diagram or working component"
  homepage "https://github.com/sonpiaz/watch-cli"
  url "https://github.com/sonpiaz/watch-cli/releases/download/v#{version}/watch-cli.tar.gz"
  sha256 "<filled by release automation>"
  version "0.3.0"
  license "MIT"

  depends_on "yt-dlp"
  depends_on "ffmpeg"
  depends_on "jq"

  def install
    libexec.install Dir["bin/*"]
    pkgshare.install "lib"
    pkgshare.install "prompts" if File.directory?("prompts")

    bin_files = Dir["#{libexec}/*"]
    bin_files.each do |script|
      inreplace script, %r{ROOT_DIR="\$\(cd "\$SELF_DIR/\.\." && pwd\)"},
                "ROOT_DIR=\"#{pkgshare}\""
    end
    bin.install_symlink bin_files
  end

  test do
    system "#{bin}/watch", "--help"
  end
end
```

---

## Auto-bump on release

Phase 4 wires the watch-cli release workflow (see
[`releases.md`](releases.md)) to update `Formula/watch-cli.rb` on
every `v*` tag push. The bump is a separate job in
`.github/workflows/release.yml` after tarball + npm publish.

After the GH Release is created and the tarball SHA256 is known, the
job checks out `sonpiaz/homebrew-tap` via `HOMEBREW_TAP_PAT`, edits
only `version` and `sha256` (the `url` resolves via `v#{version}`
interpolation), and opens a PR:

```bash
VERSION="${GITHUB_REF_NAME#v}"
SHA256=$(cat watch-cli.tar.gz.sha256)
sed -i.bak \
  -e "s/^  version \".*\"$/  version \"${VERSION}\"/" \
  -e "s/^  sha256 \".*\"$/  sha256 \"${SHA256}\"/" \
  Formula/watch-cli.rb
rm Formula/watch-cli.rb.bak
git commit -am "watch-cli ${VERSION}"
git push origin "bump/watch-cli-${VERSION}"
gh pr create --repo sonpiaz/homebrew-tap \
  --title "watch-cli ${VERSION}" \
  --body "Automated bump from watch-cli v${VERSION} release."
```

The PR is reviewed manually for the first few releases. Auto-merge
is intentionally not the Phase 4 default — human review catches
accidental breakage before users `brew upgrade`.

### Required secret: `HOMEBREW_TAP_PAT`

Fine-grained PAT scoped narrowly: resource owner `sonpiaz`,
repository access only `sonpiaz/homebrew-tap`, repository permissions
`Contents` read+write + `Pull requests` read+write + `Metadata`
read-only (auto-included), no account permissions. Add to the
**watch-cli** repo's Actions secrets as `HOMEBREW_TAP_PAT`. Recommend
1-year expiry with a calendar reminder for rotation.

The default `GITHUB_TOKEN` cannot replace this PAT — it is scoped to
the workflow's own repo and cannot push to a different repository.

---

## First-formula bootstrap

The first release (v0.3.0) cannot rely on auto-bump — that job runs
after the release is created, but the formula must exist first.
Bootstrap:

1. Create the tap repo (`gh repo create` above).
2. Cut watch-cli v0.3.0 per [`releases.md`](releases.md). This
   produces `releases/download/v0.3.0/watch-cli.tar.gz` and its
   SHA256.
3. Hand-write `Formula/watch-cli.rb` in the tap, filling
   `version "0.3.0"` and the `sha256` from the release asset.
   Commit directly to `main` of the tap (no PR — first commit).
4. Verify on a fresh machine per the test plan below.
5. Future releases (v0.3.1+) use the auto-bump. Never hand-edit
   the formula after v0.3.0.

If the auto-bump misfires later (PAT expired, format drift,
permission change), fall back to the hand-edit sequence — log the
issue and fix the workflow before the next release.

---

## User install path

The README install section gains a Homebrew block above the curl
one-liner:

```bash
# macOS — Homebrew (recommended)
brew tap sonpiaz/tap
brew install watch-cli

# Any OS — curl
curl -fsSL https://github.com/sonpiaz/watch-cli/releases/latest/download/install.sh | bash
```

Once v0.3.0 ships and the tap is verified, the curl form stays
documented for Linux + servers + CI but is no longer the lead on
macOS. Existing curl-installed users can keep `~/.watch-cli` or
migrate via `rm -rf ~/.watch-cli ~/.local/bin/watch && brew install
watch-cli`.

---

## Linux note

Linuxbrew works (the formula does not gate on `OS.mac?`) but is rare
in this audience. Linux users should keep using the curl installer
— well-tested on Ubuntu and Debian via the CI matrix. Phase 4 does
not optimize for Linuxbrew: no CI matrix, no docs, no support
commitment. Issues filed get "use the curl installer on Linux."

---

## Test plan

The implementer must verify on a clean macOS machine (or fresh
Homebrew in a container) before declaring the tap published. Any
failure blocks the v0.3.0 ship.

1. **Tap discovery.** `brew tap sonpiaz/tap` succeeds, no warnings.
2. **Formula audit.** `brew audit --strict --online sonpiaz/tap`
   and `brew style sonpiaz/tap` pass with no errors. (`brew style`
   enforces `desc` length and Ruby formatting.)
3. **Install.** `brew install watch-cli` completes. Deps pulled
   automatically. Tarball download matches the formula SHA256.
4. **Layout.** `which watch` → `$(brew --prefix)/bin/watch`
   (symlink into `$(brew --prefix)/Cellar/watch-cli/<version>/libexec/`).
   `$(brew --prefix)/share/watch-cli/lib/env.sh` exists. Grep the
   installed script: `ROOT_DIR` rewritten to `pkgshare`.
5. **Smoke.** `watch --help` exits 0, prints help.
6. **`brew test`.** `brew test watch-cli` passes.
7. **End-to-end.** `watch https://www.youtube.com/watch?v=dQw4w9WgXcQ`
   produces a valid v1 text block (or v1 JSON with `--format json`).
   Transcribe reads `KYMA_API_KEY` from `~/.config/watch-cli/env`
   (Homebrew does not touch that file). Second run is a cache hit,
   < 2 seconds.
8. **Upgrade.** Hand-edit the tap formula to `0.3.1-test` against a
   synthetic tarball on a branch; `brew upgrade
   sonpiaz/tap/watch-cli` against the branch tap resolves cleanly.
9. **Clean uninstall.** `brew uninstall watch-cli` then `brew untap
   sonpiaz/tap`. After both: `which watch` returns nothing,
   `$(brew --prefix)/share/watch-cli/` is gone,
   `~/.config/watch-cli/env` untouched.

---

## Anti-patterns

- **Submitting to homebrew-core in this phase.** Tap first, validate
  over multiple releases, consider core only after the formula has
  been stable for ≥ one major version. Homebrew-core has a
  notability bar (~75 stars + months of stability) and a multi-week
  review queue; the tap unblocks users today.
- **Bundling whisper.cpp or the ggml model.** Offline is an explicit
  `--with-local` opt-in with a 1.62 GB model. Forcing it on every
  brew install punishes the majority of users.
- **Vendoring `yt-dlp` or `ffmpeg`.** Both are first-class Homebrew
  formulae with active security updates. `depends_on` keeps
  watch-cli users on the same binaries as the rest of their
  toolchain. Vendoring would freeze versions and put watch-cli on
  the hook for upstream breakage in tools we explicitly compose.
- **Patching bin scripts inside the formula beyond the `ROOT_DIR`
  rewrite.** A deeper patch belongs in the watch-cli repo, not the
  formula. Formulae that diverge from upstream become
  unmaintainable.
- **Auto-merging the bump PR by default.** Phase 4 keeps it manual.
  Auto-merge can be enabled later once proven; a malformed release
  would otherwise push to every user's next `brew upgrade`.

---

## Cross-references

- Release workflow that builds the tarball, computes SHA256, and
  triggers the bump: [`releases.md`](releases.md).
- Output schema the installed binary satisfies (Homebrew ships the
  binary, not a new schema): [`output-schema.md`](output-schema.md).
- Locked pitch and tone rules governing the `desc` line:
  [`../BRANDING.md`](../BRANDING.md).
- Offline transcribe path users opt into separately from brew:
  [`offline-mode.md`](offline-mode.md).
