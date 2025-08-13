import asyncio
import json
import os
import pty
import signal
import subprocess
import uuid
from datetime import datetime, UTC
from typing import Dict, Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel

DEBUG = os.getenv("DEBUG_LOGGING") is not None

def debug_log(message: str):
    """Debug logging that can be toggled off"""
    if DEBUG:
        print(message)


app = FastAPI(title="Claude Agent Server", version="1.0.0")
security = HTTPBearer()

# In-memory storage for agents
agents: Dict[str, "AgentProcess"] = {}
AUTH_TOKEN = os.getenv("AUTH_TOKEN", "default-token")


class AgentProcess:
    def __init__(self, agent_id: str):
        self.agent_id = agent_id
        self.tmux_session: Optional[str] = None
        self.output_queue = asyncio.Queue()
        self.websockets: set[WebSocket] = set()
        self.created_at = datetime.now(UTC)
        self.is_running = False
        self.terminal_size = (24, 80)  # rows, cols
        self.last_output_size = 0

    async def start_process(self):
        """Start Claude Code or shell in tmux session"""
        try:
            # Check if claude is available and properly configured
            claude_available = await self._check_claude_availability()
            
            if claude_available and await self._setup_claude_config():
                # Use claude in interactive mode after proper setup
                command = "claude"
            else:
                # Use bash or fallback to sh
                shell = os.getenv("SHELL", "/bin/bash")
                if not os.path.exists(shell):
                    shell = "/bin/sh"
                command = f"{shell} -i"  # Interactive shell
            
            debug_log(f"Starting tmux session with: {command}")
            
            # Create unique tmux session name
            self.tmux_session = f"claude-{self.agent_id}"
            
            # Set up environment for Claude Code
            env = os.environ.copy()
            env.update({
                'TERM': 'xterm-256color',
                'FORCE_COLOR': '1',
                'CLICOLOR': '1'
            })
            
            # Pass through Anthropic API key and configure Claude Code
            if 'ANTHROPIC_API_KEY' in os.environ:
                env['ANTHROPIC_API_KEY'] = os.environ['ANTHROPIC_API_KEY']
                # Disable non-essential Claude Code traffic for container
                env['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] = 'true'
            
            # Start tmux session with command
            result = subprocess.run([
                "tmux", "new-session", "-d", "-s", self.tmux_session, command
            ], env=env, capture_output=True, text=True)
            
            if result.returncode != 0:
                raise Exception(f"Failed to start tmux session: {result.stderr}")
                
            self.is_running = True
            
            # Start background task to read tmux output
            asyncio.create_task(self._read_tmux_output())
            
            debug_log(f"Started tmux session: {self.tmux_session}")
                
        except Exception as e:
            debug_log(f"Agent start error: {type(e).__name__}: {str(e)}")
            if DEBUG:
                import traceback
                traceback.print_exc()
            raise HTTPException(status_code=500, detail=f"Failed to start agent: {type(e).__name__}: {str(e)}")

    async def _check_claude_availability(self) -> bool:
        """Check if claude CLI is available"""
        try:
            result = subprocess.run(
                ["claude", "--version"], 
                capture_output=True, 
                text=True, 
                timeout=5
            )
            return result.returncode == 0
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return False

    async def _setup_claude_config(self) -> bool:
        """Set up Claude Code configuration for API key authentication"""
        api_key = os.getenv("ANTHROPIC_API_KEY")
        if not api_key:
            debug_log("No ANTHROPIC_API_KEY provided, falling back to shell")
            return False
        
        try:
            # Create .claude directory if it doesn't exist
            import pathlib
            claude_dir = pathlib.Path.home() / ".claude"
            claude_dir.mkdir(exist_ok=True)
            
            # Create configuration file for headless operation
            config_file = claude_dir / "config.json"
            config_data = {
                "customApiKeyResponses": {
                    "approved": [api_key[-20:]],  # Last 20 chars for approval
                    "rejected": []
                },
                "hasCompletedOnboarding": True
            }
            
            import json
            with open(config_file, 'w') as f:
                json.dump(config_data, f, indent=2)
            
            debug_log(f"Claude Code configuration created at {config_file}")
            
            # Test if claude works with our setup
            test_result = subprocess.run(
                ["claude", "--version"],
                capture_output=True,
                text=True,
                timeout=5,
                env={**os.environ, "ANTHROPIC_API_KEY": api_key}
            )
            
            if test_result.returncode == 0:
                debug_log(f"Claude Code API key authentication ready")
                return True
            else:
                debug_log(f"Claude Code test failed: {test_result.stderr}")
                return False
                
        except Exception as e:
            debug_log(f"Claude Code setup error: {e}")
            return False

    def _set_terminal_size(self, rows=None, cols=None):
        """Set the terminal size for tmux session"""
        if rows and cols:
            self.terminal_size = (rows, cols)
        
        if not self.tmux_session:
            return
            
        try:
            rows, cols = self.terminal_size
            # Resize tmux session
            subprocess.run([
                "tmux", "resize-window", "-t", self.tmux_session, "-x", str(cols), "-y", str(rows)
            ], capture_output=True)
            debug_log(f"Terminal size set to: {cols}x{rows}")
        except Exception as e:
            debug_log(f"Could not set terminal size: {e}")

    async def _read_tmux_output(self):
        """Read output from tmux session and queue it for WebSocket"""
        if not self.tmux_session:
            return
            
        try:
            while self.is_running:
                try:
                    # Capture current tmux pane content
                    result = subprocess.run([
                        "tmux", "capture-pane", "-t", self.tmux_session, "-p"
                    ], capture_output=True, text=True, timeout=1)
                    
                    if result.returncode == 0:
                        current_output = result.stdout
                        # Send the entire output each time (tmux capture-pane gives full screen)
                        if current_output and current_output != getattr(self, '_last_full_output', ''):
                            await self.output_queue.put(current_output)
                            self._last_full_output = current_output
                    
                    # Small delay to prevent busy loop
                    await asyncio.sleep(0.1)
                    
                except subprocess.TimeoutExpired:
                    continue
                except Exception as e:
                    debug_log(f"Tmux read error: {e}")
                    break
                    
        except Exception as e:
            await self.output_queue.put(f"Error reading tmux output: {str(e)}\n")
        finally:
            self.is_running = False
            debug_log(f"Tmux output reader stopped for agent {self.agent_id}")

    async def send_input(self, data: str):
        """Send input to the tmux session"""
        if not self.tmux_session:
            return
            
        try:
            debug_log(f"Sending to tmux: {repr(data)}")
            # Send keys to tmux session
            subprocess.run([
                "tmux", "send-keys", "-t", self.tmux_session, data
            ], capture_output=True)
            debug_log(f"Sent to tmux successfully")
        except Exception as e:
            debug_log(f"Error sending input to tmux: {e}")
            await self.output_queue.put(f"Error sending input: {str(e)}\n")

    async def stop(self):
        """Stop the agent process"""
        self.is_running = False
        
        # Kill tmux session
        if self.tmux_session:
            try:
                subprocess.run([
                    "tmux", "kill-session", "-t", self.tmux_session
                ], capture_output=True)
                debug_log(f"Killed tmux session: {self.tmux_session}")
            except Exception as e:
                debug_log(f"Error killing tmux session: {e}")
            finally:
                self.tmux_session = None

    def get_status(self):
        """Get agent status"""
        return {
            "agent_id": self.agent_id,
            "is_running": self.is_running,
            "created_at": self.created_at.isoformat(),
            "tmux_session": self.tmux_session,
            "output_queue_size": self.output_queue.qsize(),
            "terminal_size": self.terminal_size,
            "connected_clients": len(self.websockets),
        }


class RunTaskRequest(BaseModel):
    prompt: str
    options: Dict = {}


def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    if credentials.credentials != AUTH_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token"
        )
    return credentials.credentials


@app.get("/")
async def health_check():
    return {"status": "ok", "message": "Claude Agent Server is running"}


@app.websocket("/agents/{agent_id}/stream")
async def websocket_endpoint(websocket: WebSocket, agent_id: str):
    await websocket.accept()
    
    try:
        # Verify auth token from query params or headers
        # In a real implementation, you'd verify the token here
        
        # Get or create agent
        if agent_id not in agents:
            agents[agent_id] = AgentProcess(agent_id)
            await agents[agent_id].start_process()
        
        agent = agents[agent_id]
        agent.websockets.add(websocket)
        
        # Send initial welcome message
        await websocket.send_text("Connected to Claude Agent Terminal\r\n")
        await websocket.send_text(f"Agent ID: {agent_id}\r\n")
        await websocket.send_text("Ready for commands...\r\n")
        
        # Start background task to send queued output to WebSocket (only if first client)
        if len(agent.websockets) == 1:
            output_task = asyncio.create_task(send_output_to_websocket(agent))
        
        # Handle incoming messages from WebSocket
        while True:
            data = await websocket.receive_text()
            
            # Check if it's a control message (JSON)
            if data.startswith("{") and data.endswith("}"):
                try:
                    import json
                    message = json.loads(data)
                    if message.get("type") == "resize":
                        rows = message.get("rows")
                        cols = message.get("cols")
                        if rows and cols:
                            agent._set_terminal_size(rows, cols)
                            debug_log(f"Terminal resized to {cols}x{rows}")
                            continue
                except json.JSONDecodeError:
                    pass  # Not JSON, treat as regular input
            
            # Regular terminal input
            await agent.send_input(data)
            
    except WebSocketDisconnect:
        if agent_id in agents:
            agents[agent_id].websockets.discard(websocket)
        if 'output_task' in locals() and output_task:
            output_task.cancel()
    except Exception as e:
        await websocket.send_text(f"Error: {str(e)}\r\n")
        await websocket.close()


async def send_output_to_websocket(agent: AgentProcess):
    """Background task to send agent output to all connected WebSockets"""
    try:
        while agent.is_running:
            try:
                # Wait for output with timeout
                output = await asyncio.wait_for(agent.output_queue.get(), timeout=1.0)
                formatted_output = output.replace('\n', '\r\n')
                
                # Send to all connected websockets
                dead_websockets = []
                for ws in list(agent.websockets):
                    try:
                        await ws.send_text(formatted_output)
                    except Exception:
                        dead_websockets.append(ws)
                
                # Remove dead websockets
                for ws in dead_websockets:
                    agent.websockets.discard(ws)
                    
            except asyncio.TimeoutError:
                continue
            except Exception as e:
                debug_log(f"Error in output queue processing: {e}")
                break
    except Exception as e:
        debug_log(f"WebSocket output task error: {e}")
    
    debug_log(f"Output task ended for agent {agent.agent_id}")


@app.get("/agents/{agent_id}/status")
async def get_agent_status(agent_id: str, token: str = Depends(verify_token)):
    if agent_id not in agents:
        raise HTTPException(status_code=404, detail="Agent not found")
    
    return agents[agent_id].get_status()


@app.post("/agents/{agent_id}/run")
async def run_task(agent_id: str, request: RunTaskRequest, token: str = Depends(verify_token)):
    if agent_id not in agents:
        agents[agent_id] = AgentProcess(agent_id)
        await agents[agent_id].start_process()
    
    agent = agents[agent_id]
    task_id = str(uuid.uuid4())
    
    # Send the prompt to the agent
    await agent.send_input(request.prompt)
    
    return {
        "task_id": task_id,
        "agent_id": agent_id,
        "status": "accepted",
        "prompt": request.prompt
    }


@app.post("/agents/{agent_id}/kill")
async def kill_agent(agent_id: str, token: str = Depends(verify_token)):
    if agent_id not in agents:
        raise HTTPException(status_code=404, detail="Agent not found")
    
    agent = agents[agent_id]
    await agent.stop()
    del agents[agent_id]
    
    return {"message": f"Agent {agent_id} killed successfully"}


@app.get("/agents")
async def list_agents(token: str = Depends(verify_token)):
    return {
        "agents": [agent.get_status() for agent in agents.values()]
    }


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)