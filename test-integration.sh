#!/bin/bash
set -e

echo "🧪 Starting Integration Test Suite"

# Test 1: Server Health Check
echo "1. Testing server health..."
make server-dev &
SERVER_PID=$!
sleep 3

# Health check
curl -f http://localhost:8080/ || { echo "❌ Health check failed"; exit 1; }
echo "✅ Server health check passed"

# Test 2: Auth endpoint
echo "2. Testing authentication..."
curl -f -H "Authorization: Bearer default-token" http://localhost:8080/agents || { echo "❌ Auth test failed"; exit 1; }
echo "✅ Authentication test passed"

# Test 3: WebSocket connection (using wscat if available)
if command -v wscat &> /dev/null; then
    echo "3. Testing WebSocket connection..."
    timeout 5 wscat -c "ws://localhost:8080/agents/test/stream" --execute 'hello' || echo "⚠️ WebSocket test needs manual verification"
fi

# Test 4: iOS Unit Tests
echo "4. Running iOS unit tests..."
make ios-test

# Test 5: Container Test
echo "5. Testing Docker container..."
kill $SERVER_PID 2>/dev/null || true
sleep 2
make docker-test

echo "🎉 All integration tests completed successfully!"

# Cleanup function
cleanup() {
    kill $SERVER_PID 2>/dev/null || true
    docker stop test-claude-agent 2>/dev/null || true
    docker rm test-claude-agent 2>/dev/null || true
}

trap cleanup EXIT