import Testing
import Combine
@testable import ClaudeMachineLauncher

class MockFlyLaunchService: FlyLaunchServiceProtocol {
    var shouldSucceed = true
    var mockMachine: FlyMachine?
    var mockApp: FlyApp?
    
    func launchMachine(config: FlyLaunchConfig, token: String) -> AnyPublisher<FlyMachine, APIError> {
        if shouldSucceed, let machine = mockMachine {
            return Just(machine)
                .setFailureType(to: APIError.self)
                .eraseToAnyPublisher()
        } else {
            return Fail(error: APIError.unauthorized)
                .eraseToAnyPublisher()
        }
    }
    
    func getMachineStatus(appName: String, machineId: String, token: String) -> AnyPublisher<FlyMachine, APIError> {
        if shouldSucceed, let machine = mockMachine {
            return Just(machine)
                .setFailureType(to: APIError.self)
                .eraseToAnyPublisher()
        } else {
            return Fail(error: APIError.serverError(500))
                .eraseToAnyPublisher()
        }
    }
    
    func ensureAppExists(appName: String, token: String) -> AnyPublisher<FlyApp, APIError> {
        if shouldSucceed, let app = mockApp {
            return Just(app)
                .setFailureType(to: APIError.self)
                .eraseToAnyPublisher()
        } else {
            return Fail(error: APIError.serverError(404))
                .eraseToAnyPublisher()
        }
    }
}

struct FlyLaunchViewModelTests {
    
    @Test func testInitialState() {
        let viewModel = FlyLaunchViewModel()
        
        #expect(viewModel.flyAPIToken.isEmpty)
        #expect(viewModel.appName == "claudeagents")
        #expect(viewModel.image == "ghcr.io/aplucche/cc_ios-claude-agent:latest")
        #expect(viewModel.region == "ord")
        #expect(!viewModel.isLoading)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.launchedMachine == nil)
    }
    
    @Test func testCanLaunch() {
        let viewModel = FlyLaunchViewModel()
        
        #expect(!viewModel.canLaunch)
        
        viewModel.flyAPIToken = "token"
        viewModel.appName = "test-app"
        
        #expect(viewModel.canLaunch)
    }
    
    @Test func testSuccessfulLaunch() async throws {
        let mockService = MockFlyLaunchService()
        let testMachine = FlyMachine(
            id: "test-123",
            name: "test-machine",
            state: "started",
            region: "ord",
            instanceId: nil,
            privateIP: "192.168.1.1",
            config: nil
        )
        
        mockService.mockMachine = testMachine
        mockService.shouldSucceed = true
        
        let viewModel = FlyLaunchViewModel(service: mockService)
        viewModel.flyAPIToken = "test-token"
        viewModel.appName = "test-app"
        
        viewModel.launchMachine()
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        #expect(viewModel.launchedMachine?.id == "test-123")
        #expect(viewModel.launchedMachine?.state == "started")
        #expect(viewModel.errorMessage == nil)
    }
}