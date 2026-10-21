# Personal Godot AI companion

Node 24+, on your own PC/server. API-key inference, Ollama/LM Studio and ComfyUI
connections run directly from the APK; the companion is optional.

```sh
npm ci
npm run build
npm start
```

The server binds to `127.0.0.1:7341` by default and creates an owner-only pairing
token at `~/.config/godot-ai-companion/pairing.token`. Enter that token in the
editor's subscription settings. To connect from another device, set
`AI_COMPANION_HOST=0.0.0.0` on your private network, or use an authenticated HTTPS
tunnel. No fixed shared token is included in the source or APK.

Optional configuration:

| Variable | Purpose |
| --- | --- |
| `AI_COMPANION_DATA_DIR` | Personal persistent credentials and configuration |
| `AI_COMPANION_HOST`, `AI_COMPANION_PORT` | Listener address |
| `AI_COMPANION_TOKEN` | Explicit pairing token instead of the generated file |
| `CLAUDE_BIN`, `COPILOT_BIN`, `KIMI_BIN` | Paths to installed official runtimes |
| `GITHUB_OAUTH_CLIENT_ID` | Your GitHub OAuth App with Device Flow enabled |

Claude uses its official Agent SDK/Claude Code login, Copilot uses its SDK and
your OAuth App, and Kimi Code uses ACP. Each runtime owns its account credentials;
the Android app receives status and model choices, not those credentials.
Subscription eligibility and available models are determined by each provider.
ChatGPT is connected directly in the APK through SIWC, separately from these runtimes.

For a local stdio MCP server, create `mcp-servers.json` in the companion data
directory, with owner-only permissions:

```json
{
  "my_tools": {
    "command": "/absolute/path/to/mcp-server",
    "args": [],
    "env": {}
  }
}
```

Connect the APK to `http://PC_ADDRESS:7341/mcp/my_tools` with the pairing token.
Only locally configured commands can run; the HTTP API cannot submit a command.
The relay supports request/response tool operations. Server-initiated sampling
and elicitation are explicitly reported unavailable.

Run `npm test` and `npm run build` before using a modified companion. Automated
tests use deterministic runtimes and do not consume subscription or API credits.
