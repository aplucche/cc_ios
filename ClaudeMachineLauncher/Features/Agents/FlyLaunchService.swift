import Foundation
import Combine

protocol FlyLaunchServiceProtocol {
    func launchMachine(config: FlyLaunchConfig, token: String) -> AnyPublisher<FlyMachine, APIError>
    func getMachineStatus(appName: String, machineId: String, token: String) -> AnyPublisher<FlyMachine, APIError>
    func ensureAppExists(appName: String, token: String) -> AnyPublisher<FlyApp, APIError>
    func deployApp(config: FlyLaunchConfig, token: String) -> AnyPublisher<FlyDeployResponse, APIError>
    func allocateIPs(appName: String, token: String) -> AnyPublisher<Bool, APIError>
    func startMachine(appName: String, machineId: String, token: String) -> AnyPublisher<Void, APIError>
    func stopMachine(appName: String, machineId: String, token: String) -> AnyPublisher<Void, APIError>
    func listMachines(appName: String, token: String) -> AnyPublisher<[FlyMachine], APIError>
}

class FlyLaunchService: FlyLaunchServiceProtocol {
    private let apiClient: FlyAPIClient
    
    init(apiClient: FlyAPIClient = FlyAPIClient()) {
        self.apiClient = apiClient
    }
    
    func launchMachine(config: FlyLaunchConfig, token: String) -> AnyPublisher<FlyMachine, APIError> {
        Logger.log("Service launching machine with config: app=\(config.appName), image=\(config.image), region=\(config.region)", category: .system)
        
        // 1. Ensure app exists
        // 2. Allocate public IP addresses (required for hostname to resolve)
        // 3. Launch machine
        return ensureAppExists(appName: config.appName, token: token)
            .handleEvents(receiveOutput: { app in
                Logger.log("✅ App confirmed: \(app.name) (status: \(app.status))", category: .system)
            })
            .flatMap { [weak self] app -> AnyPublisher<Bool, APIError> in
                Logger.log("Allocating public IPs for hostname resolution...", category: .system)
                guard let self = self else {
                    return Fail(error: APIError.invalidResponse).eraseToAnyPublisher()
                }
                return self.allocateIPs(appName: config.appName, token: token)
            }
            .handleEvents(receiveOutput: { success in
                Logger.log("✅ IP allocation: \(success)", category: .system)
            })
            .flatMap { [weak self] ipSuccess -> AnyPublisher<FlyMachine, APIError> in
                Logger.log("Launching machine...", category: .system)
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
    
    func deployApp(config: FlyLaunchConfig, token: String) -> AnyPublisher<FlyDeployResponse, APIError> {
        Logger.log("Service deploying app: \(config.appName) with image: \(config.image)", category: .system)
        
        let deployRequest = FlyDeployRequest(config: config)
        return apiClient.deployApp(appName: config.appName, deployRequest: deployRequest, token: token)
    }
    
    func allocateIPs(appName: String, token: String) -> AnyPublisher<Bool, APIError> {
        Logger.log("Allocating IPs via GraphQL API for \(appName)", category: .system)
        
        return Future { promise in
            Task {
                do {
                    // Allocate shared IPv4 using GraphQL
                    let graphqlURL = URL(string: "https://api.fly.io/graphql")!
                    
                    let ipv4Query = """
                    mutation($input: AllocateIPAddressInput!) {
                        allocateIpAddress(input: $input) {
                            app { name }
                        }
                    }
                    """
                    
                    let ipv4Variables: [String: Any] = [
                        "input": [
                            "appId": appName,
                            "type": "shared_v4"
                        ]
                    ]
                    
                    let ipv4Body: [String: Any] = [
                        "query": ipv4Query,
                        "variables": ipv4Variables
                    ]
                    
                    var request = URLRequest(url: graphqlURL)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: ipv4Body)
                    
                    Logger.log("GraphQL request: \(String(data: request.httpBody!, encoding: .utf8) ?? "")", category: .network)
                    
                    let (data, response) = try await URLSession.shared.data(for: request)
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        Logger.log("GraphQL response: \(httpResponse.statusCode)", category: .network)
                        Logger.log("GraphQL body: \(String(data: data, encoding: .utf8) ?? "")", category: .network)
                        
                        let success = httpResponse.statusCode == 200
                        promise(.success(success))
                    } else {
                        promise(.success(false))
                    }
                    
                } catch {
                    Logger.log("IP allocation error: \(error.localizedDescription)", category: .system)
                    // Don't fail the flow - continue without IP allocation
                    promise(.success(false))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    func startMachine(appName: String, machineId: String, token: String) -> AnyPublisher<Void, APIError> {
        Logger.log("Service starting machine: \(machineId) for app: \(appName)", category: .system)
        return apiClient.startMachine(appName: appName, machineId: machineId, token: token)
    }
    
    func stopMachine(appName: String, machineId: String, token: String) -> AnyPublisher<Void, APIError> {
        Logger.log("Service stopping machine: \(machineId) for app: \(appName)", category: .system)
        return apiClient.stopMachine(appName: appName, machineId: machineId, token: token)
    }
    
    func listMachines(appName: String, token: String) -> AnyPublisher<[FlyMachine], APIError> {
        Logger.log("Service listing machines for app: \(appName)", category: .system)
        return apiClient.listMachines(appName: appName, token: token)
    }
}