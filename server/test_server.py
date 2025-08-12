#!/usr/bin/env python3
"""
Simple server tests for PTY functionality.
Run with: python test_server.py
"""
import pytest
import asyncio
import json
from serve_agent import AgentProcess, debug_log

def test_agent_process_initialization():
    """Test AgentProcess basic initialization"""
    agent = AgentProcess("test-agent")
    
    assert agent.agent_id == "test-agent"
    assert agent.process_pid is None
    assert agent.pty_fd is None
    assert not agent.is_running
    assert agent.terminal_size == (24, 80)
    assert len(agent.websockets) == 0

def test_agent_process_status():
    """Test AgentProcess status reporting"""
    agent = AgentProcess("status-test")
    
    status = agent.get_status()
    
    assert status["agent_id"] == "status-test"
    assert status["is_running"] is False
    assert status["process_pid"] is None
    assert status["terminal_size"] == (24, 80)
    assert status["connected_clients"] == 0

def test_resize_message_parsing():
    """Test JSON resize message parsing logic"""
    # Valid resize message
    resize_msg = '{"type":"resize","rows":30,"cols":100}'
    data = json.loads(resize_msg)
    
    assert data.get("type") == "resize"
    assert data.get("rows") == 30
    assert data.get("cols") == 100
    
    # Invalid JSON should not crash
    try:
        json.loads("not valid json")
        assert False, "Should have raised JSONDecodeError"
    except json.JSONDecodeError:
        pass  # Expected

def test_debug_logging_toggle():
    """Test debug logging can be toggled"""
    import os
    
    # Without DEBUG_LOGGING env var
    if 'DEBUG_LOGGING' in os.environ:
        del os.environ['DEBUG_LOGGING']
    
    from serve_agent import DEBUG
    assert DEBUG is False
    
    # Test debug_log doesn't crash when disabled
    debug_log("This should not print")

if __name__ == "__main__":
    print("Running server tests...")
    test_agent_process_initialization()
    print("✓ Agent initialization")
    
    test_agent_process_status()  
    print("✓ Agent status")
    
    test_resize_message_parsing()
    print("✓ Resize message parsing")
    
    test_debug_logging_toggle()
    print("✓ Debug logging toggle")
    
    print("All server tests passed!")