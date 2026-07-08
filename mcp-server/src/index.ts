#!/usr/bin/env node
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createServer } from "./server.js";
import { startHttpServer } from "./httpServer.js";

const transportMode = process.env.MCP_TRANSPORT ?? "stdio";

if (transportMode === "http") {
  await startHttpServer();
} else {
  const server = createServer();
  const transport = new StdioServerTransport();
  await server.connect(transport);
}
