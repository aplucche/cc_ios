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
    
    init(image: String, env: [String: String]? = nil, services: [MachineService]? = nil) {
        self.image = image
        self.env = env
        self.services = services
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