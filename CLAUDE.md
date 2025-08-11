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
make server-dev        # Run FastAPI server locally
make docker-test       # Build and test Docker container
make container-publish # Guide to publish container to GHCR
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

---

## Development Phases

1. **UI Shell**: Basic form with API key, image, app name inputs
2. **Launch Logic**: Implement Fly.io machine creation API call  
3. **Status View**: Display machine ID, state, region from API response
4. **Claude Integration**: Add Claude API key field for future automation

---

## File Conventions

- Keep files under 100 lines when possible
- One responsibility per file
- Use descriptive names: `FlyLaunchService.swift` not `Service.swift`
- Group imports at top, extensions at bottom


## Logging (Minimal Strategy)

- Use a single `Logger.log(_:category:)` method for all logs
- Categories: `.ui`, `.network`, `.system`, `.agent`
- Prints to Xcode console and system log via `os_log`
- One-liner usage: `Logger.log("Launching", category: .network)`
- Optional: use `LogStore` to expose logs in-app or for Claude inspection