import Foundation
import Testing
import Combine
@testable import ClaudeMachineLauncher

// Test helper for isolation
struct TestIsolation {
    static func cleanupSharedState() {
        // MachineStateManager doesn't have public clear method
        // Tests should work with existing machines or be isolated
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

@Test("MachineStateManager basic operations")
func testMachineStateManagerBasicOperations() async {
    // Clean slate for test isolation
    TestIsolation.cleanupSharedState()
    
    let machineState = MachineStateManager.shared
    
    // Test initial state
    #expect(machineState.activeMachine == nil)
    #expect(machineState.machines.isEmpty)
    
    // Test would require public API for adding machines
    // For now, just verify the manager exists and has basic properties
    #expect(machineState.activeMachineId == nil)
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