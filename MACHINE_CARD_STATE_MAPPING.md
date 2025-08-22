# Machine Card State-View Mapping

This document defines the formal mapping between machine states and their UI representation in the simplified machine cards.

## Current Implementation Analysis

Based on the codebase analysis, here are the machine states and connection states we need to handle:

### Machine States (from Fly.io API)
- `started` - Machine is running
- `starting` - Machine is booting up
- `stopped` - Machine is stopped
- `suspended` - Machine is suspended (paused)

### Connection States (from SessionManager)
- `isConnected: true` - Terminal WebSocket is connected
- `isConnected: false` - Terminal WebSocket is not connected

### Loading States (from SessionManager)
- `loadingMachines.contains(machineId)` - Machine operation in progress

## State-to-View Mapping Table

| Machine State | Connection State | Loading State | Status Display | Button 1 | Button 2 | Card Color |
|---------------|------------------|---------------|----------------|----------|----------|------------|
| `started` | `connected` | `false` | "Running" | ⏸️ Pause | None | Green |
| `started` | `not connected` | `false` | "Connecting..." | ⏸️ Pause | None | Orange |
| `starting` | `any` | `false` | "Starting..." | Disabled "Starting" | None | Orange |
| `suspended` | `any` | `false` | "Suspended" | "Activate" | 🗑️ Delete | Gray |
| `stopped` | `any` | `false` | "Suspended" | "Activate" | 🗑️ Delete | Gray |
| `any` | `any` | `true` | `statusText` | Disabled Spinner | Disabled | Current |

## State Transition Table

| From State | User Action | To State | API Call | Loading State | Notes |
|------------|-------------|----------|----------|---------------|-------|
| `suspended/stopped` | Click "Activate" | `starting` → `started` | `startMachine()` | Yes | Also calls `onSelect()` |
| `started` | Click ⏸️ | `suspended` | `suspendMachine()` | Yes | Also disconnects session |
| `suspended/stopped` | Click 🗑️ | Removed | `deleteMachine()` | Yes | Permanently deletes machine |
| `starting` | Auto-transition | `started` | None | No | Fly.io handles transition |
| `started` + `!connected` | Auto-connect | `started` + `connected` | WebSocket connect | No | SessionManager handles |

## Button Behavior Rules

### Button 1 (Primary Action)
- **Running machines**: ⏸️ Pause icon to suspend
- **Inactive machines**: "Activate" text to start/resume  
- **Loading states**: Disabled with spinner
- **Starting machines**: Disabled "Starting" text

### Button 2 (Secondary Action)
- **Only visible** for `suspended` or `stopped` machines
- **Hidden during loading** states
- **Action**: Delete machine permanently from Fly.io

## UI Consistency Rules

1. **Status reflects combined state**: Machine state + connection state in one indicator
2. **Buttons are state-based**: Not selection-based or context-dependent
3. **Loading states**: Show current operation with spinner
4. **Color coding**: Green (ready), Orange (transitioning), Gray (inactive)
5. **Single source of truth**: Machine state determines all UI elements

## Edge Cases & Error Handling

| Scenario | Current Behavior | Desired Behavior |
|----------|------------------|------------------|
| Delete fails | Loading state clears | Show error, keep machine |
| Start fails | Loading state clears | Show error, stay suspended |
| Connection fails | Shows "Connecting..." indefinitely | Keep showing "Connecting..." (no timeout) |
| Unknown state | Shows capitalized state | Gray color, disabled buttons |

## Implementation Notes

- `statusText` combines machine state and connection into single string
- `statusColor` maps to UI color scheme
- Loading states override normal button display
- Delete button only appears when safe (suspended/stopped)
- No selection-based styling or behavior

This mapping ensures consistent, predictable UI behavior regardless of the underlying complexity.