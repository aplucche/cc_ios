# Claude Machine Launcher

iOS terminal app for launching and connecting to Fly.io machines with shell access.

## Quick Start

```bash
# Use centralized commands via Makefile
make ios-build    # Build iOS app
make ios-test     # Run tests
make help         # See all commands
```

## Features

### Terminal Features
- **PTY-based Shell**: Connect to bash/zsh running in Fly.io containers
- **Terminal Features**: Command history, tab completion, ANSI colors, line editing
- **SwiftTerm Integration**: Terminal emulation with Unicode support

### Cloud Infrastructure
- **Fly.io Integration**: Launch machines using REST API (no CLI needed)
- **Multi-Session Management**: Handle multiple persistent terminal connections
- **Container Deployment**: Deploy containers with public hostnames
- **Container**: Custom `ghcr.io/aplucche/cc_ios-claude-agent:latest`

### iOS Architecture  
- **Feature Pods**: Clean separation (Agents, Terminal, Settings)
- **Combine/SwiftUI**: Reactive architecture with proper state management
- **WebSocket Bridge**: Bidirectional communication with heartbeat
- **Message Buffering**: Ensures no terminal output is lost during view transitions

## Usage

1. **Get Fly API Token**: [fly.io/user/personal_access_tokens](https://fly.io/user/personal_access_tokens)
2. **Launch Machine**: Enter API token and app name, tap "Launch Machine"
3. **Terminal Access**: Switch to Terminal tab for full shell experience
4. **Real Commands**: Run `ls`, `cd`, `vim`, `htop`, `curl`, etc. in your cloud container

## Development

```bash
# Essential commands
make ios-build              # Build iOS app
make ios-test               # Run iOS tests  
make server-dev             # Test server locally
make docker-test            # Build and test container
make test-integration       # Full integration tests

# Debug logging (optional)
export DEBUG_LOGGING=1      # Enable detailed logs
```