/**
 * watch-cli MCP tool handler.
 *
 * Shells out to `watch <url> --format json [<frames>]`, parses the v1 JSON
 * payload from stdout, and returns it to the MCP caller.
 *
 * Exit-code mapping lives in mcp-server/SPEC.md § Error mapping. Tags from
 * stderr ride in the MCP error message field verbatim so callers can grep
 * for `tag=...` like they would on the CLI.
 */

import { spawn } from "node:child_process";
import { ErrorCode, McpError } from "@modelcontextprotocol/sdk/types.js";

export interface WatchToolArgs {
  url: string;
  frames?: number;
}

export interface WatchToolResult {
  content: Array<{ type: "text"; text: string }>;
  isError?: boolean;
  // CallToolResult schema in @modelcontextprotocol/sdk is a `$loose` zod object,
  // which TypeScript infers with an index signature. Mirror it here so the
  // server handler can return us directly without a cast.
  [key: string]: unknown;
}

const STDERR_TAIL_LIMIT = 1024;

function extractTag(stderr: string): string | null {
  const match = stderr.match(/tag=[a-z0-9-]+(?::[a-z0-9._-]+)?/i);
  return match ? match[0] : null;
}

function tailStderr(stderr: string): string {
  if (stderr.length <= STDERR_TAIL_LIMIT) return stderr;
  return stderr.slice(stderr.length - STDERR_TAIL_LIMIT);
}

interface CliResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

function runWatch(args: string[]): Promise<CliResult> {
  return new Promise((resolve, reject) => {
    const child = spawn("watch", args, { stdio: ["ignore", "pipe", "pipe"] });
    const stdoutChunks: Buffer[] = [];
    const stderrChunks: Buffer[] = [];

    child.stdout.on("data", (b: Buffer) => stdoutChunks.push(b));
    child.stderr.on("data", (b: Buffer) => stderrChunks.push(b));

    child.on("error", (err: NodeJS.ErrnoException) => {
      // ENOENT: `watch` not on PATH. Treat as missing-dep so the caller sees
      // the same tag shape the CLI itself would emit on exit 2.
      if (err.code === "ENOENT") {
        reject(
          new McpError(
            ErrorCode.InternalError,
            "tag=missing-dep:watch — install watch-cli via https://github.com/sonpiaz/watch-cli (curl install.sh | bash)",
          ),
        );
        return;
      }
      reject(
        new McpError(
          ErrorCode.InternalError,
          `failed to spawn watch: ${err.message}`,
        ),
      );
    });

    child.on("close", (code: number | null) => {
      resolve({
        exitCode: code ?? 1,
        stdout: Buffer.concat(stdoutChunks).toString("utf8"),
        stderr: Buffer.concat(stderrChunks).toString("utf8"),
      });
    });
  });
}

export async function handleWatch(args: WatchToolArgs): Promise<WatchToolResult> {
  if (!args || typeof args.url !== "string" || args.url.length === 0) {
    throw new McpError(
      ErrorCode.InvalidParams,
      "tag=usage-error — required field `url` is missing or empty",
    );
  }
  if (
    args.frames !== undefined &&
    (!Number.isInteger(args.frames) || args.frames < 1 || args.frames > 64)
  ) {
    throw new McpError(
      ErrorCode.InvalidParams,
      "tag=usage-error — `frames` must be an integer between 1 and 64",
    );
  }

  const cliArgs = ["--format", "json", args.url];
  if (args.frames !== undefined) cliArgs.push(String(args.frames));

  const { exitCode, stdout, stderr } = await runWatch(cliArgs);
  const tag = extractTag(stderr);
  const stderrTail = tailStderr(stderr).trim();

  switch (exitCode) {
    case 0: {
      // Happy path: stdout is one line of v1 JSON.
      const payload = stdout.trim();
      // Validate parse but pass the bytes through verbatim so optional fields
      // (transcribe_cost_usd) survive the round trip exactly as the CLI wrote
      // them.
      try {
        JSON.parse(payload);
      } catch (err) {
        throw new McpError(
          ErrorCode.InternalError,
          `tag=parse-error — CLI exited 0 but stdout was not valid JSON: ${(err as Error).message}`,
        );
      }
      return {
        content: [{ type: "text", text: payload }],
      };
    }

    case 4: {
      // Partial success: frames populated, transcript null, exit_code=4 in
      // the JSON. Do NOT throw — clients branch on obj.exit_code === 4.
      const payload = stdout.trim();
      try {
        JSON.parse(payload);
      } catch (err) {
        throw new McpError(
          ErrorCode.InternalError,
          `tag=parse-error — partial-success exit 4 but stdout was not valid JSON: ${(err as Error).message}`,
        );
      }
      if (tag) {
        // Log tag to stderr for the MCP host operator; not part of the
        // payload contract.
        process.stderr.write(`[watch-cli-mcp] partial success ${tag}\n`);
      }
      return {
        content: [{ type: "text", text: payload }],
        isError: false,
      };
    }

    case 2:
      throw new McpError(
        ErrorCode.InternalError,
        `${tag ?? "tag=missing-dep"} — ${stderrTail || "required binary not on PATH"}`,
      );

    case 3: {
      const isCallerRecoverable =
        tag === "tag=download-auth" || tag === "tag=download-region";
      const code = isCallerRecoverable
        ? ErrorCode.InvalidParams
        : ErrorCode.InternalError;
      throw new McpError(
        code,
        `${tag ?? "tag=download-other"} — ${stderrTail || "download failed"}`,
      );
    }

    case 64:
      throw new McpError(
        ErrorCode.InvalidParams,
        `${tag ?? "tag=usage-error"} — ${stderrTail || "usage error"}`,
      );

    case 1:
    default:
      throw new McpError(
        ErrorCode.InternalError,
        `tag=unknown — watch exited ${exitCode}: ${stderrTail || "no stderr"}`,
      );
  }
}

export const WATCH_TOOL_DEFINITION = {
  name: "watch",
  description:
    "Watch any social video → get an architecture diagram, working component, runnable notebook, or step-by-step cheat sheet — automatically.",
  inputSchema: {
    type: "object" as const,
    properties: {
      url: {
        type: "string",
        format: "uri",
        description:
          "A social video URL. Supported platforms: YouTube, X / Twitter, LinkedIn, TikTok, Vimeo, Reddit, Facebook.",
      },
      frames: {
        type: "integer",
        minimum: 1,
        maximum: 64,
        description:
          "Number of evenly-spaced frames to extract. Defaults to 8 when omitted. Bound to 64 to keep the response payload small.",
      },
    },
    required: ["url"],
    additionalProperties: false,
  },
};
