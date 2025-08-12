import asyncio
import json
import os
import subprocess
import uuid
from datetime import datetime, UTC
from typing import Dict, Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel


app = FastAPI(title="Claude Agent Server", version="1.0.0")
security = HTTPBearer()

# In-memory storage for agents
agents: Dict[str, "AgentProcess"] = {}
AUTH_TOKEN = os.getenv("AUTH_TOKEN", "default-token")


class AgentProcess:
    def __init__(self, agent_id: str):
        self.agent_id = agent_id
        self.process: Optional[subprocess.Popen] = None
        self.output_queue = asyncio.Queue()
        self.input_queue = asyncio.Queue()
        self.websockets: set[WebSocket] = set()
        self.created_at = datetime.now(UTC)
        self.is_running = False

    async def start_process(self):
        """Start the Claude Code process using async subprocess"""
        try:
            # Check if claude-code is available, fallback to demo shell
            claude_available = await self._check_claude_availability()
            
            if claude_available:
                # Start actual Claude Code CLI with async subprocess
                self.process = await asyncio.create_subprocess_exec(
                    "claude-code", "--interactive",
                    stdin=asyncio.subprocess.PIPE,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.STDOUT,
                    env=dict(os.environ, PYTHONUNBUFFERED="1")
                )
            else:
                # Fallback to demo shell for testing with async subprocess
                demo_code = f"""
import sys
import time

print('Claude Agent Terminal Ready (Demo Mode)', flush=True)
print('Agent ID: {self.agent_id}', flush=True)
print('Type commands or send messages...', flush=True)
print('claude> ', end='', flush=True)

while True:
    try:
        line = sys.stdin.readline()
        if not line:
            break
        line = line.strip()
        if line == 'exit':
            break
        if line:
            print('\\r\\nEcho: ' + line, flush=True)
        print('claude> ', end='', flush=True)
    except (EOFError, KeyboardInterrupt):
        break
        
print('\\r\\nDemo session ended.', flush=True)
"""
                self.process = await asyncio.create_subprocess_exec(
                    "python", "-u", "-c", demo_code,
                    stdin=asyncio.subprocess.PIPE,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.STDOUT,
                    env=dict(os.environ, PYTHONUNBUFFERED="1")
                )
            
            self.is_running = True
            
            # Start background task to read process output asynchronously
            asyncio.create_task(self._read_process_output_async())
            
        except Exception as e:
            print(f"Agent start error: {type(e).__name__}: {str(e)}")
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

    async def _read_process_output_async(self):
        """Read output from the async process and queue it for WebSocket"""
        if not self.process:
            return
            
        try:
            while self.is_running and self.process.returncode is None:
                line = await self.process.stdout.readline()
                if not line:  # EOF
                    break
                decoded_line = line.decode(errors="ignore")
                await self.output_queue.put(decoded_line)
        except Exception as e:
            await self.output_queue.put(f"Error reading process output: {str(e)}\n")
        finally:
            self.is_running = False

    async def send_input(self, data: str):
        """Send input to the async process"""
        if self.process and self.process.stdin:
            try:
                print(f"Sending to subprocess: {repr(data)}")
                message = (data + "\n").encode()
                self.process.stdin.write(message)
                await self.process.stdin.drain()
                print(f"Sent and drained to subprocess")
            except Exception as e:
                print(f"Error sending input to subprocess: {e}")
                await self.output_queue.put(f"Error sending input: {str(e)}\n")

    async def stop(self):
        """Stop the agent process"""
        self.is_running = False
        if self.process:
            try:
                self.process.terminate()
                try:
                    await asyncio.wait_for(self.process.wait(), timeout=5.0)
                except asyncio.TimeoutError:
                    self.process.kill()
                    await self.process.wait()
            except Exception as e:
                print(f"Error stopping process: {e}")
            self.process = None

    def get_status(self):
        """Get agent status"""
        return {
            "agent_id": self.agent_id,
            "is_running": self.is_running,
            "created_at": self.created_at.isoformat(),
            "process_pid": self.process.pid if self.process else None,
            "output_queue_size": self.output_queue.qsize(),
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
                    except Exception as e:
                        print(f"Error sending to websocket: {e}")
                        dead_websockets.append(ws)
                
                # Remove dead websockets
                for ws in dead_websockets:
                    agent.websockets.discard(ws)
                    
            except asyncio.TimeoutError:
                # Continue waiting for output
                continue
            except Exception as e:
                print(f"Error in output queue processing: {e}")
                break
    except Exception as e:
        print(f"WebSocket output task error: {e}")
    
    print(f"Output task ended for agent {agent.agent_id}")


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