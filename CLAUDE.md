# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

Claude Machine Launcher is an iOS app for launching and monitoring Fly.io machines. The app allows users to input Fly API credentials, configure machine settings, launch new machines, and monitor their status.

---

## Setup

```bash
brew install xcodegen xcbeautify
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

---

## Core Commands

Use the Makefile for centralized command management:

```bash
make ios-build         # Build iOS app
make ios-test          # Run iOS tests  
make server-dev        # Run FastAPI server locally (for testing)
make docker-test       # Build and test Docker container
make container-publish # Guide to publish container to GHCR
make test-integration  # Run full integration test suite
make help             # Show all available commands
```

### Legacy Commands (still work)
```bash
# Generate Xcode project (required before first build)
xcodegen generate

# Build app manually
xcodebuild -scheme ClaudeMachineLauncher -destination 'platform=iOS Simulator,name=iPhone 16' | xcbeautify --quieter
```

---

## Architecture

Feature Pod structure groups related functionality:

```
ClaudeMachineLauncher/
├── project.yml                    # XcodeGen configuration
├── Core/                          # Shared infrastructure
│   ├── FlyAPIClient.swift         # HTTP client for Fly.io API
│   └── Models/
│       ├── FlyMachine.swift       # Machine model
│       └── FlyLaunchConfig.swift  # Launch configuration
└── Features/
    └── FlyLaunch/                 # Main feature pod
        ├── FlyLaunchService.swift # API integration logic
        ├── FlyLaunchViewModel.swift # UI state management
        └── FlyLaunchView.swift    # SwiftUI interface
```

---

## Key Implementation Details

### API Integration
- Use `https://api.machines.dev/v1` for direct Fly.io API access
- POST `/apps/{app}/machines` to launch machines
- GET `/apps/{app}/machines/{machine_id}` to check status
- GET `/apps/{app}` to check if app exists
- POST `/apps` to create new apps
- Include `Authorization: Bearer {fly_api_token}` header

### API Quirks & Known Issues
- **No user endpoint**: `/v1/user` returns 404, user info not available via API
- **App creation**: Requires organization slug, use "personal" as fallback
- **Error handling**: 404 responses indicate missing apps/machines, not API errors
- **API Client**: Refactored to use generic `performRequest` method, eliminating code duplication and potential logging issues

### State Management
- ViewModels use `@Published` properties with Combine
- Keep async/await logic in Service layer, not in Views
- Use `@StateObject` for ViewModels in SwiftUI views

### Testing
- Use Swift Testing framework (`import Testing`)
- Mock services implement protocol interfaces
- Test files use `@testable import ClaudeMachineLauncher`
- High-leverage tests cover: SessionManager, TerminalViewModel, error handling
- Server tests: `python server/test_server.py` for PTY functionality
- Run iOS tests: `make ios-test`

---

## Application Workflow

### Complete Integration Flow
1. **Agents Tab**: Launch Fly.io machine using Fly.io REST API with our custom claude-agent container
2. **Claude Code Integration**: Container automatically detects and launches Claude Code CLI with API key
3. **Get Machine URL**: Launched machine endpoint is `{machine-id}.{app-name}.fly.dev`
4. **Terminal Tab**: Auto-populated with machine URL, connect via WebSocket to PTY-based Claude Code or shell
5. **Real Terminal**: Direct bidirectional communication with Claude Code CLI or bash/zsh fallback

### PTY-Based Terminal Architecture
- **Claude Code Integration**: Container auto-detects and launches `claude-code --interactive` when available
- **Intelligent Fallback**: Falls back to bash/zsh if Claude Code unavailable or fails
- **API Key Security**: Anthropic API key passed securely via environment variables from iOS Keychain
- **Full Terminal Features**: Command history, tab completion, ANSI colors, line editing
- **WebSocket Bridge**: PTY output → WebSocket → iOS, iOS input → WebSocket → PTY
- **Terminal Resizing**: iOS sends resize messages, server updates PTY window size with SIGWINCH
- **Message Buffering**: iOS buffers messages until SwiftTerm is ready, then replays

### Key Points
- **No Fly CLI needed**: App uses Fly.io REST API directly
- **Container Image**: Default is `ghcr.io/aplucche/cc_ios-claude-agent:latest` 
- **Claude Code Ready**: Container includes Claude Code CLI v1.0.77 with native installation
- **API Key Integration**: Anthropic API key automatically passed from iOS Settings to container
- **Multi-Session Architecture**: SessionManager handles multiple persistent WebSocket connections
- **Background Persistence**: Terminal sessions continue running when switching between agents
- **Smart Terminal**: Claude Code when available, shell fallback for reliability

---

## File Conventions

- Keep files under 100 lines when possible
- One responsibility per file
- Use descriptive names: `FlyLaunchService.swift` not `Service.swift`
- Group imports at top, extensions at bottom


## Logging (Toggleable Debug Strategy)

- Use a single `Logger.log(_:category:)` method for all logs
- Categories: `.ui`, `.network`, `.system`, `.agent`
- **Debug Toggle**: Set `DEBUG_LOGGING` environment variable to enable logging
- Prints to Xcode console and system log via `os_log` (when enabled)
- One-liner usage: `Logger.log("Launching", category: .network)`
- **Production Ready**: No log noise in production builds
- Optional: use `LogStore` to expose logs in-app or for Claude inspection

### Server Logging
- Server uses `debug_log()` function that checks `DEBUG_LOGGING` env var
- Same toggle mechanism as iOS client
- Clean production deployment with optional debugging