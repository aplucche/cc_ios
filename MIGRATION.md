# Migration to cc_ios Private Repository

## Overview

Move the Claude Agent WebSocket container to the private `cc_ios` repository for production use.

## Files to Copy

Copy these files to `git@github.com:aplucche/cc_ios.git`:

```
├── .github/workflows/docker.yml       # GitHub Actions for GHCR publishing
├── Makefile                          # Development commands
├── DEPLOYMENT.md                     # Container deployment guide
├── server/
│   ├── Dockerfile                   # Container definition
│   ├── serve_agent.py              # FastAPI WebSocket server
│   ├── pyproject.toml              # Python dependencies
│   └── README.md                   # Server documentation
```

## Migration Steps

1. **Copy Files to cc_ios**
   ```bash
   # Clone the private repo
   git clone git@github.com:aplucche/cc_ios.git
   cd cc_ios
   
   # Copy server files
   cp -r /path/to/cc_ios_test/server ./
   cp -r /path/to/cc_ios_test/.github ./
   cp /path/to/cc_ios_test/Makefile ./
   cp /path/to/cc_ios_test/DEPLOYMENT.md ./
   ```

2. **Commit and Push**
   ```bash
   git add .
   git commit -m "Add Claude Agent WebSocket container for terminal streaming"
   git push origin main
   ```

3. **Verify GitHub Actions**
   - Push triggers container build
   - Image publishes to: `ghcr.io/aplucche/cc_ios-claude-agent:latest`
   - Container registry is **private** (matches repo visibility)

## Updated Container Image

**New GHCR Image**: `ghcr.io/aplucche/cc_ios-claude-agent:latest`

This image will be **private** and only accessible with proper authentication.

## iOS App Integration

In your iOS app, update machine creation to use:

```swift
let launchConfig = FlyLaunchConfig(
    image: "ghcr.io/aplucche/cc_ios-claude-agent:latest",
    env: ["AUTH_TOKEN": generateSecureToken()],
    region: userRegion
)
```

## Security Benefits

- **Private container registry** - Only accessible with authentication
- **Private source code** - Container build process not publicly visible
- **Secure token handling** - Production-ready authentication

## Commands After Migration

```bash
# Test container locally
make docker-test

# Push changes to trigger GHCR publish
git push origin main

# View available commands
make help
```

## Cleanup

After successful migration, you can remove:
- The test repository files (if no longer needed)
- Any public container images from the test repo