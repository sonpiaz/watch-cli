# Releases

This document is the source of truth for the watch-cli release
contract: semver policy, where the version number lives, what a tag
triggers, and how a consumer pins to a specific version. Every
downstream consumer (`install.sh`, the Homebrew tap, the
`@sonpiaz/watch-cli-mcp` npm package) reads a release artifact — a
tag, a tarball, a SHA256 — and those artifacts have a stability
promise.

---

## Purpose

Every install today hits `main` HEAD. `install.sh` clones the repo
from `main`, and the README's curl one-liner fetches
`raw.githubusercontent.com/sonpiaz/watch-cli/main/install.sh`. One bad
commit on `main` therefore breaks every machine that runs the
installer that minute, and there are zero published versions for
Homebrew or any other packager to pin against. Tagged releases give
downstream packagers a stable artifact and turn the v1 output schema
promise (see [`output-schema.md`](output-schema.md)) into a concrete
contract: "v1 means the tarball at tag v1.x.y."

---

## Semver policy

watch-cli follows semver with one pre-1.0 exception (see below).

### Stable (post v1.0.0)

| Bump | When | Examples |
|---|---|---|
| **Major** (X.0.0) | The v1 output schema in [`output-schema.md`](output-schema.md) changes incompatibly. A CLI flag is removed. A documented exit code changes meaning. | Removing `transcript` from JSON output; renaming `--cookies` to `--cookie-file`; changing the meaning of exit `4`. |
| **Minor** (0.X.0) | A new CLI flag, a new `bin/*` script, or a new `lib/*` helper ships. New optional JSON fields. New stderr tag tokens. | Adding `--no-audio`; adding `bin/cookies-export`; adding `transcribe_cost_usd` (already shipped). |
| **Patch** (0.0.X) | Bug fixes, doc updates, dependency version notes. No surface change. | Fixing a `stat` portability bug; correcting a README link; pinning yt-dlp recommendation in install.sh. |

A "surface change" is anything an external script can observe: stdout
contents in `--format json` or text mode, stderr `tag=…` tokens, exit
codes, CLI flags, environment variables read, file paths written. The
v1 stability promise in `output-schema.md` is the authoritative list.

### Pre-1.0 (current state)

watch-cli is at **v0.2.0** as of the merge of Phase 3. While the major
is `0`, minor bumps are **allowed to contain breaking changes** —
standard pre-1.0 semver. This gives the foundation specs
(output-schema, exit-codes, offline-mode, releases, homebrew) one
final shakeout before freeze. `0.X.0` may rename a JSON field, change
an exit code, or rename a stderr tag if the change improves the
spec. `0.0.X` continues to mean "bug fix only" even pre-1.0.

### Cutoff to v1.0.0

v1.0.0 is cut when all five of the following hold:

1. All foundation sub-specs are signed off: `output-schema.md`,
   `exit-codes.md`, `offline-mode.md`, `releases.md` (this file),
   `homebrew.md`.
2. The output schema in v1 has at least one external consumer in
   production. The MCP server in `mcp-server/` already meets this — it
   returns the v1 JSON shape verbatim.
3. The Homebrew tap is published and one user has installed via brew
   successfully (see [`homebrew.md`](homebrew.md)).
4. 30 days of green CI on `main` after the last spec sign-off, with
   the full matrix passing on macOS and Ubuntu.
5. No open issue tagged `schema-breaking` or `exit-code-breaking`.

Cutting v1.0.0 ends the breaking-change runway. After v1.0.0, any
schema or exit-code change requires a major bump and the v1
compatibility flag promised in `output-schema.md` (`--format
json-v1` available for at least one major release after v2 ships).

---

## Version source of truth

Today the `VERSION` string lives in two places: the constant
`VERSION="watch-cli v0.2.0"` on line 41 of `bin/watch` (other bin
scripts do not carry it), and `WATCH_CLI_VERSION="0.2.0"` in
`lib/env.sh` for the user-agent string.

Phase 4 consolidates into a single source — new file
`lib/version.sh`:

```bash
# lib/version.sh
export WATCH_CLI_VERSION="0.3.0"
export WATCH_CLI_VERSION_STRING="watch-cli v${WATCH_CLI_VERSION}"
```

- Every `bin/*` script sources `lib/version.sh` near the top (after
  `lib/env.sh`) and uses `$WATCH_CLI_VERSION_STRING` for `--version`.
  The hardcoded `VERSION=` in `bin/watch` is removed.
- `lib/env.sh` sources `lib/version.sh` and uses `$WATCH_CLI_VERSION`
  for the user-agent. The duplicate `WATCH_CLI_VERSION=` line in
  `env.sh` is removed.

Version becomes a one-line change at release time with no bin/lib
drift risk.

### CI guardrail

`.github/workflows/ci.yml` gains a step that compares the value of
`WATCH_CLI_VERSION` in `lib/version.sh` against the latest git tag
that matches `v*`. Mismatch on a `main` build fails CI with:

```text
error: lib/version.sh says 0.3.0 but latest tag is v0.4.0
fix: bump WATCH_CLI_VERSION in lib/version.sh to 0.4.0, or cut a new tag
```

The release workflow (below) re-checks the same invariant before
publishing.

---

## Tag policy

Tags name a single point on `main`. Format: `v<X.Y.Z>`. No
zero-stripping, no `-rc.N` suffix, no `-alpha`. Pre-1.0 cadence is
small enough that direct tags suffice; release-candidate runways
get added after v1.0.0 if needed.

### Cutting a release

1. Open a PR that bumps `WATCH_CLI_VERSION` in `lib/version.sh`.
   Title: `release: vX.Y.Z`. PR body lists user-facing changes
   (these get promoted into the GH Release notes).
2. CI passes (lint, smoke, schema, exit-code tests).
3. Merge with a squash commit titled `release: vX.Y.Z`.
4. From `main` at the merged commit:
   ```bash
   git checkout main && git pull --rebase
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin vX.Y.Z
   ```
5. The release workflow fires on the tag push and creates the GH
   Release, publishes the npm package, and bumps the Homebrew tap.

Tags are cut from `main` only. The release workflow asserts the tag's
commit is an ancestor of `origin/main`.

---

## Release notes template

Auto-generated from squashed PR titles since the previous tag, then
human-edited before publish.

```markdown
## Highlights
- One-line summary of the headline change.
- Up to three more bullets for anything an installed user would care
  about (new flag, new platform, breaking change).

## What's new
<auto-generated list of squashed PR titles since the previous tag,
one per bullet, linked to PR>

## Schema version
Output schema: v1 (no change since v0.3.0). See
[output-schema.md](https://github.com/sonpiaz/watch-cli/blob/vX.Y.Z/docs/output-schema.md).

## Install
    brew tap sonpiaz/tap && brew install watch-cli            # macOS
    curl -fsSL https://github.com/sonpiaz/watch-cli/releases/download/vX.Y.Z/install.sh | bash
    WATCH_CLI_VERSION=X.Y.Z curl -fsSL <same-url> | bash       # pin

## Acknowledgements
Thanks to <handles> for issues, patches, and review.
```

The "Schema version" line is required on every release. If the major
did not change, say so explicitly — downstream consumers grep for it
to confirm they do not need to re-validate their parser.

---

## GitHub Actions release workflow

File: `.github/workflows/release.yml`. Trigger: `on: push: tags:
['v*']`. Each step is required; failure aborts the release.

### 1. Verify the tag

Check out the tag's commit; assert the commit is an ancestor of
`origin/main`. If not, fail with `error: tag vX.Y.Z is not on main
(got <sha>); refusing to release`.

### 2. Verify the version

Source `lib/version.sh`; assert `$WATCH_CLI_VERSION` equals the tag
minus the leading `v`. Mismatch fails with the CI guardrail message.

### 3. Build the source tarball

```bash
VERSION="${GITHUB_REF_NAME#v}"
git archive --format=tar.gz \
  --prefix="watch-cli-${VERSION}/" \
  -o "watch-cli.tar.gz" HEAD
sha256sum watch-cli.tar.gz | awk '{print $1}' > watch-cli.tar.gz.sha256
```

Tarball name is `watch-cli.tar.gz` — fixed, not version-suffixed.
The Homebrew formula resolves the per-version URL via `v#{version}`
interpolation (see [`homebrew.md`](homebrew.md)).

### 4. Create the GH Release

```bash
gh release create "v${VERSION}" \
  --title "v${VERSION}" \
  --notes-file release-notes.md \
  watch-cli.tar.gz \
  watch-cli.tar.gz.sha256 \
  install.sh
```

Three assets attached: source tarball, SHA256 file, and a copy of
`install.sh` from the tagged commit (so the pin-a-version curl form
resolves cleanly).

### 5. Publish the MCP server

```bash
cd mcp-server
npm ci
npm run build
npm publish --access public
```

Requires `NPM_TOKEN` repo secret scoped to publish under `@sonpiaz/`.
`mcp-server/package.json` must already carry the correct version —
the version-bump PR includes a bump of `mcp-server/package.json` to
match.

### 6. Bump the Homebrew tap

Opens a PR against `sonpiaz/homebrew-tap` with the new `version` and
`sha256` in `Formula/watch-cli.rb`. Full mechanism in
[`homebrew.md`](homebrew.md). Requires the `HOMEBREW_TAP_PAT` repo
secret (fine-grained PAT scoped to `sonpiaz/homebrew-tap`,
contents:write + pull-requests:write).

### Required repo secrets

- `NPM_TOKEN` — step 5; publish under `@sonpiaz/` on npm.
  **Setup (one-time, manual):** generate an Automation token at
  https://www.npmjs.com/settings/sonpiaz/tokens, then paste into the
  watch-cli repo at Settings → Secrets and variables → Actions →
  New repository secret. Without this, the `publish-mcp` job fails
  and no MCP server is published — the GH Release and tarball are
  unaffected.
- `HOMEBREW_TAP_PAT` — step 6; push branches + open PRs in
  `sonpiaz/homebrew-tap`.
  **Setup (one-time, manual):** generate a fine-grained PAT at
  https://github.com/settings/personal-access-tokens, scope:
  resource owner `sonpiaz`, repo access only `sonpiaz/homebrew-tap`,
  permissions `contents:write` + `pull-requests:write` +
  `metadata:read`, 1-year expiry. Paste into the watch-cli repo at
  Settings → Secrets and variables → Actions. Without this, the
  `bump-tap` job fails and Homebrew users do not get an auto-bump
  PR — the GH Release and npm publish are unaffected.
- `GITHUB_TOKEN` (built-in) is sufficient for steps 1–4.

---

## Install URL strategy

`install.sh` today clones `main` HEAD. Phase 4 changes it to fetch a
tagged release tarball.

```bash
# default — latest
curl -fsSL https://github.com/sonpiaz/watch-cli/releases/latest/download/install.sh | bash

# pin a specific version
WATCH_CLI_VERSION=0.3.0 curl -fsSL \
  https://github.com/sonpiaz/watch-cli/releases/download/v0.3.0/install.sh | bash
```

`releases/latest/download/<asset>` is a GitHub-managed redirect that
always resolves to the newest published release. The installer
fetches `watch-cli.tar.gz` from the same release and unpacks into
`$INSTALL_DIR` instead of cloning `main`. When `WATCH_CLI_VERSION` is
set, the installer fetches from
`releases/download/v${WATCH_CLI_VERSION}/watch-cli.tar.gz`. Mismatch
between URL and env variable aborts with `error: WATCH_CLI_VERSION=…
disagrees with installer for v…`.

### What changes in `install.sh`

The implementer (not this spec) edits the installer:

- Replace `git clone "$REPO_URL" "$INSTALL_DIR"` with `curl -fsSL
  <tarball-url> | tar -xz -C "$INSTALL_DIR" --strip-components=1`.
- Replace the `git pull --rebase` update path with a version compare
  against the latest release and a fresh tarball fetch if newer.
- Resolve `WATCH_CLI_VERSION` into the URL when set.
- Verify tarball SHA256 against `watch-cli.tar.gz.sha256` before
  unpacking. Mismatch is fatal `exit 1` with stderr
  `tag=tarball-checksum-mismatch`.

The `git clone` path stays available for the README's "from a clone"
flow — a developer who clones the repo and runs `./install.sh`
locally still works. Only `curl | bash` uses the release tarball.

---

## What the implementer must do before tagging v1.0.0

1. All five foundation specs merged and signed off:
   `output-schema.md`, `exit-codes.md`, `offline-mode.md`,
   `releases.md`, `homebrew.md`.
2. Homebrew tap published. `brew install sonpiaz/tap/watch-cli`
   succeeds on a fresh macOS machine ([`homebrew.md`](homebrew.md)).
3. `@sonpiaz/watch-cli-mcp` is on npm at a version matching
   watch-cli (MCP v1.0.0 ships when watch-cli v1.0.0 ships).
4. CI green on `main` for 30 days. No skipped jobs, no
   `continue-on-error: true` on any required step.
5. No open issue tagged `schema-breaking` or `exit-code-breaking`.
6. v1.0.0 release notes call out the stability-promise from
   `output-schema.md`: "Output schema is now frozen at v1. Any
   future incompatible change ships as v2 with a one-major-version
   `--format json-v1` compatibility flag."

---

## Test plan

The implementer must verify end to end before declaring done:

1. **Local dry-run.** Run the workflow on a personal fork. Tag a
   v0.3.0-rc local-only tag (or use
   [`nektos/act`](https://github.com/nektos/act)); confirm steps 1–4
   produce a tarball and a GH Release on the fork.
2. **Tarball integrity.** Download `watch-cli.tar.gz`, verify SHA256
   against `watch-cli.tar.gz.sha256`, unpack and run
   `./watch-cli-0.3.0/install.sh` on a clean container. `watch
   --version` prints `watch-cli v0.3.0`.
3. **Pinned install.** Run the `WATCH_CLI_VERSION=0.3.0` curl form
   on a second clean container. Same result.
4. **Latest install.** Run the `releases/latest/download/install.sh`
   form. Resolves to v0.3.0.
5. **MCP server publish.** `@sonpiaz/watch-cli-mcp@0.3.0` is on npm,
   `bin/watch-cli-mcp` works via `npx`.
6. **Homebrew bump.** A PR opens against `sonpiaz/homebrew-tap`
   titled `watch-cli 0.3.0`; merging makes `brew upgrade watch-cli`
   work. Full Homebrew test plan in [`homebrew.md`](homebrew.md).
7. **Version mismatch.** Push a tag `v0.3.1` without bumping
   `lib/version.sh`. The workflow fails at step 2 with the
   documented error; no release is created.

---

## Cross-references

- Output schema this release ships with:
  [`output-schema.md`](output-schema.md).
- Homebrew tap and per-release formula bump:
  [`homebrew.md`](homebrew.md).
- Exit codes the installer and the release workflow exit with on
  failure: [`exit-codes.md`](exit-codes.md).
