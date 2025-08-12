# Claude Agent Server

FastAPI server providing PTY-based terminal access with Claude Code integration via WebSocket.

## Features

- **Claude Code Integration**: Auto-detects and launches Claude Code CLI v1.0.77 when available
- **Intelligent Fallback**: Falls back to bash/zsh if Claude Code unavailable or fails
- **API Key Security**: Receives Anthropic API key from iOS app via environment variables
- **Real PTY Terminal**: Actual Claude Code or bash/zsh shells via Python pty module
- **WebSocket Streaming**: Bidirectional communication between iOS and terminal
- **Terminal Features**: Command history, tab completion, ANSI colors, resize handling
- **Multi-Client Support**: Multiple iOS devices can connect to same shell session
- **Agent Management**: HTTP endpoints for lifecycle management
- **Bearer Token Auth**: Secure API access

## API Endpoints

### WebSocket
- `WS /agents/{agent_id}/stream` - Bidirectional streaming with agent

### HTTP
- `GET /agents/{agent_id}/status` - Get agent status
- `POST /agents/{agent_id}/run` - Start one-off task
- `POST /agents/{agent_id}/kill` - Stop agent process
- `GET /agents` - List all agents

## Development

```bash
# Install dependencies
pip install fastapi uvicorn websockets

# Run locally
python serve_agent.py

# Build container
docker build -t claude-agent .

# Run container
docker run -p 8080:8080 -e AUTH_TOKEN=your-secret-token claude-agent
```

## Deployment

### iOS App Integration
This container is launched **automatically by the iOS app** via Fly.io REST API:

1. **iOS Agents Tab**: Launches machine with this container image
2. **Container URL**: `{machine-id}.{app-name}.fly.dev`
3. **iOS Terminal Tab**: Connects to WebSocket endpoint for real-time interaction

### Manual Deployment (Optional)
```bash
# Deploy from container registry (if needed for testing)
fly deploy --image ghcr.io/aplucche/cc_ios-claude-agent:latest

# Set environment variables
fly secrets set AUTH_TOKEN=your-secret-token
```

### Environment Variables
- `AUTH_TOKEN` - Bearer token for API authentication (default: "default-token")
- `ANTHROPIC_API_KEY` - API key for Claude Code authentication (passed from iOS app)
- `DEBUG_LOGGING` - Enable debug logging (optional)
- `HOST` - Server host (default: "0.0.0.0") 
- `PORT` - Server port (default: 8080)

### Claude Code Integration Details
- **Installation**: Uses native Claude Code installer (`curl -fsSL https://claude.ai/install.sh | bash`)
- **Detection**: Server checks for `claude-code --version` availability at startup
- **Launch Command**: `claude-code --interactive` when available, falls back to shell
- **API Key**: Automatically configured via `ANTHROPIC_API_KEY` environment variable
- **Fallback**: Graceful degradation to bash/zsh if Claude Code fails