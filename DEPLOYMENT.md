# Container Deployment Guide

## Overview

This guide explains how to use the Claude Agent WebSocket container with Fly.io's Machine API. The container provides terminal streaming endpoints that your iOS app connects to via WebSocket.

## Container Image

**GHCR Image**: `ghcr.io/aplucche/cc_ios-claude-agent:latest`

This container provides:
- WebSocket endpoint: `/agents/{agent_id}/stream` 
- HTTP endpoints: `/agents/{agent_id}/status`, `/kill`, `/run`
- Health check: `GET /`
- Bearer token authentication

## Development Workflow

### 1. Local Development
```bash
# Run server locally
make server-dev

# Build and test container
make docker-test
```

### 2. Publish to GHCR
```bash
# Push to main branch to trigger GitHub Actions
make container-publish
```

### 3. Use in iOS App
Reference the GHCR image in your iOS app's Fly machine creation API calls.

## Fly Machine Creation via API

### Example Machine Configuration

```json
{
  "config": {
    "image": "ghcr.io/aplucche/cc_ios-claude-agent:latest",
    "env": {
      "AUTH_TOKEN": "your-secret-token"
    },
    "services": [{
      "ports": [{
        "port": 8080,
        "handlers": ["http"]
      }],
      "protocol": "tcp",
      "internal_port": 8080
    }],
    "checks": [{
      "type": "http",
      "port": 8080,
      "method": "GET",
      "path": "/",
      "interval": "30s",
      "timeout": "10s"
    }]
  },
  "region": "ord",
  "skip_launch": false
}
```

### API Call Example

```bash
# Create machine via API
curl -X POST "https://api.machines.dev/v1/apps/{your-fly-org}/machines" \
  -H "Authorization: Bearer $FLY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @machine-config.json
```

### iOS App Integration

In your iOS app's `FlyLaunchService.swift`, use:

```swift
let launchConfig = FlyLaunchConfig(
    image: "ghcr.io/aplucche/cc_ios-claude-agent:latest",
    env: ["AUTH_TOKEN": "your-secret-token"],
    // ... other config
)
```

## Container Endpoints

### WebSocket Streaming
```
wss://your-machine.fly.dev/agents/{agent_id}/stream
Authorization: Bearer your-token
```

### HTTP Management
```bash
# Health check
GET https://your-machine.fly.dev/

# List agents
GET https://your-machine.fly.dev/agents
Authorization: Bearer your-token

# Agent status
GET https://your-machine.fly.dev/agents/{agent_id}/status
Authorization: Bearer your-token

# Start task
POST https://your-machine.fly.dev/agents/{agent_id}/run
Authorization: Bearer your-token
```

## Environment Variables

- `AUTH_TOKEN` - Bearer token for API authentication (required)
- `PORT` - Server port (default: 8080)
- `HOST` - Server host (default: 0.0.0.0)

## Machine Specifications

**Recommended Settings:**
- **CPU**: 1 shared CPU
- **Memory**: 256MB-512MB
- **Region**: Choose based on user location
- **Auto-stop**: Enabled for cost optimization

## Monitoring & Debugging

```bash
# View machine logs
fly machine logs {machine_id}

# SSH into machine
fly machine exec {machine_id} -- /bin/bash

# Check machine status
curl https://api.machines.dev/v1/apps/{org}/machines/{machine_id}
```

## Security Notes

- Always use secure random tokens for `AUTH_TOKEN`
- Store tokens securely in your iOS app (Keychain)
- Consider implementing token rotation
- Use HTTPS/WSS in production (automatic with Fly.io)