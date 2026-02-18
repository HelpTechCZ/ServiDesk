# ServiDesk

Open-source remote desktop & support tool. Self-hosted relay server with native Windows and macOS agents.

## Features

- **Remote desktop** with real-time screen sharing (MJPEG + delta encoding)
- **End-to-end encryption** (ECDH key exchange + AES-GCM)
- **Unattended access** with password protection
- **File transfer** between admin and client
- **Chat** during remote sessions
- **Multi-monitor** support with live switching
- **Auto-update** mechanism for Windows agent
- **Device registry** with persistent storage
- **Hardware info** collection (CPU, RAM, disks, OS)
- **Self-hosted** relay server on any Node.js host or Docker

## Architecture

```
+------------------+       WSS        +------------------+       WSS        +------------------+
|  Windows/macOS   | <--------------> |   Relay Server   | <--------------> |   macOS Viewer    |
|     Agent        |                  |   (Node.js)      |                  |   (Admin app)     |
+------------------+                  +------------------+                  +------------------+
```

- **Agent** runs on the client machine, captures screen, injects input
- **Relay Server** routes WebSocket messages between agents and viewers
- **Viewer** is the admin app for connecting to agents

## Components

| Component | Technology | Path |
|-----------|-----------|------|
| Relay Server | Node.js, WebSocket | `relay-server/` |
| Windows Agent | C# .NET 8, WPF | `windows-agent/` |
| macOS Agent | Swift, SwiftUI | `mac-agent/` |
| macOS Viewer | Swift, SwiftUI | *closed source* |

## Quick Start

### Relay Server

```bash
cd relay-server
cp env.example .env
# Edit .env – set your own ADMIN_TOKEN
npm install
node src/index.js
```

Or with Docker:

```bash
cd relay-server
cp env.example .env
docker compose up -d --build
```

### Windows Agent

Requires .NET 8 SDK and Windows.

```bash
cd windows-agent
dotnet build
dotnet run --project RemoteAgent.GUI
```

### macOS Viewer

Open `mac-viewer/RemoteViewer.xcodeproj` in Xcode and build.

### macOS Agent

Open `mac-agent/ServiDeskAgent.xcodeproj` in Xcode and build.

## Configuration

### Relay Server

Configuration via environment variables (`.env` file):

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8090` | HTTP/WS port |
| `ADMIN_TOKEN` | – | SHA-256 token for admin authentication |
| `SESSION_TIMEOUT_MS` | `3600000` | Max session duration (1h) |
| `MAX_ACTIVE_SESSIONS` | `10` | Concurrent session limit |

### Agent

Agent config is stored in `%ProgramData%/RemoteAgent/config.json` (Windows) or `~/Library/Application Support/ServiDeskAgent/config.json` (macOS).

Key settings:
- `relayServerUrl` – WebSocket URL of your relay server
- `agentId` – Auto-generated unique ID

## Deployment

See [SYNOLOGY-DEPLOY.md](relay-server/SYNOLOGY-DEPLOY.md) for detailed Synology NAS deployment guide.

For any Docker host:

```bash
docker compose up -d --build
# Set up reverse proxy (nginx/caddy) with TLS termination
# Point your domain to the server
```

## Security

- All remote sessions use **E2E encryption** (ECDH + AES-256-GCM)
- Admin authentication via **SHA-256 token**
- Unattended access passwords are **SHA-256 hashed** (never stored in plaintext)
- Relay server only routes encrypted binary data – cannot read screen content

## License

[MIT](LICENSE) – free for personal and commercial use.

## Contributing

Contributions are welcome! Please open an issue or pull request.

---

Made by [HelpTech.cz](https://helptech.cz)
