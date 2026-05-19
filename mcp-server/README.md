# @sonpiaz/watch-cli-mcp

MCP (Model Context Protocol) stdio server that exposes [watch-cli](https://github.com/sonpiaz/watch-cli) as a callable tool.

> Watch any social video → get an architecture diagram, working component, runnable notebook, or step-by-step cheat sheet — automatically.

A single MCP server reaches every MCP-capable agent runtime — Claude Desktop, Claude Code, Cursor, OpenClaw, hermes-agent, Cline, Continue.dev, Windsurf, Zed, Codex, Kiro, VS Code Copilot — without per-IDE plugin work. This package wraps `watch-cli` so any of them can call it through one channel.

## Prerequisites

- Node.js >= 18.
- The `watch` CLI installed and on `PATH`. Install with:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/sonpiaz/watch-cli/main/install.sh | bash
  ```

The MCP server shells out to `watch`; it does not bundle the CLI.

## Install

```bash
npm install -g @sonpiaz/watch-cli-mcp
```

Or run on demand via `npx`:

```bash
npx -y @sonpiaz/watch-cli-mcp
```

The binary is `watch-cli-mcp`. It reads JSON-RPC on stdin, writes JSON-RPC on stdout, and logs to stderr.

## Tool

One tool is registered: `watch`.

**Input schema:**

```json
{
  "type": "object",
  "properties": {
    "url": {
      "type": "string",
      "format": "uri",
      "description": "A social video URL. Supported: YouTube, X / Twitter, LinkedIn, TikTok, Vimeo, Reddit, Facebook."
    },
    "frames": {
      "type": "integer",
      "minimum": 1,
      "maximum": 64,
      "description": "Number of evenly-spaced frames to extract. Default 8."
    }
  },
  "required": ["url"],
  "additionalProperties": false
}
```

**Output:** the v1 JSON object from [`docs/output-schema.md`](https://github.com/sonpiaz/watch-cli/blob/main/docs/output-schema.md), passed through verbatim. Read the schema for the field reference.

## Error mapping

| CLI exit | MCP response |
|---|---|
| `0` | Tool result with the v1 JSON as `content[0].text`. |
| `2` | `InternalError`, message includes `tag=missing-dep:<bin>`. |
| `3` `download-auth` / `download-region` | `InvalidParams`, message includes the tag — caller can recover with cookies or a different URL. |
| `3` `download-network` / `download-other` | `InternalError`, message includes the tag. |
| `4` (partial success) | Tool result with `isError: false`. Frames populated, transcript `null`, `exit_code: 4` in the JSON payload. Caller branches on `obj.exit_code === 4`. |
| `64` | `InvalidParams`, message includes `tag=usage-error`. |
| `1` / other | `InternalError`, message includes the CLI stderr tail (≤ 1 KB). |

Tags always ride in the MCP error `message` field so callers can grep for the same `tag=...` token they would see in CLI stderr.

## Client configuration

### Claude Desktop

Config path:

- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`
- Linux: `~/.config/Claude/claude_desktop_config.json`

Merge into the existing `mcpServers` object:

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

Restart Claude Desktop after editing.

### Cursor

Config path: `.cursor/mcp.json` (project-scoped) or `~/.cursor/mcp.json` (user-global). Same `mcpServers` object shape as Claude Desktop:

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

### hermes-agent

Config path: `optional-skills/mcp.json` inside the hermes-agent install, or `~/.hermes-agent/mcp.json` user-global. Same `mcpServers` shape as above.

### Other MCP clients

Any MCP-capable agent that accepts an `npx` command will work with the snippet above. Substitute the client's config path; the `command` / `args` pair is portable.

## Build from source

```bash
git clone https://github.com/sonpiaz/watch-cli
cd watch-cli/mcp-server
npm install
npm run build
node dist/index.js
```

## License

MIT. © 2026 Son Piaz.
