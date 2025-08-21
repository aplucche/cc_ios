# Machine Selection Debugging History

## Problem
Users selected machine A but terminal connected to machine B. Multiple machines auto-connected simultaneously causing race conditions.

## Root Cause Analysis

### Initial Hypothesis: Load Balancer Issue ❌
**Thought**: Fly.io load balancer randomly routes WebSocket connections across machines  
**Solution Attempted**: Fly-Replay headers with sticky sessions  
**Complexity**: Added routing endpoint, HTTP pre-checks, machine-specific hostnames  
**Result**: Over-engineered solution that didn't address the real problem

### Actual Root Cause: Session Management ✅  
**Real Issue**: In `SessionManager.createSession()`:
```swift
// Lines 96-101: Auto-set first session as active
if self?.activeSessionId == nil {
    self?.activeSessionId = machine.id
}

// Lines 105-109: Auto-connect ALL sessions after 5 seconds  
Task {
    try await Task.sleep(nanoseconds: 5_000_000_000) 
    await MainActor.run { [weak self] in
        self?.connectToSession(machineId: machine.id)  // ALL machines!
    }
}
```

**What Happened**: 
1. App discovers 3 machines: A, B, C
2. Creates sessions for all 3 machines
3. Sets first machine (A) as active
4. After 5 seconds, ALL 3 machines auto-connect simultaneously 
5. User sees "Connected to A" but terminal shows machine B or C

## Simple Solution ✅
Remove auto-connection logic entirely:
```swift
// Do NOT auto-set as active or auto-connect
// Let AppStateManager explicitly control which machine is selected
// Only the explicitly selected machine should connect
```

**Result**: Only user-selected machines connect. Clean, predictable behavior.

## Key Learnings

### Dead Ends Explored
1. **Machine-specific hostnames**: `{machineId}.claudeagents.fly.dev` don't exist
2. **Fly-Replay complexity**: Solving wrong problem with sophisticated routing
3. **Server-side routing**: Added unnecessary HTTP endpoints and logic

### Debugging Insights  
- **Load balancer is not the enemy**: Random routing is fine if only one connection exists
- **Race conditions in auto-connect**: Multiple simultaneous connections caused confusion
- **Session management simplicity**: Explicit user control > automatic behavior

### Architecture Principles
- **Explicit over implicit**: User selections should be explicit, not automatic
- **Simple state management**: One active session at a time, user-controlled
- **Debugging complexity**: Adding features can mask simpler underlying issues

## Quick Debug Commands
```bash
# Check what's connecting
tail -f ios-logs | grep "Connecting to session"

# Verify only selected machine connects  
tail -f ios-logs | grep "Setting active session"

# Confirm terminal shows correct machine
tail -f ios-logs | grep "TerminalViewModel received message"
```

## Final Architecture
- **Discovery**: Find all available machines
- **Selection**: User explicitly selects one machine  
- **Connection**: Only selected machine connects
- **Terminal**: Shows the machine you actually selected

**Complexity**: Minimal  
**Maintainability**: High  
**User Experience**: Predictable