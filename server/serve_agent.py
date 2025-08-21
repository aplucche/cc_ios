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
            # First setup git repository if git environment variables are present
            await self._setup_git_repository()
            
            # First setup Claude configuration (needed before availability check)
            config_success = await self._setup_claude_config()
            
            # Then check if claude-code is available after configuration
            claude_available = False
            if config_success:
                claude_available = await self._check_claude_availability()
            
            if claude_available:
                # Use claude in interactive mode after proper setup
                command = ["claude"]
                debug_log("Using Claude Code CLI")
            else:
                # Use bash or fallback to sh
                shell = os.getenv("SHELL", "/bin/bash")
                if not os.path.exists(shell):
                    shell = "/bin/sh"
                command = [shell, "-i"]  # Interactive shell
                debug_log(f"Falling back to shell: {shell}")
            
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
                
                # Pass through Anthropic API key and configure Claude Code
                if 'ANTHROPIC_API_KEY' in os.environ:
                    env['ANTHROPIC_API_KEY'] = os.environ['ANTHROPIC_API_KEY']
                    # Use individual environment variables instead of CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                    # which has known hanging issues in v1.0.45+
                    env['DISABLE_AUTOUPDATER'] = '1'
                    env['DISABLE_TELEMETRY'] = '1' 
                    env['DISABLE_ERROR_REPORTING'] = '1'
                    env['DISABLE_BUG_COMMAND'] = '1'
                
                # Pass through git environment variables
                for git_var in ['GIT_USERNAME', 'GIT_TOKEN', 'GIT_REPO_URL', 'GIT_BRANCH']:
                    if git_var in os.environ:
                        env[git_var] = os.environ[git_var]
                
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
        """Check if claude CLI is available"""
        try:
            debug_log("Testing Claude Code availability...")
            result = subprocess.run(
                ["claude", "--version"], 
                capture_output=True, 
                text=True, 
                timeout=5
            )
            if result.returncode == 0:
                debug_log(f"Claude Code available: {result.stdout.strip()}")
                return True
            else:
                debug_log(f"Claude Code failed: {result.stderr}")
                return False
        except subprocess.TimeoutExpired:
            debug_log("Claude Code timed out (likely onboarding prompt)")
            return False
        except FileNotFoundError:
            debug_log("Claude Code not found in PATH")
            return False

    async def _setup_claude_config(self) -> bool:
        """Set up Claude Code configuration to bypass onboarding - TEMPORARILY DISABLED"""
        debug_log("Claude Code configuration setup is TEMPORARILY DISABLED for testing")
        return False
        
        # DISABLED CODE BELOW - uncomment to re-enable Claude config setup
        """
        api_key = os.getenv("ANTHROPIC_API_KEY")
        if not api_key:
            debug_log("No ANTHROPIC_API_KEY provided, skipping Claude Code setup")
            return False
        
        debug_log("Starting Claude Code configuration setup...")
        
        try:
            # Create .claude directory if it doesn't exist
            import pathlib
            claude_dir = pathlib.Path.home() / ".claude"
            claude_dir.mkdir(exist_ok=True)
            
            # Create API key helper script (use /tmp for write permissions)
            helper_script = pathlib.Path("/tmp/anthropic_key_helper.sh")
            with open(helper_script, 'w') as f:
                f.write('#!/bin/sh\necho "$ANTHROPIC_API_KEY"\n')  # Use sh instead of bash
            helper_script.chmod(0o755)
            debug_log(f"Created API key helper at {helper_script}")
            
            # Approach 1: Create complete configuration file to bypass onboarding
            claude_config = claude_dir / "claude.json"
            config_data = {
                "hasCompletedOnboarding": True,
                "theme": "dark",
                "apiKeyHelper": str(helper_script),
                "defaultMode": "acceptEdits",
                # Also try direct API key approach as fallback
                "apiKey": api_key
            }
            
            import json
            with open(claude_config, 'w') as f:
                json.dump(config_data, f, indent=2)
            
            debug_log(f"Claude Code configuration created at {claude_config}")
            
            # Approach 2: Also create settings.json for redundancy
            settings_file = claude_dir / "settings.json"
            settings_data = {
                "hasCompletedOnboarding": True,
                "theme": "dark",
                "apiKeyHelper": str(helper_script)
            }
            
            with open(settings_file, 'w') as f:
                json.dump(settings_data, f, indent=2)
            
            debug_log(f"Claude Code settings created at {settings_file}")
            
            # Verify files were created properly
            debug_log(f"Config file exists: {claude_config.exists()}")
            debug_log(f"Settings file exists: {settings_file.exists()}")
            debug_log(f"Helper script exists: {helper_script.exists()}")
            
            # Approach 3: Try config commands as backup
            try:
                subprocess.run(["claude", "config", "set", "hasCompletedOnboarding", "true"], 
                              check=True, capture_output=True, timeout=5)
                subprocess.run(["claude", "config", "set", "theme", "dark"], 
                              check=True, capture_output=True, timeout=5)
                debug_log("Claude config commands executed successfully")
            except subprocess.CalledProcessError as e:
                debug_log(f"Config commands failed (expected): {e}")
            
            # Test if claude works with our setup
            test_env = {**os.environ, "ANTHROPIC_API_KEY": api_key}
            test_result = subprocess.run(
                ["claude", "--version"],
                capture_output=True,
                text=True,
                timeout=5,
                env=test_env
            )
            
            if test_result.returncode == 0:
                debug_log(f"Claude Code ready with onboarding bypass: {test_result.stdout.strip()}")
                return True
            else:
                debug_log(f"Claude Code test failed: {test_result.stderr}")
                return False
                
        except Exception as e:
            debug_log(f"Claude Code setup error: {type(e).__name__}: {e}")
            if DEBUG:
                import traceback
                debug_log(f"Claude Code setup traceback: {traceback.format_exc()}")
            return False
        """
        
    async def _setup_git_repository(self):
        """Clone git repository if git environment variables are present"""
        git_username = os.getenv("GIT_USERNAME")
        git_token = os.getenv("GIT_TOKEN")
        git_repo_url = os.getenv("GIT_REPO_URL")
        git_branch = os.getenv("GIT_BRANCH", "main")
        
        # Debug: log all git-related environment variables
        debug_log(f"Git environment check - USERNAME: {'SET' if git_username else 'MISSING'}")
        debug_log(f"Git environment check - TOKEN: {'SET' if git_token else 'MISSING'}")
        debug_log(f"Git environment check - REPO_URL: {'SET' if git_repo_url else 'MISSING'}")
        debug_log(f"Git environment check - BRANCH: {git_branch}")
        
        if not all([git_username, git_token, git_repo_url]):
            debug_log("Git environment variables not found, skipping repository setup")
            return
        
        debug_log(f"Setting up git repository: {git_repo_url}")
        
        try:
            import pathlib
            home_dir = pathlib.Path.home()
            repo_name = git_repo_url.split('/')[-1].replace('.git', '')
            repo_path = home_dir / repo_name
            
            # Configure git with credentials
            debug_log("Configuring git credentials")
            subprocess.run(["git", "config", "--global", "user.name", git_username], check=True, capture_output=True)
            subprocess.run(["git", "config", "--global", "user.email", f"{git_username}@users.noreply.github.com"], check=True, capture_output=True)
            
            # Clone repository if it doesn't exist
            if not repo_path.exists():
                debug_log(f"Cloning repository to {repo_path}")
                
                # Create authenticated URL - GitHub requires PAT as username with empty password
                if "github.com" in git_repo_url:
                    auth_url = git_repo_url.replace("https://", f"https://{git_token}@")
                else:
                    auth_url = git_repo_url  # For other git providers, might need different auth format
                
                result = subprocess.run([
                    "git", "clone", "-b", git_branch, auth_url, str(repo_path)
                ], capture_output=True, text=True, timeout=30)
                
                if result.returncode == 0:
                    debug_log(f"Successfully cloned repository to {repo_path}")
                    
                    # Change to repository directory for the shell session
                    os.chdir(repo_path)
                    debug_log(f"Changed working directory to {repo_path}")
                else:
                    debug_log(f"Failed to clone repository: {result.stderr}")
            else:
                debug_log(f"Repository already exists at {repo_path}")
                os.chdir(repo_path)
                
                # Try to pull latest changes
                try:
                    result = subprocess.run(["git", "pull"], capture_output=True, text=True, timeout=15, cwd=repo_path)
                    if result.returncode == 0:
                        debug_log("Successfully pulled latest changes")
                    else:
                        debug_log(f"Failed to pull changes: {result.stderr}")
                except subprocess.TimeoutExpired:
                    debug_log("Git pull timed out")
                
        except Exception as e:
            debug_log(f"Git repository setup error: {type(e).__name__}: {e}")
            if DEBUG:
                import traceback
                debug_log(f"Git setup traceback: {traceback.format_exc()}")

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

# Global agents and git setup tracking
agents: dict[str, AgentProcess] = {}
git_setup_done = False

async def setup_git_if_needed():
    """Simple git setup that runs once on first connection"""
    global git_setup_done
    if git_setup_done:
        return
        
    git_username = os.getenv("GIT_USERNAME")
    git_token = os.getenv("GIT_TOKEN")
    git_repo_url = os.getenv("GIT_REPO_URL")
    git_branch = os.getenv("GIT_BRANCH", "main")
    
    if not all([git_username, git_token, git_repo_url]):
        debug_log("No git environment variables, skipping git setup")
        return
        
    try:
        import pathlib
        import subprocess
        
        home_dir = pathlib.Path.home()
        repo_name = git_repo_url.split('/')[-1].replace('.git', '')
        repo_path = home_dir / repo_name
        
        if not repo_path.exists():
            debug_log(f"Cloning git repository: {git_repo_url}")
            subprocess.run(["git", "config", "--global", "user.name", git_username], check=True, capture_output=True)
            subprocess.run(["git", "config", "--global", "user.email", f"{git_username}@users.noreply.github.com"], check=True, capture_output=True)
            
            # Use PAT as username for GitHub auth
            auth_url = git_repo_url.replace("https://", f"https://{git_token}@")
            result = subprocess.run([
                "git", "clone", "-b", git_branch, auth_url, str(repo_path)
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                debug_log(f"Git repository cloned successfully to {repo_path}")
            else:
                debug_log(f"Git clone failed: {result.stderr}")
        else:
            debug_log(f"Git repository already exists at {repo_path}")
            
        git_setup_done = True
    except Exception as e:
        debug_log(f"Git setup error: {e}")


@app.get("/")
async def health_check():
    return {"status": "ok", "message": "Claude Agent Server is running"}


@app.websocket("/agents/{agent_id}/stream")
async def websocket_endpoint(websocket: WebSocket, agent_id: str):
    await websocket.accept()
    
    try:
        # Verify auth token from query params or headers
        # In a real implementation, you'd verify the token here
        
        # Setup git repository immediately on connection (independent of agent)
        await setup_git_if_needed()
        
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