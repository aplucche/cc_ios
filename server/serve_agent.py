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
        self.websocket: Optional[WebSocket] = None
        self.created_at = datetime.now(UTC)
        self.is_running = False

    async def start_process(self):
        """Start the Claude Code process"""
        try:
            # Check if claude-code is available, fallback to demo shell
            claude_available = await self._check_claude_availability()
            
            if claude_available:
                # Start actual Claude Code CLI
                self.process = subprocess.Popen(
                    ["claude-code", "--interactive"],
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                    universal_newlines=True,
                    env=dict(os.environ, PYTHONUNBUFFERED="1")
                )
            else:
                # Fallback to demo shell for testing
                self.process = subprocess.Popen(
                    ["python", "-c", """
import sys
import time

print('Claude Agent Terminal Ready (Demo Mode)')
print('Agent ID: {agent_id}')
print('Type commands or send messages...')

while True:
    try:
        line = sys.stdin.readline()
        if not line or line.strip() == 'exit':
            break
        print('Echo: ' + line.strip(), flush=True)
    except (EOFError, KeyboardInterrupt):
        break
""".format(agent_id=self.agent_id)],
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                    universal_newlines=True
                )
            self.is_running = True
            
            # Start background task to read process output
            asyncio.create_task(self._read_process_output())
            
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

    async def _read_process_output(self):
        """Read output from the process and queue it for WebSocket"""
        if not self.process:
            return
            
        try:
            while self.is_running and self.process.poll() is None:
                line = self.process.stdout.readline()
                if line:
                    await self.output_queue.put(line)
                await asyncio.sleep(0.01)
        except Exception as e:
            await self.output_queue.put(f"Error reading process output: {str(e)}\n")
        finally:
            self.is_running = False

    async def send_input(self, data: str):
        """Send input to the process"""
        if self.process and self.process.stdin:
            try:
                self.process.stdin.write(data + "\n")
                self.process.stdin.flush()
            except Exception as e:
                await self.output_queue.put(f"Error sending input: {str(e)}\n")

    async def stop(self):
        """Stop the agent process"""
        self.is_running = False
        if self.process:
            try:
                self.process.terminate()
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
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
        agent.websocket = websocket
        
        # Send initial welcome message
        await websocket.send_text("Connected to Claude Agent Terminal\r\n")
        await websocket.send_text(f"Agent ID: {agent_id}\r\n")
        await websocket.send_text("Ready for commands...\r\n")
        
        # Start background task to send queued output to WebSocket
        output_task = asyncio.create_task(send_output_to_websocket(agent, websocket))
        
        # Handle incoming messages from WebSocket
        while True:
            data = await websocket.receive_text()
            await agent.send_input(data)
            
    except WebSocketDisconnect:
        if agent_id in agents:
            agents[agent_id].websocket = None
        if 'output_task' in locals() and output_task:
            output_task.cancel()
    except Exception as e:
        await websocket.send_text(f"Error: {str(e)}\r\n")
        await websocket.close()


async def send_output_to_websocket(agent: AgentProcess, websocket: WebSocket):
    """Background task to send agent output to WebSocket"""
    try:
        while agent.websocket == websocket:
            try:
                # Wait for output with timeout
                output = await asyncio.wait_for(agent.output_queue.get(), timeout=1.0)
                await websocket.send_text(output.replace('\n', '\r\n'))
            except asyncio.TimeoutError:
                # Send periodic heartbeat
                continue
            except Exception as e:
                print(f"Error sending output to websocket: {e}")
                break
    except Exception as e:
        print(f"WebSocket output task error: {e}")


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