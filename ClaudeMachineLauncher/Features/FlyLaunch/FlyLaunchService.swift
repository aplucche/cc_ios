import Foundation
import Combine

protocol FlyLaunchServiceProtocol {
    func launchMachine(config: FlyLaunchConfig, token: String) -> AnyPublisher<FlyMachine, APIError>
    func getMachineStatus(appName: String, machineId: String, token: String) -> AnyPublisher<FlyMachine, APIError>
}

class FlyLaunchService: FlyLaunchServiceProtocol {
    private let apiClient: FlyAPIClient
    
    init(apiClient: FlyAPIClient = FlyAPIClient()) {
        self.apiClient = apiClient
    }
    
    func launchMachine(config: FlyLaunchConfig, token: String) -> AnyPublisher<FlyMachine, APIError> {
        let request = FlyLaunchRequest(config: config)
        return apiClient.launchMachine(appName: config.appName, request: request, token: token)
    }
    
    func getMachineStatus(appName: String, machineId: String, token: String) -> AnyPublisher<FlyMachine, APIError> {
        return apiClient.getMachine(appName: appName, machineId: machineId, token: token)
    }
}