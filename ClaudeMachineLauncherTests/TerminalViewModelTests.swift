import Foundation
import Testing
import Combine
@testable import ClaudeMachineLauncher

// Test helper for isolation
struct TestIsolation {
    static func cleanupSharedState() {
        AppStateManager.shared.clearAllMachines()
        SessionManager.shared.clearAllSessions()
    }
    
    static func waitForAsync() async {
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
    }
}

@Test("TerminalViewModel initialization state")
func testTerminalViewModelInitialization() {
    let viewModel = TerminalViewModel()
    
    // Test initial state
    #expect(viewModel.activeSessionId == nil)
    #expect(viewModel.isConnected == false)
    #expect(viewModel.isConnecting == false)
    #expect(viewModel.errorMessage == nil)
}

@Test("SessionManager creates and manages sessions")
func testSessionManagerBasicOperations() async {
    // Clean slate for test isolation
    TestIsolation.cleanupSharedState()
    
    let sessionManager = SessionManager.shared
    
    // Test initial state
    #expect(sessionManager.sessionCount == 0)
    #expect(sessionManager.activeSessionId == nil)
    #expect(sessionManager.activeSession == nil)
    
    // Create test machine
    let testMachine = FlyMachine(
        id: "test-session-\(UUID().uuidString)",
        name: "test-machine",
        state: "started",
        region: "ord",
        instanceId: nil,
        privateIP: "192.168.1.1",
        config: nil
    )
    
    sessionManager.createSession(for: testMachine, appName: "test-app", authToken: "test-token")
    
    // Wait for async operations to complete
    await TestIsolation.waitForAsync()
    
    // Test session creation
    #expect(sessionManager.sessionCount == 1)
    #expect(sessionManager.activeSessionId == testMachine.id)
    #expect(sessionManager.activeSession != nil)
    #expect(sessionManager.activeSession?.machine.id == testMachine.id)
    
    sessionManager.clearAllSessions()
    #expect(sessionManager.sessionCount == 0)
}

@Test("Logger debug toggle functionality")
func testLoggerDebugToggle() {
    // Logger should respect DEBUG_LOGGING environment variable
    let debugEnabled = ProcessInfo.processInfo.environment["DEBUG_LOGGING"] != nil
    #expect(Logger.debugEnabled == debugEnabled)
}

@Test("AgentStreamingError descriptions")
func testAgentStreamingErrorDescriptions() {
    let invalidURLError = AgentStreamingError.invalidURL
    let notConnectedError = AgentStreamingError.notConnected
    let authFailedError = AgentStreamingError.authenticationFailed
    let connectionLostError = AgentStreamingError.connectionLost
    
    #expect(invalidURLError.errorDescription == "Invalid WebSocket URL")
    #expect(notConnectedError.errorDescription == "Not connected to agent stream")
    #expect(authFailedError.errorDescription == "Authentication failed")
    #expect(connectionLostError.errorDescription == "Connection to agent lost")
}