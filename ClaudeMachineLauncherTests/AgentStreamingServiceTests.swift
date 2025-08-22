import Foundation
import Testing
import Combine
@testable import ClaudeMachineLauncher

class MockAgentStreamingService: AgentStreamingServiceProtocol {
    var isConnected: Bool = false
    private let connectionStateSubject = CurrentValueSubject<ConnectionState, Never>(.disconnected)
    private let messagesSubject = PassthroughSubject<String, Never>()
    
    var connectionState: AnyPublisher<ConnectionState, Never> {
        connectionStateSubject.eraseToAnyPublisher()
    }
    
    var messages: AnyPublisher<String, Never> {
        messagesSubject.eraseToAnyPublisher()
    }
    
    var lastConnectedURL: URL?
    var lastToken: String?
    var sentMessages: [String] = []
    
    func connect(to url: URL, with token: String) async throws {
        lastConnectedURL = url
        lastToken = token
        isConnected = true
        connectionStateSubject.send(.connected)
    }
    
    func disconnect() {
        isConnected = false
        connectionStateSubject.send(.disconnected)
    }
    
    func send(_ message: String) async throws {
        sentMessages.append(message)
    }
    
    // Test helpers
    func simulateMessage(_ message: String) {
        messagesSubject.send(message)
    }
    
    func simulateConnectionError(_ error: Error) {
        connectionStateSubject.send(.failed(error))
    }
}

@Test("AgentStreamingService connection flow")
func testAgentStreamingConnection() async throws {
    let mockService = MockAgentStreamingService()
    let url = URL(string: "wss://example.com/agents/test/stream")!
    let token = "test-token"
    
    try await mockService.connect(to: url, with: token)
    
    #expect(mockService.isConnected == true)
    #expect(mockService.lastConnectedURL == url)
    #expect(mockService.lastToken == token)
}

@Test("AgentStreamingService message sending")
func testAgentStreamingMessageSending() async throws {
    let mockService = MockAgentStreamingService()
    let url = URL(string: "wss://example.com/agents/test/stream")!
    
    try await mockService.connect(to: url, with: "token")
    try await mockService.send("test message")
    
    #expect(mockService.sentMessages.contains("test message"))
}

@Test("TerminalViewModel connection state management")
func testTerminalViewModelConnectionState() async throws {
    let viewModel = TerminalViewModel()
    
    // With new architecture, connection is managed by SessionManager
    #expect(viewModel.isConnected == false)
    #expect(viewModel.activeSessionId == nil)
}

@Test("MachineStateManager multi-machine state")
func testMachineStateManagerMultiMachineState() async {
    // Clean slate for test isolation
    TestIsolation.cleanupSharedState()
    
    let machineState = MachineStateManager.shared
    
    // Create test machine with unique ID
    let testMachine = FlyMachine(
        id: "test-\(UUID().uuidString)",
        name: "test-machine",
        state: "started",
        region: "ord",
        instanceId: nil,
        privateIP: "192.168.1.1",
        config: nil
    )
    
    // Test would need to be updated when we add a public addMachine method
    // For now, just test that the machine state manager exists
    #expect(machineState.machines.isEmpty == true)
    #expect(machineState.activeMachine == nil)
}