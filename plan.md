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