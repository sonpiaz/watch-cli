#!/usr/bin/env node
/**
 * watch-cli MCP stdio server entry point.
 *
 * Registers the `watch` tool, runs over stdio, exits cleanly on EOF or
 * SIGINT/SIGTERM. The SDK serializes concurrent tool calls; each call shells
 * out to the local `watch` CLI.
 *
 * Spec: ../SPEC.md
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  type CallToolResult,
} from "@modelcontextprotocol/sdk/types.js";

import { WATCH_TOOL_DEFINITION, handleWatch, type WatchToolArgs } from "./watch-tool.js";

const SERVER_NAME = "watch-cli-mcp";
const SERVER_VERSION = "0.1.0";

async function main(): Promise<void> {
  const server = new Server(
    {
      name: SERVER_NAME,
      version: SERVER_VERSION,
    },
    {
      capabilities: {
        tools: {},
      },
    },
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [WATCH_TOOL_DEFINITION],
  }));

  server.setRequestHandler(
    CallToolRequestSchema,
    async (request): Promise<CallToolResult> => {
      if (request.params.name !== WATCH_TOOL_DEFINITION.name) {
        throw new Error(`unknown tool: ${request.params.name}`);
      }
      const args = (request.params.arguments ?? {}) as unknown as WatchToolArgs;
      return handleWatch(args);
    },
  );

  const transport = new StdioServerTransport();
  await server.connect(transport);

  // Graceful shutdown — close transport, exit 0.
  const shutdown = async () => {
    try {
      await server.close();
    } finally {
      process.exit(0);
    }
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

main().catch((err) => {
  process.stderr.write(
    `[watch-cli-mcp] fatal: ${err instanceof Error ? err.message : String(err)}\n`,
  );
  process.exit(1);
});
