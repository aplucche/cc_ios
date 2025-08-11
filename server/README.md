# Claude Agent Server

FastAPI server that provides WebSocket streaming interface for Claude agents running in containers.

## Features

- **WebSocket Streaming**: Real-time bidirectional communication with agents
- **Agent Management**: HTTP endpoints for agent lifecycle management
- **Bearer Token Auth**: Secure API access
- **ANSI Compatible**: Output formatted for terminal emulators like SwiftTerm

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

### Fly.io
```bash
# Deploy from container registry
fly deploy --image ghcr.io/your-username/cc_ios_test/claude-agent:latest

# Set environment variables
fly secrets set AUTH_TOKEN=your-secret-token
```

### Environment Variables
- `AUTH_TOKEN` - Bearer token for API authentication (default: "default-token")
- `HOST` - Server host (default: "0.0.0.0") 
- `PORT` - Server port (default: 8080)