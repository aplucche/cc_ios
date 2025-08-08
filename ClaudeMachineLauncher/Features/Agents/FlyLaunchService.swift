import Foundation
import Combine

protocol FlyLaunchServiceProtocol {
    func launchMachine(config: FlyLaunchConfig, token: String) -> AnyPublisher<FlyMachine, APIError>
    func getMachineStatus(appName: String, machineId: String, token: String) -> AnyPublisher<FlyMachine, APIError>
    func ensureAppExists(appName: String, token: String) -> AnyPublisher<FlyApp, APIError>
}

class FlyLaunchService: FlyLaunchServiceProtocol {
    private let apiClient: FlyAPIClient
    
    init(apiClient: FlyAPIClient = FlyAPIClient()) {
        self.apiClient = apiClient
    }
    
    func launchMachine(config: FlyLaunchConfig, token: String) -> AnyPublisher<FlyMachine, APIError> {
        Logger.log("Service launching machine with config: app=\(config.appName), image=\(config.image), region=\(config.region)", category: .system)
        
        // Ensure app exists before launching machine
        return ensureAppExists(appName: config.appName, token: token)
            .flatMap { [weak self] app -> AnyPublisher<FlyMachine, APIError> in
                Logger.log("App confirmed: \(app.name), proceeding with machine launch", category: .system)
                guard let self = self else {
                    return Fail(error: APIError.invalidResponse).eraseToAnyPublisher()
                }
                let request = FlyLaunchRequest(config: config)
                return self.apiClient.launchMachine(appName: config.appName, request: request, token: token)
            }
            .share()
            .eraseToAnyPublisher()
    }
    
    func getMachineStatus(appName: String, machineId: String, token: String) -> AnyPublisher<FlyMachine, APIError> {
        Logger.log("Service getting machine status for \(machineId)", category: .system)
        return apiClient.getMachine(appName: appName, machineId: machineId, token: token)
    }
    
    func ensureAppExists(appName: String, token: String) -> AnyPublisher<FlyApp, APIError> {
        Logger.log("Checking if app exists: \(appName)", category: .system)
        
        return apiClient.getApp(appName: appName, token: token)
            .catch { [weak self] error -> AnyPublisher<FlyApp, APIError> in
                guard let self = self else {
                    return Fail(error: APIError.invalidResponse).eraseToAnyPublisher()
                }
                
                // If app doesn't exist (404), try to create it with personal org
                if case .serverError(404) = error {
                    Logger.log("App not found, attempting to create: \(appName)", category: .system)
                    return self.createAppWithPersonalOrg(appName: appName, token: token)
                } else {
                    // Other errors (auth, network, etc.) should bubble up
                    Logger.log("App check failed with error: \\(error)", category: .system)
                    return Fail(error: error).eraseToAnyPublisher()
                }
            }
            .share()
            .eraseToAnyPublisher()
    }
    
    private func createAppWithPersonalOrg(appName: String, token: String) -> AnyPublisher<FlyApp, APIError> {
        Logger.log("Creating app with personal organization: \(appName)", category: .system)
        
        // Try with "personal" as default org slug
        let request = FlyAppCreateRequest(appName: appName, orgSlug: "personal")
        return apiClient.createApp(request: request, token: token)
            .catch { error -> AnyPublisher<FlyApp, APIError> in
                Logger.log("App creation failed: \\(error). Please create the app manually with: flyctl apps create \\(appName)", category: .system)
                return Fail(error: error).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
}