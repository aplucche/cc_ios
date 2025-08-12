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
        self.process_pid: Optional[int] = None
        self.pty_fd: Optional[int] = None
        self.output_queue = asyncio.Queue()
        self.input_queue = asyncio.Queue()
        self.websockets: set[WebSocket] = set()
        self.created_at = datetime.now(UTC)
        self.is_running = False
        self.terminal_size = (24, 80)  # rows, cols

    async def start_process(self):
        """Start a real shell using PTY"""
        try:
            # Check if claude-code is available, fallback to shell
            claude_available = await self._check_claude_availability()
            
            if claude_available:
                command = ["claude-code", "--interactive"]
            else:
                # Use bash or fallback to sh
                shell = os.getenv("SHELL", "/bin/bash")
                if not os.path.exists(shell):
                    shell = "/bin/sh"
                command = [shell, "-i"]  # Interactive shell
            
            debug_log(f"Starting shell: {' '.join(command)}")
            
            # Create PTY and fork process
            self.pty_fd, child_fd = pty.openpty()
            self.process_pid = os.fork()
            
            if self.process_pid == 0:
                # Child process - become shell
                os.close(self.pty_fd)
                os.setsid()
                os.dup2(child_fd, 0)  # stdin
                os.dup2(child_fd, 1)  # stdout  
                os.dup2(child_fd, 2)  # stderr
                os.close(child_fd)
                
                # Set terminal size
                self._set_terminal_size()
                
                # Set environment for better shell experience
                env = os.environ.copy()
                env.update({
                    'TERM': 'xterm-256color',
                    'PS1': '\\[\\033[01;32m\\]\\u@claude-agent\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ ',
                    'FORCE_COLOR': '1',
                    'CLICOLOR': '1'
                })
                
                os.execvpe(command[0], command, env)
            else:
                # Parent process
                os.close(child_fd)
                self.is_running = True
                
                # Start background task to read PTY output
                asyncio.create_task(self._read_pty_output())
                
                debug_log(f"Started shell process PID: {self.process_pid}")
                
        except Exception as e:
            debug_log(f"Agent start error: {type(e).__name__}: {str(e)}")
            if DEBUG:
                import traceback
                traceback.print_exc()
            raise HTTPException(status_code=500, detail=f"Failed to start agent: {type(e).__name__}: {str(e)}")

    async def _check_claude_availability(self) -> bool:
        """Check if claude-code CLI is available"""
        try:
            result = subprocess.run(
                ["claude-code", "--version"], 
                capture_output=True, 
                text=True, 
                timeout=5
            )
            return result.returncode == 0
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return False

    def _set_terminal_size(self, rows=None, cols=None):
        """Set the terminal size using termios"""
        if rows and cols:
            self.terminal_size = (rows, cols)
        
        try:
            import termios
            import struct
            import fcntl
            rows, cols = self.terminal_size
            
            # Set terminal size on PTY
            if self.pty_fd:
                size = struct.pack("HHHH", rows, cols, 0, 0)
                fcntl.ioctl(self.pty_fd, termios.TIOCSWINSZ, size)
                
                # Send SIGWINCH to notify shell of size change
                if self.process_pid:
                    os.kill(self.process_pid, signal.SIGWINCH)
                    
            debug_log(f"Terminal size set to: {cols}x{rows}")
        except Exception as e:
            debug_log(f"Could not set terminal size: {e}")

    async def _read_pty_output(self):
        """Read output from the PTY and queue it for WebSocket"""
        if not self.pty_fd:
            return
            
        try:
            # Make PTY non-blocking
            import fcntl
            flags = fcntl.fcntl(self.pty_fd, fcntl.F_GETFL)
            fcntl.fcntl(self.pty_fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)
            
            while self.is_running:
                try:
                    # Use asyncio to read from PTY without blocking
                    data = await asyncio.get_event_loop().run_in_executor(
                        None, self._read_pty_data
                    )
                    if data:
                        await self.output_queue.put(data)
                    else:
                        # Small delay to prevent busy loop
                        await asyncio.sleep(0.01)
                except Exception as e:
                    debug_log(f"PTY read error: {e}")
                    break
                    
        except Exception as e:
            await self.output_queue.put(f"Error reading PTY output: {str(e)}\n")
        finally:
            self.is_running = False
            debug_log(f"PTY output reader stopped for agent {self.agent_id}")

    def _read_pty_data(self):
        """Read data from PTY (blocking call - run in executor)"""
        try:
            return os.read(self.pty_fd, 1024).decode('utf-8', errors='ignore')
        except (OSError, BlockingIOError):
            return None

    async def send_input(self, data: str):
        """Send input to the PTY"""
        if self.pty_fd:
            try:
                debug_log(f"Sending to PTY: {repr(data)}")
                os.write(self.pty_fd, data.encode('utf-8'))
                debug_log(f"Sent to PTY successfully")
            except Exception as e:
                debug_log(f"Error sending input to PTY: {e}")
                await self.output_queue.put(f"Error sending input: {str(e)}\n")

    async def stop(self):
        """Stop the agent process"""
        self.is_running = False
        
        # Close PTY
        if self.pty_fd:
            try:
                os.close(self.pty_fd)
                self.pty_fd = None
            except Exception as e:
                debug_log(f"Error closing PTY: {e}")
        
        # Kill process
        if self.process_pid:
            try:
                os.kill(self.process_pid, signal.SIGTERM)
                await asyncio.sleep(1.0)
                try:
                    os.kill(self.process_pid, 0)
                    os.kill(self.process_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            except Exception as e:
                debug_log(f"Error stopping process: {e}")
            finally:
                self.process_pid = None

    def get_status(self):
        """Get agent status"""
        return {
            "agent_id": self.agent_id,
            "is_running": self.is_running,
            "created_at": self.created_at.isoformat(),
            "process_pid": self.process_pid,
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