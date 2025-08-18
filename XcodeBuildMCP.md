# XcodeBuildMCP Testing Guide

Testing the XcodeBuildMCP with ClaudeMachineLauncher iOS project.

## ClaudeMachineLauncher Test Commands

### 1. Project Discovery
```javascript
discover_projs({ workspaceRoot: "/Users/aplucche/repos/cc_ios_test" })
// Found: ClaudeMachineLauncher.xcodeproj

list_schemes({ projectPath: "/Users/aplucche/repos/cc_ios_test/ClaudeMachineLauncher.xcodeproj" })
// Available scheme: ClaudeMachineLauncher
```

### 2. Build for iOS Simulator
```javascript
build_sim({ 
  projectPath: "/Users/aplucche/repos/cc_ios_test/ClaudeMachineLauncher.xcodeproj", 
  scheme: "ClaudeMachineLauncher", 
  simulatorName: "iPhone 16" 
})
// ✅ Build succeeded
```

### 3. Get App Details
```javascript
get_sim_app_path({ 
  projectPath: "/Users/aplucche/repos/cc_ios_test/ClaudeMachineLauncher.xcodeproj", 
  scheme: "ClaudeMachineLauncher", 
  platform: "iOS Simulator",
  simulatorName: "iPhone 16" 
})
// Returns: /Users/aplucche/Library/Developer/Xcode/DerivedData/ClaudeMachineLauncher-*/Build/Products/Debug-iphonesimulator/ClaudeMachineLauncher.app

get_app_bundle_id({ appPath: "PATH_FROM_ABOVE" })
// Returns: com.example.claudemachinelauncher
```

### 4. Simulator Setup & Launch
```javascript
list_sims()
// Shows available simulators with UUIDs

boot_sim({ simulatorUuid: "74919D9C-F842-4A8F-B625-812FB206E9B6" }) // iPhone 16
open_sim()

install_app_sim({ 
  simulatorUuid: "74919D9C-F842-4A8F-B625-812FB206E9B6", 
  appPath: "PATH_FROM_STEP_3" 
})

launch_app_sim({ 
  simulatorUuid: "74919D9C-F842-4A8F-B625-812FB206E9B6", 
  bundleId: "com.example.claudemachinelauncher" 
})
```

### 5. Terminal UI Testing
```javascript
// Get UI elements with precise coordinates
describe_ui({ simulatorUuid: "74919D9C-F842-4A8F-B625-812FB206E9B6" })

// Tap in terminal area (TextArea at 0,193 with 320x238 dimensions)
tap({ simulatorUuid: "74919D9C-F842-4A8F-B625-812FB206E9B6", x: 160, y: 312 })

// Type commands in terminal
type_text({ simulatorUuid: "74919D9C-F842-4A8F-B625-812FB206E9B6", text: "ls -la" })

// Press Enter (keyCode 40)
key_press({ simulatorUuid: "74919D9C-F842-4A8F-B625-812FB206E9B6", keyCode: 40 })

// Take screenshot to verify
screenshot({ simulatorUuid: "74919D9C-F842-4A8F-B625-812FB206E9B6" })
```

## Real-World Testing Results

### ✅ Development Workflow
1. **Code Fix & Deploy**: Modified `serve_agent.py`, built container locally, committed and deployed to GHCR
2. **Fresh Testing**: Built new iOS app, launched clean iPhone 16 Pro simulator  
3. **Machine Launch**: Used "Launch New Agent" button, waited ~30s for machine to start
4. **Live Debugging**: Connected to new machine "red-sea-5488", tested Claude Code CLI in real terminal

### ✅ UI Automation Capabilities  
- **Tab Navigation**: Successfully used gestures and taps to navigate between Agents/Terminal tabs
- **Form Interaction**: Verified API keys, app names, container images in configuration
- **Live Terminal**: Typed commands, pressed keys, saw real-time output from remote Fly.io machines
- **Visual Verification**: Screenshots confirmed app states, terminal responses, connection status

### ✅ Debugging Effectiveness
- **Container Testing**: Verified new container with environment variable fixes deployed correctly
- **Real-time Diagnosis**: Identified that `claude --version` executes but hangs (no output, no prompt return)
- **Live Troubleshooting**: Tested Ctrl+C interruption, analyzed terminal states, confirmed hanging behavior

## Practical Lessons

### Navigation Tips
- **Scrolling can be inverted** - try `scroll-up` if `scroll-down` goes wrong direction
- **Tab bars need precise tapping** - use `describe_ui` for exact coordinates  
- **Gestures work well** - `swipe-from-right-edge` for navigation, `scroll-up/down` for content

### Terminal Interaction
- **Always tap terminal area first** - ensures focus before typing
- **Key codes work reliably** - keyCode 40 = Enter, keyCode 6 = Ctrl+C
- **Real terminal features** - command history, live output, bidirectional communication

### Development Integration  
- **Live container testing** - Deploy fixes and test immediately in real environment
- **Multiple simulator support** - Can run different devices simultaneously for testing
- **Complete build cycle** - From code change to deployed container to live testing in <5 minutes

## Container Testing Results

### ✅ Environment Variable Fix Success
**Fixed `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` hanging issue by using individual variables:**
```bash
# New working environment variables in container:
DISABLE_ERROR_REPORTING=1
DISABLE_TELEMETRY=1  
DISABLE_BUG_COMMAND=1
DISABLE_AUTOUPDATER=1
ANTHROPIC_API_KEY=sk-ant-api03-...

# No longer using problematic:
# CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=true
```

### ✅ Container Deployment Workflow
1. **Code Fix**: Modified `serve_agent.py` environment variables
2. **Local Testing**: `make docker-test` - "✅ Claude Code detection passed"
3. **Deploy**: Git commit/push triggers GHCR container build
4. **Live Testing**: Launch new machine "empty-night-1512" with updated container
5. **Verification**: Terminal testing confirms fixes applied

### ✅ Claude Code Status
- **Installation**: ✅ `/usr/local/bin/claude` present
- **Configuration**: ✅ `~/.claude/claude.json` and `settings.json` created  
- **API Key**: ✅ Properly passed from iOS app to container
- **Basic Commands**: ✅ `which claude`, environment checks work
- **Help Command**: ✅ `timeout 5 claude --help` completes (vs infinite hang)
- **Version Command**: ❌ Still hangs, but manageable with timeouts

### 🔧 Button Interaction Challenge
**"Launch New Agent" button difficult to trigger via automation:**
- Multiple tap approaches tried (single, double, long press, touch events)
- Coordinates verified with `describe_ui` - button frame correct
- Occasional success (saw "No Replacements Found" briefly)
- **Workaround**: Manual button press by user, then continue automated testing

## Best Practices

1. **Always use `describe_ui`** before UI interactions - coordinates are pixel-perfect
2. **Take screenshots frequently** - Visual verification catches issues early  
3. **Test with fresh simulators** - Avoids cached state from previous tests
4. **Wait for deployments** - Give containers 30+ seconds to start after launching
5. **Use timeouts for Claude commands** - `timeout 5 claude --help` vs hanging indefinitely
6. **Manual fallback for difficult buttons** - Some UI elements may need manual interaction
7. **Verify environment variables** - `env | grep -E "(DISABLE|ANTHROPIC)"` confirms fixes applied