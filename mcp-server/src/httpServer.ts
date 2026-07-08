import { randomUUID } from "node:crypto";
import express from "express";
import type { Request, Response } from "express";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { isInitializeRequest } from "@modelcontextprotocol/sdk/types.js";
import { createServer } from "./server.js";

export async function startHttpServer(): Promise<void> {
  const token = process.env.WP_OPS_MCP_TOKEN;
  if (!token) {
    console.error(
      "MCP_TRANSPORT=http requires WP_OPS_MCP_TOKEN to be set. This server can SSH into " +
        "staging/production hosts on your behalf, so it refuses to start unauthenticated. " +
        "Set a long random token and have clients send 'Authorization: Bearer <token>'."
    );
    process.exit(1);
  }

  const host = process.env.MCP_HTTP_HOST ?? "127.0.0.1";
  const port = Number(process.env.MCP_HTTP_PORT ?? 3000);

  const app = express();
  app.use(express.json());

  app.use((req, res, next) => {
    if (req.header("authorization") !== `Bearer ${token}`) {
      res.status(401).json({ jsonrpc: "2.0", error: { code: -32001, message: "Unauthorized" }, id: null });
      return;
    }
    next();
  });

  const transports = new Map<string, StreamableHTTPServerTransport>();

  app.post("/mcp", async (req: Request, res: Response) => {
    const sessionId = req.header("mcp-session-id");
    let transport = sessionId ? transports.get(sessionId) : undefined;

    if (!transport) {
      if (sessionId || !isInitializeRequest(req.body)) {
        res.status(400).json({
          jsonrpc: "2.0",
          error: { code: -32000, message: "Bad Request: no valid session ID provided" },
          id: null,
        });
        return;
      }

      transport = new StreamableHTTPServerTransport({
        sessionIdGenerator: () => randomUUID(),
        onsessioninitialized: (sid) => {
          transports.set(sid, transport!);
        },
      });
      transport.onclose = () => {
        if (transport!.sessionId) transports.delete(transport!.sessionId);
      };

      const mcpServer = createServer();
      await mcpServer.connect(transport);
    }

    await transport.handleRequest(req, res, req.body);
  });

  const handleSessionRequest = async (req: Request, res: Response) => {
    const sessionId = req.header("mcp-session-id");
    const transport = sessionId ? transports.get(sessionId) : undefined;
    if (!transport) {
      res.status(400).send("Invalid or missing session ID");
      return;
    }
    await transport.handleRequest(req, res);
  };

  app.get("/mcp", handleSessionRequest);
  app.delete("/mcp", handleSessionRequest);

  app.listen(port, host, () => {
    console.error(`wp-ops MCP server listening on http://${host}:${port}/mcp (Streamable HTTP, auth required)`);
  });
}
