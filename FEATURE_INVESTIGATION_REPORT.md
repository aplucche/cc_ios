# Claude Code Integration Investigation Report

## 1. Context & Evolution

**Original Goal**: iOS app for launching Fly.io machines with basic terminal access  
**Current Goal**: Full Claude Code CLI integration with iOS app

**Key Requirements**:
- Launch Fly machines with Claude Code pre-installed via REST API
- Real-time terminal streaming with Claude Code interactive sessions
- Secure API key flow from iOS Keychain to container environment
- Intelligent fallback to shell when Claude Code unavailable
- Complete programmatic deployment (no CLI dependencies)

## 2. Current Status: SIMPLIFIED DIRECT TMUX INTEGRATION COMPLETE

### **Architecture Evolution: Nested Session Problem Solved**

#### **Problem Identified: Nested tmux Sessions**
- **Issue**: Server was creating tmux sessions within existing tmux environment
- **Symptom**: Nested session warnings preventing Claude Code access
- **Root Cause**: Complex session creation logic caused session isolation

#### **Solution: Direct tmux Integration**
- **Container Startup**: Claude Code starts directly in main tmux session at boot
- **Server Attachment**: Python server attaches to existing main session instead of creating new ones
- **Simplified Flow**: Container → tmux main session → Claude Code, Server attaches via WebSocket bridge

### **Current Implementation**

#### **Container Architecture (`startup.sh` + `Dockerfile`)**
- **Startup Sequence**: Container boots → tmux main session with Claude Code → Python server starts
- **Claude Code v1.0.77**: Native installation via `curl -fsSL https://claude.ai/install.sh | bash`
- **Configuration**: API key setup handled at container startup
- **Fallback**: Graceful fallback to `bash -i` if Claude Code unavailable
- **Session**: Single `main` tmux session shared across all connections

#### **Python Server (`serve_agent.py`)**
- **Simplified Logic**: Server attaches to existing main session instead of creating new ones
- **Session Management**: AgentProcess uses `tmux_session = "main"` 
- **WebSocket Bridge**: Bidirectional communication via `tmux send-keys` and `tmux capture-pane`
- **Status Tracking**: Agent status reports `"architecture": "direct_tmux_attach"`

#### **iOS App Integration**
- **API Key Flow**: iOS Keychain → Environment Variables → Claude Code CLI
- **Connection**: WebSocket to `/agents/{agent_id}/stream` endpoint
- **Session Persistence**: tmux session continues running when iOS disconnects
- **Terminal Control**: Full terminal features including resize, colors, input handling
## 3. Testing Results

### **Container Testing**
- **Build**: Successfully builds Claude Code v1.0.77 in container
- **Startup**: Container properly starts main tmux session with Claude Code
- **Health Check**: HTTP endpoint responds correctly
- **API**: Authentication and agent management endpoints functional
- **tmux Integration**: All tmux commands (list-sessions, send-keys, capture-pane) working

### **WebSocket Communication**
- **Connection**: iOS app successfully connects to WebSocket endpoint
- **Session Attachment**: Server attaches to main tmux session without creating new ones  
- **Command Execution**: Input/output flows correctly through tmux bridge
- **Terminal Features**: Resize, colors, and interactive prompts functional

## 4. Key Files & Implementation

### **Container Files**
- `server/Dockerfile`: Container build with tmux + Claude Code installation
- `server/startup.sh`: Startup script that creates main tmux session then starts Python server
- `server/serve_agent.py`: Simplified WebSocket server that attaches to existing sessions

### **iOS Integration**
- `SessionManager.swift`: Multi-connection WebSocket management
- `TerminalViewModel.swift`: SwiftTerm integration and terminal I/O
- `AgentStreamingService.swift`: WebSocket communication with auth and reconnection
- `FlyLaunchViewModel.swift`: Machine launching with API key passthrough

### **Configuration**
- `machine-config.json`: Fly.io machine settings
- `Makefile`: Build and test automation
- `CLAUDE.md`: Project documentation

## 5. Resolution Summary

### **Problem**: Nested tmux sessions caused warnings and blocked Claude Code access
### **Solution**: Simplified architecture with direct tmux integration
### **Result**: Claude Code accessible via iOS app with no session conflicts

**Current Status**: Direct tmux integration implemented and tested. Container builds and deploys Claude Code v1.0.77 in main tmux session. iOS app connects via WebSocket bridge with full terminal functionality.

---

**Last Updated**: August 13, 2025  
**Architecture**: Direct tmux integration - production ready