import Foundation

struct FlyMachine: Codable {
    let id: String
    let name: String
    let state: String
    let region: String
    let instanceId: String?
    let privateIP: String?
    let config: MachineConfig?
    
    enum CodingKeys: String, CodingKey {
        case id, name, state, region, config
        case instanceId = "instance_id"
        case privateIP = "private_ip"
    }
}

struct MachineConfig: Codable {
    let image: String
    let env: [String: String]?
    let services: [MachineService]?
    let guest: GuestConfig?
    
    init(image: String, env: [String: String]? = nil, services: [MachineService]? = nil, guest: GuestConfig? = nil) {
        self.image = image
        self.env = env
        self.services = services
        self.guest = guest
    }
}

struct MachineService: Codable {
    let ports: [Port]
    let protocolType: String
    let internalPort: Int
    
    enum CodingKeys: String, CodingKey {
        case ports
        case protocolType = "protocol"
        case internalPort = "internal_port"
    }
}

struct Port: Codable {
    let port: Int
    let handlers: [String]?
}

struct GuestConfig: Codable {
    let memoryMb: Int
    let cpus: Int
    let cpuKind: String
    
    enum CodingKeys: String, CodingKey {
        case memoryMb = "memory_mb"
        case cpus
        case cpuKind = "cpu_kind"
    }
    
    init(memoryMb: Int = 1024, cpus: Int = 1, cpuKind: String = "shared") {
        self.memoryMb = memoryMb
        self.cpus = cpus
        self.cpuKind = cpuKind
    }
}