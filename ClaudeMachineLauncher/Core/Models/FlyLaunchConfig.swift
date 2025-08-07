import Foundation

struct FlyLaunchConfig {
    let appName: String
    let image: String
    let region: String
    let env: [String: String]
    let internalPort: Int
    
    init(appName: String, image: String, region: String = "ord", env: [String: String] = [:], internalPort: Int = 8080) {
        self.appName = appName
        self.image = image
        self.region = region
        self.env = env
        self.internalPort = internalPort
    }
    
    func toMachineConfig() -> MachineConfig {
        let service = MachineService(
            ports: [Port(port: 80, handlers: ["http"])],
            protocolType: "tcp",
            internalPort: internalPort
        )
        
        return MachineConfig(
            image: image,
            env: env.isEmpty ? nil : env,
            services: [service]
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