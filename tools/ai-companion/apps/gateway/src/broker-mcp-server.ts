import { randomBytes } from "node:crypto";
import { createServer, type Server } from "node:http";
import { NodeStreamableHTTPServerTransport } from "@modelcontextprotocol/node";
import { McpServer } from "@modelcontextprotocol/server";
import type { ToolBroker } from "../../../packages/core/src/index.js";
import { toMcpToolResult } from "./tool-result-content.js";

export class BrokerMcpServer {
  readonly #broker: ToolBroker;
  readonly #toolNames: string[] | undefined;
  readonly #token = randomBytes(32).toString("base64url");
  #server: Server | undefined;
  #url: string | undefined;

  constructor(broker: ToolBroker, toolNames?: string[]) {
    this.#broker = broker;
    this.#toolNames = toolNames;
  }

  async start(): Promise<{ url: string; authorization: string }> {
    if (this.#url) return { url: this.#url, authorization: `Bearer ${this.#token}` };
    this.#server = createServer(async (request, response) => {
      if (request.url !== "/mcp") {
        response.writeHead(404).end();
        return;
      }
      if (request.headers.authorization !== `Bearer ${this.#token}`) {
        response.writeHead(401).end();
        return;
      }
      try {
        const server = this.#createMcpServer();
        const transport = new NodeStreamableHTTPServerTransport({ sessionIdGenerator: undefined });
        await server.connect(transport);
        await transport.handleRequest(request, response);
      } catch {
        if (!response.headersSent) response.writeHead(500);
        response.end();
      }
    });
    await new Promise<void>((resolve, reject) => {
      this.#server!.once("error", reject);
      this.#server!.listen(0, "127.0.0.1", () => {
        this.#server!.off("error", reject);
        resolve();
      });
    });
    const address = this.#server.address();
    if (!address || typeof address === "string") throw new Error("MCP loopback server did not bind a TCP port");
    this.#url = `http://127.0.0.1:${address.port}/mcp`;
    return { url: this.#url, authorization: `Bearer ${this.#token}` };
  }

  async close(): Promise<void> {
    const server = this.#server;
    this.#server = undefined;
    this.#url = undefined;
    if (!server) return;
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }

  #createMcpServer(): McpServer {
    const server = new McpServer({ name: "godot-agent-session", version: "0.13.0" });
    for (const { definition, schema } of this.#broker.runtimeDefinitions(this.#toolNames)) {
      server.registerTool(
        definition.name,
        {
          title: definition.name.replaceAll("_", " "),
          description: definition.description,
          inputSchema: schema,
          annotations: {
            readOnlyHint: definition.risk === "read",
            destructiveHint: definition.risk === "destructive",
            idempotentHint: definition.risk === "read",
            openWorldHint: false,
          },
        },
        async (input) => {
          const result = await this.#broker.execute(definition.name, input);
          return toMcpToolResult(result);
        },
      );
    }
    return server;
  }
}
