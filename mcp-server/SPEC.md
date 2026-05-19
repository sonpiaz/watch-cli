# MCP server specification

This document is the contract for the watch-cli MCP (Model Context
Protocol) stdio server. The actual server is authored against this
spec during Phase 2 implementation; this document is the source of
truth for its shape.

Cross-references:

- Output contract the server must return verbatim:
  [`../docs/output-schema.md`](../docs/output-schema.md)
- Exit codes that map onto MCP error codes:
  [`../docs/exit-codes.md`](../docs/exit-codes.md)
- Pitch text reused in the tool `description`:
  [`../BRANDING.md`](../BRANDING.md)
- MCP transport reference:
  https://modelcontextprotocol.io/specification/2025-03-26/basic/transports

---

## Purpose

A single MCP server reaches every MCP-capable agent runtime without
per-IDE plugin work. By 2026 that includes Claude Desktop, Claude Code,
Cursor, OpenClaw, hermes-agent, Cline, Continue.dev, Windsurf, Zed,
Codex, Kiro, and VS Code Copilot — twelve plus production agents in
one codebase. The server exposes `watch` as a callable tool whose
input and output exactly match the v1 contract in
[`../docs/output-schema.md`](../docs/output-schema.md), so every
downstream consumer parses one shape regardless of channel
(CLI stdout, MCP tool response, skill body parse rules).

---

## Package decision

Two options considered:

- **(a) Standalone npm package** `@sonpiaz/watch-cli-mcp` — separate
  TypeScript codebase under `mcp-server/`, depends on
  `@modelcontextprotocol/sdk`. Independent semver. CLI-only users never
  install the MCP package.
- **(b) Built-in subcommand** `watch --mcp-serve` — the existing Bash
  script grows an MCP mode. Single binary, no npm dep for CLI-only.

**Locked choice: (a) standalone npm package `@sonpiaz/watch-cli-mcp`.**

Justification:

1. **Bash is a poor host for MCP.** JSON-RPC framing + an evolving
   capabilities handshake + JSON-schema validation are all in the
   TypeScript SDK already; re-implementing them in shell is busywork.
2. **The CLI install path stays small.** `curl install.sh | bash` users
   keep getting six Bash scripts and a Python helper, no Node
   toolchain forced on them.
3. **Independent release cadence.** The MCP wire format iterates
   faster than the CLI contract; bumping one without the other is
   easier when they are separate artifacts.
4. **`npx` is the canonical install verb for MCP servers** in every
   published client config snippet today (Claude Desktop, Cursor,
   Continue.dev all show `npx <package>`).

Trade-off: two release artifacts. Mitigated by mirroring the version
(see § *Publish workflow*).

---

## Package layout

The implementer creates the following files under `mcp-server/`. No
file outside `mcp-server/` is modified by the implementation PR except
where the consumer-facing README needs a "Run as MCP server" line.

| Path | Purpose |
|---|---|
| `mcp-server/package.json` | Package manifest. Fields below. |
| `mcp-server/tsconfig.json` | TypeScript build config. Targets ES2022, module `Node16`, `strict: true`, `outDir: dist`. |
| `mcp-server/src/index.ts` | Entry point. Wires the stdio transport, registers the `watch` tool, starts the server. |
| `mcp-server/src/watch-tool.ts` | Tool handler. Shells out to `watch --format json`, parses the result, maps exit codes onto MCP error codes. |
| `mcp-server/README.md` | User-facing readme: install line + config snippets for the major MCP clients. |
| `mcp-server/.gitignore` | Ignores `node_modules/`, `dist/`. |

### `package.json` fields

| Field | Value |
|---|---|
| `name` | `@sonpiaz/watch-cli-mcp` |
| `version` | Mirrors `bin/watch` `VERSION`. First cut: `0.2.0`. |
| `description` | Locked pitch from `BRANDING.md`, ≤ 350 chars, single line. |
| `bin.watch-cli-mcp` | `./dist/index.js` |
| `type` | `module` |
| `engines.node` | `>=20.0.0` (matches MCP SDK). |
| `dependencies` | `@modelcontextprotocol/sdk` pinned to latest stable minor at impl time (current: `^1.29.0`). No other runtime deps. |
| `devDependencies` | `typescript ^5.4.0`, `@types/node ^20.0.0`. |
| `scripts.build` | `tsc -p .` |
| `scripts.prepublishOnly` | `npm run build` (guards against stale `dist/`). |
| `files` | `["dist", "README.md"]`. |

---

## Tool definition

Exactly one tool is registered: `watch`.

### Name

`watch`

### Description

The locked pitch from `BRANDING.md`, ≤ 350 characters. Single line.

### Input schema (JSON Schema)

```json
{
  "type": "object",
  "properties": {
    "url": {
      "type": "string",
      "format": "uri",
      "description": "A social video URL. Supported platforms: YouTube, X / Twitter, LinkedIn, TikTok, Vimeo, Reddit, Facebook."
    },
    "frames": {
      "type": "integer",
      "minimum": 1,
      "maximum": 64,
      "description": "Number of evenly-spaced frames to extract. Defaults to 8 when omitted. Bound to 64 to keep the response payload small."
    }
  },
  "required": ["url"],
  "additionalProperties": false
}
```

The `frames` upper bound of 64 is policy: the CLI itself does not cap,
but the MCP response carries every frame path as a string and the
caller almost always wants a small set. Anything higher is a CLI
invocation, not an MCP tool call.

### Output

Returns the v1 JSON object from
[`../docs/output-schema.md`](../docs/output-schema.md) **unchanged**.

The handler runs `watch --format json <url> [<frames>]`, parses the
CLI's single-line stdout JSON, and returns it as the MCP tool result
`content[0].text` (a JSON string per the MCP `text` content shape).
Every field passes through verbatim; optional fields
(`transcribe_cost_usd`) stay optional. If the CLI schema bumps to v2,
the server passes v2 through unchanged — clients detect version via
`obj.version`, not via the server.

---

## Wire format

stdio JSON-RPC 2.0, line-delimited, UTF-8, no embedded newlines per the
MCP transport spec
(https://modelcontextprotocol.io/specification/2025-03-26/basic/transports).
The SDK's `StdioServerTransport` provides framing; the implementation
does not hand-roll it.

- One JSON-RPC message per line on stdin and stdout, all UTF-8.
- No bare newlines in any field value.
- The server reads stdin to EOF, then exits cleanly.
- The server logs to stderr only. Anything written to stdout that is
  not a framed MCP response is a protocol violation. The handler must
  capture the CLI's stdout JSON, never let it fall through to the
  parent stdout.

---

## Error mapping

The watch CLI exit codes (see [`../docs/exit-codes.md`](../docs/exit-codes.md))
map onto MCP error codes as follows. The MCP `code` constants below
are the ones exposed by `@modelcontextprotocol/sdk`.

| CLI exit | CLI meaning | MCP response shape |
|---|---|---|
| `0` | success | Tool result with the v1 JSON payload as `content[0].text`. No `isError`. |
| `2` | missing dependency (yt-dlp, ffmpeg, etc.) | Throw an SDK error with code `InternalError`. The message string starts with `tag=missing-dep:<bin>` so a caller `grep`s the same token as in CLI stderr. |
| `3` | download failed (auth, region, network, other) | Throw an SDK error. **Code depends on tag:** `tag=download-auth` and `tag=download-region` → `InvalidParams` (the caller can recover with cookies or a different URL — these are inputs the caller controls). `tag=download-network` and `tag=download-other` → `InternalError`. Message always includes the tag token verbatim. |
| `4` | transcribe failed — **partial success** | Return the tool result with the v1 JSON payload (`frame_paths` populated, `transcript: null`, `exit_code: 4`). Set `isError: false` on the tool result. The non-zero exit is conveyed via the JSON `exit_code` field, not the MCP error channel — otherwise the caller loses the frames. The implementation logs the `tag=transcribe-*` token to stderr but does not throw. |
| `64` | usage error (bad URL, malformed flag) | Throw an SDK error with code `InvalidParams`. Message includes `tag=usage-error` and the CLI usage line. |
| `1` | uncategorized | Throw an SDK error with code `InternalError`. Message includes whatever the CLI wrote to stderr (truncated to 1 KB). |

**Locked decisions called out** because the source docs leave them open:

1. **Exit 4 is success at the MCP layer, partial at the payload layer.**
   Preserving the partial-success contract from
   [`../docs/exit-codes.md`](../docs/exit-codes.md) means the server
   must not throw on exit 4 — otherwise clients would have to recover
   frames from an error string. Clients branch on `obj.exit_code === 4`.
2. **Exit 3 splits across two MCP codes by stderr tag.** Auth and
   region are caller-recoverable (cookies, different URL) →
   `InvalidParams`. Network and other are environment-side →
   `InternalError`. Splitting lets clients decide retry vs. ask-user
   without parsing prose.
3. **Tags ride in the `message` field**, not in protocol-level fields.
   A future MCP revision that adds a stable `tags` field on errors
   can migrate without breaking clients.

---

## Lifecycle

- Starts when invoked via `npx @sonpiaz/watch-cli-mcp` (or local
  `dist/index.js` after `npm install -g`).
- Constructs an `StdioServerTransport`, registers the `watch` tool
  plus the SDK's `tools/list` and `tools/call` handlers.
- Reads stdin until EOF; on EOF exits `0`. On `SIGTERM` / `SIGINT`
  closes the transport cleanly and exits `0`.
- Uncaught exceptions inside a tool handler are caught by the SDK
  and surfaced as JSON-RPC error responses; the process keeps running.
- No persistent state between tool calls. Each call shells out to
  `watch` and returns. The SDK serializes concurrent calls.

---

## Config snippets

The `mcp-server/README.md` ships the exact JSON snippets users paste
into each major MCP client's config file. The snippets below are the
canonical text; the implementer copies them into the README verbatim.

### Claude Desktop

Config path:

- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`
- Linux: `~/.config/Claude/claude_desktop_config.json`

Snippet (merge into the existing `mcpServers` object):

```json
{
  "mcpServers": {
    "watch-cli": {
      "command": "npx",
      "args": ["-y", "@sonpiaz/watch-cli-mcp"]
    }
  }
}
```

### Cursor

Config path: `.cursor/mcp.json` (project) or `~/.cursor/mcp.json`
(user-global). Same `mcpServers` object shape as Claude Desktop.

### hermes-agent

Config path: `optional-skills/mcp.json` inside the hermes-agent
install, or `~/.hermes-agent/mcp.json` user-global. Same
`mcpServers` shape. If hermes-agent ships a different path in a
future release, only the README updates; the server code does not.

---

## Test plan

The implementer must verify all of the following before publishing.

1. **Boot smoke.** `npx @sonpiaz/watch-cli-mcp` starts, prints nothing
   to stdout, accepts an MCP `initialize` request, and responds with
   the SDK's capabilities object.
2. **`tools/list` returns `watch`.** Exactly one tool with the right
   `name`, locked-pitch `description`, and the input schema above.
3. **`tools/call` happy path.** A known-good public YouTube URL
   returns a tool result whose `content[0].text` parses as JSON and
   matches the v1 schema (all required fields, `version: 1`,
   `exit_code: 0`).
4. **`tools/call` partial success.** A simulated CLI exit-4 (fixture
   or known silent-audio URL) returns `isError: false`, frames
   populated, `transcript: null`, `exit_code: 4`. The server does
   **not** throw.
5. **`tools/call` usage error.** A malformed `url` returns a JSON-RPC
   error with code `InvalidParams` and message containing `tag=`.
6. **`tools/call` missing dep.** With `yt-dlp` off `PATH`, expect
   error code `InternalError` and message containing
   `tag=missing-dep:yt-dlp`.
7. **Manual mcporter integration.**
   `mcporter call --stdio "npx -y @sonpiaz/watch-cli-mcp" watch.watch url=<known-good-yt-url>`
   returns the v1 JSON payload.
8. **Phase 1 regression.** Existing shell tests
   (`tests/test-output-schema.sh`, `tests/test-exit-codes.sh`) still
   pass against `bin/watch`. The MCP server must be additive — no
   change to `bin/`.

Tests 1–6 live in `mcp-server/test/`. Test 7 is manual (requires
`mcporter` and live network). Test 8 runs in existing CI unchanged.

---

## Publish workflow

1. **Versioning.** The package version mirrors the CLI version
   (`bin/watch` `VERSION` constant). A release PR bumps both in the
   same commit. One number answers "is the MCP server in sync with
   the CLI?".
2. **Build.** From `mcp-server/`: `npm install && npm run build`.
3. **Pre-publish check.** `npm pack --dry-run` and verify the tarball
   contains `dist/`, `README.md`, `package.json` — nothing else.
4. **Publish.** `npm publish --access public`. First publish under a
   new scope requires `npm login`.
5. **2FA.** The maintainer's npm account uses TOTP; the CLI prompts
   for the code during `npm publish`. No CI auto-publish in Phase 2;
   `prepublishOnly` guards against shipping stale `dist/`.
6. **Tag alignment.** The same git tag that gates the GitHub Release
   (Phase 4 item #11) gates the npm publish. Pre-releases
   (`0.2.0-beta.1`) are allowed without a release tag and the README
   marks them as such.

Future CI improvement, out of scope for Phase 2: a workflow on `v*`
tag push that runs `npm publish --provenance`. Documented in
`docs/releases.md` (Phase 4 sub-spec).
