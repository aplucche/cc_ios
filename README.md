# Claude Machine Launcher

iOS app to launch and monitor Fly.io machines.

## Quick Start

```bash
# 1. Generate Xcode project
xcodegen generate

# 2. Open in Xcode
open ClaudeMachineLauncher.xcodeproj

# 3. Run in simulator (⌘+R)
```

## Usage

1. **Get Fly API Token**: [fly.io/user/personal_access_tokens](https://fly.io/user/personal_access_tokens)
2. **Enter Details**: API token, app name (must exist on Fly.io), Docker image
3. **Launch**: Tap "Launch Machine" 
4. **Monitor**: View machine ID, status, region, IP

## Commands

```bash
# Build & test
xcodegen generate && xcodebuild test -scheme ClaudeMachineLauncher -destination 'platform=iOS Simulator,name=iPhone 16' | xcbeautify --quieter
```