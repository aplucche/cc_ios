# Claude Machine Launcher

iOS app for launching Fly.io machines and connecting via terminal.

## Current Status

The app launches Fly.io machines using the REST API and provides terminal access through WebSocket connections. Core functionality is working with recent improvements to terminal session management and UI responsiveness.

## Quick Start

```bash
make ios-build    # Build iOS app
make ios-test     # Run tests
make help         # See all commands
```

## What It Does

Launch cloud machines from iOS and connect to them through a terminal interface. The app handles machine lifecycle (start, stop, suspend) and maintains persistent terminal sessions that survive app backgrounding.

### Key Features
- Launch Fly.io machines with custom containers
- Terminal access with command history and ANSI color support
- Multiple persistent terminal sessions
- Automatic machine discovery and reconnection
- Configurable container images and machine settings

## How to Use

1. Get a Fly API token from [fly.io/user/personal_access_tokens](https://fly.io/user/personal_access_tokens)
2. Open the app and enter your API token in Settings
3. Go to Agents tab, enter an app name, and tap "Launch Machine"
4. Switch to Terminal tab to connect to your running machine
5. Use standard shell commands in your cloud environment

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