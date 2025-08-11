# 🚀 Claude Machine Launcher (iOS)

A minimal iOS app to launch and monitor Fly.io machines, optimized for Claude Code development loops.

---

## 📌 Broad Strokes – High-Leverage iOS Project Tips

- ✅ Use **Feature Pod structure** (`Features/FlyLaunch/`) to group model, viewmodel, service, and view
- ✅ Keep all API-facing logic inside a `FlyLaunchService.swift`
- ✅ Inject the Fly API key at runtime (text input is fine for now)
- ✅ Define a simple model (`FlyMachine`) to hold ID, config, and status
- ✅ ViewModel handles `.launch()`, `.fetchStatus()`, and tracks loading/error state
- ✅ Keep UI minimal: one screen with config input + launch button + machine status readout
- ✅ Avoid backend for now — go direct from iOS to `https://api.machines.dev`
- ✅ Use `@Published` and Combine for state flow; no async/await inside views
- ✅ Keep each Swift file < 100 lines and purpose-specific (Claude-friendly)
- ✅ Include a `CLAUDE.md` with agent-specific edit notes ("You may modify only FlyLaunch/")

---

## 🧭 Minimal Phases to MVP

### Phase 1 – UI Shell
- Single SwiftUI screen with text fields for:
  - Fly API Key
  - Image
  - App Name
- Button: `Launch Machine`

### Phase 2 – Launch Logic
- Call Fly API (`POST /apps/{app}/machines`)
- Display success/fail message

### Phase 3 – Status View
- Show live response:
  - Machine ID
  - State (started, stopped, etc.)
  - Region
- (Optional: `fetchStatus()` to query latest info)

### Phase 4 – Claude Control Ready
- Add field for Claude API key
- Store or stream Claude config (TBD)

---

## ✅ Early Build Check

Before implementing launch logic:

- [ ] App builds in simulator with stub `FlyLaunchView.swift` visible
- [ ] No crashes on launch or button press
- [ ] Runtime input for Fly API key is working (e.g. captured in `@State`)
- [ ] ViewModel can receive and print config on button tap

> Once these are in place, Claude or dev can proceed with wiring the service layer and parsing the Fly.io response.

---


## VM Terminal Streaming Spec

## GOAL
Run inside a Fly.io VM and expose a minimal API to let an iOS app interact with a live Claude agent in a "terminal-like" session.
Support multiple agents in the same VM if needed.

## REQUIREMENTS
- Serve over HTTPS on port 8080 (Fly maps to 443)
- Auth via static Bearer token passed in iOS config
- ANSI-formatted output compatible with SwiftTerm
- Low memory + minimal dependencies (FastAPI + uvicorn ok)

## ENDPOINTS

### 1. WebSocket: `/agents/{agent_id}/stream`
- Bidirectional
- VM → iOS: send ANSI output chunks from the agent in near-real time
- iOS → VM: send user input (lines/keystrokes) to agent

### 2. HTTP POST: `/agents/{agent_id}/run`
- Start a one-off task (optional, for non-interactive use)
- Request: JSON `{ "prompt": "...", "options": {...} }`
- Response: task accepted + ID

### 3. HTTP GET: `/agents/{agent_id}/status`
- Returns agent uptime, current task state, queue length

### 4. HTTP POST: `/agents/{agent_id}/kill`
- Stops agent process, cleans up resources

## INTERNALS
- Each agent has:
    - Output queue → consumed by WebSocket send loop
    - Input handler → receives keystrokes/lines from WebSocket
    - Claude Code core loop processing tasks
- Multiple agents = multiple queues + loops in memory

## NOTES
- Keep output stream small; send only incremental output (no full replay)
- Use pty-like buffering so SwiftTerm behaves like a terminal
- Log significant events to stdout for Fly logs
- Fail gracefully if an agent ID doesn’t exist