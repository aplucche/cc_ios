import Foundation

struct FlyLaunchConfig {
    let appName: String
    let image: String
    let region: String
    let env: [String: String]
    let internalPort: Int
    let selectedRepository: GitRepository?
    
    init(appName: String, image: String, region: String = "ord", env: [String: String] = [:], internalPort: Int = 8080, selectedRepository: GitRepository? = nil) {
        self.appName = appName
        self.image = image
        self.region = region
        self.env = env
        self.internalPort = internalPort
        self.selectedRepository = selectedRepository
    }
    
    func toMachineConfig() -> MachineConfig {
        let service = MachineService(
            ports: [
                Port(port: 80, handlers: ["http"]),
                Port(port: 443, handlers: ["tls", "http"])
            ],
            protocolType: "tcp",
            internalPort: internalPort
        )
        
        var machineEnv = env
        
        // Add git environment variables if repository is selected
        if let repository = selectedRepository {
            machineEnv["GIT_REPO_URL"] = repository.url
            machineEnv["GIT_BRANCH"] = repository.branch
        }
        
        return MachineConfig(
            image: image,
            env: machineEnv.isEmpty ? nil : machineEnv,
            services: [service],
            guest: GuestConfig(memoryMb: 1024)
        )
    }
}

struct FlyLaunchRequest: Codable {
    let name: String?
    let region: String
    let config: MachineConfig
    
    init(config: FlyLaunchConfig) {
        self.name = nil
        self.region = config.region
        self.config = config.toMachineConfig()
    }
}

// MARK: - App Deployment Models

struct FlyDeployRequest: Codable {
    let region: String
    let config: MachineConfig
    let restart: RestartPolicy?
    
    init(config: FlyLaunchConfig) {
        self.region = config.region
        self.config = config.toMachineConfig()
        self.restart = RestartPolicy(policy: "always")
    }
}

struct RestartPolicy: Codable {
    let policy: String
}

struct FlyDeployResponse: Codable {
    let id: String
    let name: String
    let state: String
    let region: String
    let instanceId: String?
    let privateIP: String?
    let config: MachineConfig?
    let createdAt: String
    let updatedAt: String
    
    enum CodingKeys: String, CodingKey {
        case id, name, state, region, config
        case instanceId = "instance_id"
        case privateIP = "private_ip"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}