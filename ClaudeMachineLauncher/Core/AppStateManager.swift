import Foundation
import Combine

class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    
    @Published var machines: [FlyMachine] = []
    @Published var selectedMachineId: String?
    
    private init() {}
    
    var selectedMachine: FlyMachine? {
        guard let selectedId = selectedMachineId else { return nil }
        return machines.first { $0.id == selectedId }
    }
    
    var hasMachines: Bool {
        !machines.isEmpty
    }
    
    func addMachine(_ machine: FlyMachine, url: String, token: String) {
        Logger.log("Adding machine: \(machine.id)", category: .system)
        
        // Add to machines list if not already present
        if !machines.contains(where: { $0.id == machine.id }) {
            machines.append(machine)
        }
        
        // Create session in SessionManager
        SessionManager.shared.createSession(for: machine, url: url, authToken: token)
        
        // Select as active if it's the first machine
        DispatchQueue.main.async { [weak self] in
            if self?.selectedMachineId == nil {
                self?.selectMachine(machine.id)
            }
        }
    }
    
    func selectMachine(_ machineId: String) {
        Logger.log("Selecting machine: \(machineId)", category: .system)
        selectedMachineId = machineId
        SessionManager.shared.setActiveSession(machineId)
    }
    
    func removeMachine(_ machineId: String) {
        Logger.log("Removing machine: \(machineId)", category: .system)
        
        machines.removeAll { $0.id == machineId }
        SessionManager.shared.removeSession(machineId: machineId)
        
        // Update selection if needed
        if selectedMachineId == machineId {
            selectedMachineId = machines.first?.id
            if let newId = selectedMachineId {
                SessionManager.shared.setActiveSession(newId)
            }
        }
    }
    
    func clearAllMachines() {
        Logger.log("Clearing all machines", category: .system)
        machines.removeAll()
        selectedMachineId = nil
        SessionManager.shared.clearAllSessions()
    }
    
    // MARK: - Legacy support (for backward compatibility)
    var launchedMachineURL: String? {
        guard let machine = selectedMachine else { return nil }
        return "\(machine.id).\(machine.name).fly.dev"
    }
    
    var authToken: String? {
        SessionManager.shared.activeSession?.authToken
    }
    
    var hasActiveMachine: Bool {
        selectedMachine != nil
    }
}