#!/bin/bash
set -e

# Function for debug logging
debug_log() {
    if [ "${DEBUG_LOGGING:-}" ]; then
        echo "[STARTUP] $1"
    fi
}

debug_log "Starting Claude Machine Launcher container..."

# Set up Claude Code configuration if API key is provided
if [ "${ANTHROPIC_API_KEY:-}" ]; then
    debug_log "Setting up Claude Code configuration..."
    
    # Create .claude directory
    mkdir -p ~/.claude
    
    # Create config file for headless operation
    cat > ~/.claude/config.json << EOF
{
  "customApiKeyResponses": {
    "approved": ["${ANTHROPIC_API_KEY: -20}"],
    "rejected": []
  },
  "hasCompletedOnboarding": true
}
EOF
    
    # Set environment variables for Claude Code
    export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}"
    export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=true
    
    debug_log "Claude Code configuration complete"
    CLAUDE_COMMAND="claude"
else
    debug_log "No API key provided, using shell fallback"
    CLAUDE_COMMAND="bash -i"
fi

# Start Claude in main tmux session (detached)
debug_log "Starting tmux session with: ${CLAUDE_COMMAND}"

tmux new-session -d -s main -x 80 -y 24 "${CLAUDE_COMMAND}" || {
    debug_log "Failed to start tmux session, falling back to shell"
    tmux new-session -d -s main -x 80 -y 24 "bash -i"
}

debug_log "tmux session 'main' started successfully"

# Start Python server in foreground (this keeps the container running)
debug_log "Starting Python server..."
exec uvicorn serve_agent:app --host 0.0.0.0 --port 8080