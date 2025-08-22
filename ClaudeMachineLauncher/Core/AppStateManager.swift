import Foundation
import Combine

class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    
    @Published var machines: [FlyMachine] = []
    @Published var selectedMachineId: String?
    @Published var isDiscoveringMachines = false
    
    private let flyService: FlyLaunchServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    private init(flyService: FlyLaunchServiceProtocol = FlyLaunchService()) {
        self.flyService = flyService
    }
    
    var selectedMachine: FlyMachine? {
        guard let selectedId = selectedMachineId else { return nil }
        return machines.first { $0.id == selectedId }
    }
    
    var hasMachines: Bool {
        !machines.isEmpty
    }
    
    func addMachine(_ machine: FlyMachine, appName: String, token: String) {
        Logger.log("Adding machine: \(machine.id)", category: .system)
        
        // Add to machines list if not already present
        if !machines.contains(where: { $0.id == machine.id }) {
            machines.append(machine)
        }
        
        // Create session in SessionManager
        SessionManager.shared.createSession(for: machine, appName: appName, authToken: token)
        
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
        Logger.log("Removing machine from local state: \(machineId)", category: .system)
        
        machines.removeAll { $0.id == machineId }
        
        // Update selection if needed
        if selectedMachineId == machineId {
            selectedMachineId = machines.first?.id
            if let newId = selectedMachineId {
                SessionManager.shared.setActiveSession(newId)
            }
        }
    }
    
    func deleteMachine(_ machineId: String) {
        Logger.log("Initiating machine deletion: \(machineId)", category: .system)
        SessionManager.shared.deleteMachine(machineId: machineId)
    }
    
    func clearAllMachines() {
        Logger.log("Clearing all machines", category: .system)
        machines.removeAll()
        selectedMachineId = nil
        SessionManager.shared.clearAllSessions()
    }
    
    func updateMachine(_ updatedMachine: FlyMachine) {
        Logger.log("Updating machine state: \(updatedMachine.id) -> \(updatedMachine.state)", category: .system)
        
        if let index = machines.firstIndex(where: { $0.id == updatedMachine.id }) {
            machines[index] = updatedMachine
        }
    }
    
    func refreshMachineState(machineId: String) {
        Logger.log("Refreshing state for machine: \(machineId)", category: .system)
        // This will be called by UI to trigger state refresh
        SessionManager.shared.refreshMachineState(machineId: machineId)
    }
    
    func discoverExistingMachines(appName: String) {
        let token = SettingsViewModel.shared.flyAPIToken
        guard !token.isEmpty else {
            Logger.log("No Fly API token available for machine discovery", category: .system)
            return
        }
        
        Logger.log("Discovering existing machines for app: \(appName)", category: .system)
        isDiscoveringMachines = true
        
        flyService.listMachines(appName: appName, token: token)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isDiscoveringMachines = false
                    switch completion {
                    case .finished:
                        Logger.log("Machine discovery completed", category: .system)
                    case .failure(let error):
                        Logger.log("Machine discovery failed: \(error.localizedDescription)", category: .system)
                        // Don't treat this as a fatal error - user can still launch new machines
                    }
                },
                receiveValue: { [weak self] discoveredMachines in
                    Logger.log("Discovered \(discoveredMachines.count) existing machines", category: .system)
                    self?.integrateMachines(discoveredMachines, appName: appName, token: token)
                }
            )
            .store(in: &cancellables)
    }
    
    private func integrateMachines(_ discoveredMachines: [FlyMachine], appName: String, token: String) {
        for machine in discoveredMachines {
            if let existingIndex = machines.firstIndex(where: { $0.id == machine.id }) {
                // Update existing machine with latest state
                Logger.log("Updating existing machine: \(machine.name) (\(machine.id)) - State: \(machine.state)", category: .system)
                machines[existingIndex] = machine
            } else {
                // Add new machine
                Logger.log("Integrating new machine: \(machine.name) (\(machine.id)) - State: \(machine.state)", category: .system)
                machines.append(machine)
                
                // Create session for this new machine  
                SessionManager.shared.createSession(for: machine, appName: appName, authToken: token)
            }
        }
        
        // Select a machine on startup if none is selected
        if selectedMachineId == nil, !machines.isEmpty {
            // Prefer to select a "started" machine first (user likely wants to use it)
            if let startedMachine = machines.first(where: { $0.state.lowercased() == "started" }) {
                selectMachine(startedMachine.id)
            } else if let firstMachine = machines.first {
                // If no started machines, select first but don't auto-resume (just mark as selected)
                selectedMachineId = firstMachine.id
                // Don't call selectMachine() to avoid auto-resuming suspended machines
                Logger.log("Auto-selected suspended/stopped machine without resuming: \(firstMachine.id)", category: .system)
            }
        }
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