# Claude Machine Launcher - Development Commands
.PHONY: help ios-generate ios-build ios-test server-dev docker-build docker-test container-publish test-integration

# Default target
help:
	@echo "Available commands:"
	@echo "  ios-generate      Generate Xcode project"
	@echo "  ios-build         Build iOS app"
	@echo "  ios-test          Run iOS tests"
	@echo "  server-dev        Run FastAPI server locally"
	@echo "  docker-build      Build Docker container"
	@echo "  docker-test       Test Docker container locally"
	@echo "  container-publish Push to main branch to trigger GHCR publish"
	@echo "  test-integration  Run full integration test suite"

# Variables
IOS_SCHEME = ClaudeMachineLauncher
IOS_DESTINATION = 'platform=iOS Simulator,name=iPhone 16'
GHCR_IMAGE = ghcr.io/aplucche/cc_ios-claude-agent:latest
CONTAINER_NAME = claude-agent
TEST_TOKEN = test-token-123

# iOS Commands
ios-generate:
	xcodegen generate

ios-build: ios-generate
	xcodebuild -scheme $(IOS_SCHEME) -destination $(IOS_DESTINATION) | xcbeautify --quieter

ios-test: ios-generate
	xcodebuild test -scheme $(IOS_SCHEME) -destination $(IOS_DESTINATION) | xcbeautify --quieter

# Server Commands
server-dev:
	cd server && uv run uvicorn serve_agent:app --host 0.0.0.0 --port 8080 --reload

# Container Commands
docker-build:
	cd server && docker build -t $(CONTAINER_NAME) .

docker-test: docker-build
	@echo "🧪 Testing Docker container locally..."
	@docker run -d -p 8080:8080 -e AUTH_TOKEN=$(TEST_TOKEN) --name test-claude-agent $(CONTAINER_NAME)
	@sleep 3
	@curl -f http://localhost:8080/ && echo " ✅ Health check passed"
	@curl -f -H "Authorization: Bearer $(TEST_TOKEN)" http://localhost:8080/agents && echo " ✅ Auth endpoint passed"
	@docker stop test-claude-agent && docker rm test-claude-agent
	@echo "✅ Container tests complete!"

container-publish:
	@echo "📦 To publish container to GHCR:"
	@echo "1. Commit your changes: git add . && git commit -m 'Update container'"
	@echo "2. Push to main branch: git push origin main"
	@echo "3. GitHub Actions will build and push to: $(GHCR_IMAGE)"
	@echo "4. Use this image in your iOS app's Fly machine creation API calls"

# Integration Testing
test-integration:
	./test-integration.sh