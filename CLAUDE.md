# iOS Minimal Development Template

*A streamlined approach to iOS development optimized for Claude Code and AI-assisted workflows.*

---

## Setup

```bash
brew install xcodegen xcbeautify
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

---

## Core Commands

```bash
# Generate Xcode project
xcodegen generate

# Build app quietly
xcodebuild -scheme APP_NAME -destination 'platform=iOS Simulator,name=SIM_NAME' | xcbeautify --quieter

# Test target
xcodebuild test -scheme APP_NAME -destination 'platform=iOS Simulator,name=SIM_NAME' | xcbeautify --quieter
```

---

## Project Structure

```
ProjectName/
├── project.yml               # XcodeGen config
├── CLAUDE.md                 # Claude instructions
├── Core/                     # Shared infrastructure
│   ├── Persistence.swift
│   └── RepositoryProtocol.swift
├── Features/                 # Vertical feature pods
│   └── Entity/
│       ├── Entity.swift
│       ├── EntityRepository.swift
│       ├── EntityService.swift
│       ├── EntityViewModel.swift
│       └── EntityView.swift
└── ProjectNameTests/         # Unit tests
```

---

## Testing Conventions

```swift
// EntityTests.swift
import Testing
@testable import AppName

struct EntityTests {
  @Test func testInit() {
    let e = Entity(name: "Sample")
    #expect(e.name == "Sample")
  }
}
```

```swift
// MockEntityRepository.swift
struct MockEntityRepository: EntityRepositoryProtocol {
  func fetchEntities() -> AnyPublisher<[Entity], RepositoryError> {
    Just([]).setFailureType(to: RepositoryError.self).eraseToAnyPublisher()
  }
}
```

---

## project.yml

```yaml
name: AppName
targets:
  AppName:
    type: application
    platform: iOS
    sources: [AppName]
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.example.app
      GENERATE_INFOPLIST_FILE: YES
      MARKETING_VERSION: "1.0"
      CURRENT_PROJECT_VERSION: "1"
    dependencies:
      - sdk: SwiftUI.framework
      - sdk: CoreData.framework

  AppNameTests:
    type: bundle.unit-test
    platform: iOS
    sources: [AppNameTests]
    dependencies: [target: AppName]
    settings:
      GENERATE_INFOPLIST_FILE: YES
```

---

## Design Principles

- Code grouped by feature, not by type
- Keep shared logic isolated in Core/
- Each pod is self-contained and testable
- Favor @Published + Combine for state flow
- One responsibility per file, <100 lines if possible
- Claude can clone/modify pods without needing global context

---

## Claude Development Loop

1. Claude emits code → write/update a file
2. Run: `xcodegen generate && xcodebuild ...`
3. Claude reads logs (errors only via `--quieter`)
4. Claude suggests targeted edits
5. Repeat until build & test pass