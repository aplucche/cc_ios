# Claude Agent Server

FastAPI server providing PTY-based terminal access via WebSocket.

## Features

- **Real PTY Terminal**: Actual bash/zsh shells via Python pty module
- **WebSocket Streaming**: Bidirectional communication between iOS and shell
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
- `HOST` - Server host (default: "0.0.0.0") 
- `PORT` - Server port (default: 8080)