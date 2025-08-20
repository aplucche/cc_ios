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
    let autoStopMachines: String?
    let autoStartMachines: Bool?
    let minMachinesRunning: Int?
    
    enum CodingKeys: String, CodingKey {
        case ports
        case protocolType = "protocol"
        case internalPort = "internal_port"
        case autoStopMachines = "auto_stop_machines"
        case autoStartMachines = "auto_start_machines"
        case minMachinesRunning = "min_machines_running"
    }
    
    init(ports: [Port], protocolType: String, internalPort: Int, autoStopMachines: String? = "suspend", autoStartMachines: Bool? = true, minMachinesRunning: Int? = 0) {
        self.ports = ports
        self.protocolType = protocolType
        self.internalPort = internalPort
        self.autoStopMachines = autoStopMachines
        self.autoStartMachines = autoStartMachines
        self.minMachinesRunning = minMachinesRunning
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