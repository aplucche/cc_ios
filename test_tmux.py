#!/usr/bin/env python3
"""
Test tmux-based terminal integration for Claude Agent
"""
import asyncio
import websockets
import sys

async def test_tmux_integration():
    """Test that tmux sessions work with WebSocket connections"""
    uri = "ws://localhost:8080/agents/tmux-test/stream"
    
    try:
        # Test connection
        async with websockets.connect(uri, timeout=5) as websocket:
            # Read initial connection messages
            initial_messages = []
            for _ in range(4):
                try:
                    message = await asyncio.wait_for(websocket.recv(), timeout=2.0)
                    initial_messages.append(message)
                except asyncio.TimeoutError:
                    break
            
            # Verify we got expected connection messages
            if not any("Connected to Claude Agent Terminal" in msg for msg in initial_messages):
                raise Exception("Did not receive connection message")
            
            if not any("Agent ID: tmux-test" in msg for msg in initial_messages):
                raise Exception("Did not receive agent ID")
            
            # Test command execution
            await websocket.send("echo 'tmux-test-success'\n")
            await asyncio.sleep(1)
            
            # Read command response
            response_received = False
            for _ in range(3):
                try:
                    response = await asyncio.wait_for(websocket.recv(), timeout=2.0)
                    if "tmux-test-success" in response:
                        response_received = True
                        break
                except asyncio.TimeoutError:
                    break
            
            if not response_received:
                raise Exception("Command execution failed - no echo response")
            
            return True
            
    except Exception as e:
        print(f"tmux integration test failed: {e}")
        return False

def main():
    """Run tmux integration test"""
    try:
        success = asyncio.run(test_tmux_integration())
        if success:
            print("tmux integration test passed")
            sys.exit(0)
        else:
            sys.exit(1)
    except Exception as e:
        print(f"Test error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()