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
        Logger.log("Service launching machine with config: app=\(config.appName), image=\(config.image), region=\(config.region)", category: .system)
        let request = FlyLaunchRequest(config: config)
        return apiClient.launchMachine(appName: config.appName, request: request, token: token)
    }
    
    func getMachineStatus(appName: String, machineId: String, token: String) -> AnyPublisher<FlyMachine, APIError> {
        Logger.log("Service getting machine status for \(machineId)", category: .system)
        return apiClient.getMachine(appName: appName, machineId: machineId, token: token)
    }
}