import Foundation
import Combine
import SwiftUI

// MARK: - Clean API Types

enum FlyMachineState: String {
    case started, starting, stopped, suspended, unknown
    
    init(from apiString: String) {
        self = FlyMachineState(rawValue: apiString.lowercased()) ?? .unknown
    }
}

enum MachineOperation {
    case launching, starting, suspending, deleting, connecting
}

enum MachineAction {
    case pause, activate, delete, none
}

// MARK: - UI State

struct MachineUIState {
    let machine: FlyMachine
    let flyState: FlyMachineState
    let isConnected: Bool
    let operation: MachineOperation?
    
    var statusText: String {
        if let op = operation {
            switch op {
            case .launching: return "Launching..."
            case .starting: return "Starting..."
            case .suspending: return "Suspending..."
            case .deleting: return "Deleting..."
            case .connecting: return "Connecting..."
            }
        }
        
        switch flyState {
        case .started: return isConnected ? "Running" : "Connecting..."
        case .starting: return "Starting..."
        case .stopped, .suspended: return "Suspended"
        case .unknown: return machine.state.capitalized
        }
    }
    
    var statusColor: Color {
        if operation != nil { return .orange }
        
        switch flyState {
        case .started: return isConnected ? .green : .orange
        case .starting: return .orange
        case .stopped, .suspended: return .gray
        case .unknown: return .gray
        }
    }
    
    var isLoading: Bool { operation != nil }
    
    var primaryAction: MachineAction {
        guard !isLoading else { return .none }
        
        switch flyState {
        case .started: return .pause
        case .stopped, .suspended: return .activate
        default: return .none
        }
    }
    
    var secondaryAction: MachineAction {
        guard !isLoading else { return .none }
        
        switch flyState {
        case .stopped, .suspended: return .delete
        default: return .none
        }
    }
}

// MARK: - Unified State Manager

class MachineStateManager: ObservableObject {
    static let shared = MachineStateManager()
    
    @Published private(set) var machines: [FlyMachine] = []
    @Published private(set) var activeMachineId: String?
    @Published private(set) var uiStates: [String: MachineUIState] = [:]
    
    // Direct access for terminal integration
    func getStreamingService(for machineId: String) -> AgentStreamingService? {
        return streamingServices[machineId]
    }
    
    private let flyService: FlyLaunchServiceProtocol
    private var streamingServices: [String: AgentStreamingService] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    private init(flyService: FlyLaunchServiceProtocol = FlyLaunchService()) {
        self.flyService = flyService
    }
    
    // MARK: - Public Interface
    
    var activeMachine: FlyMachine? {
        guard let activeId = activeMachineId else { return nil }
        return machines.first { $0.id == activeId }
    }
    
    func uiState(for machineId: String) -> MachineUIState? {
        uiStates[machineId]
    }
    
    func isConnected(machineId: String) -> Bool {
        uiStates[machineId]?.isConnected ?? false
    }
    
    // MARK: - Machine Management
    
    func launchMachine(config: FlyLaunchConfig) {
        let token = SettingsViewModel.shared.flyAPIToken
        let tempId = "launching-\(UUID().uuidString)"
        let tempMachine = FlyMachine(
            id: tempId,
            name: config.appName,
            state: "launching",
            region: config.region,
            instanceId: nil,
            privateIP: nil,
            config: nil
        )
        
        addMachine(tempMachine, withOperation: .launching)
        
        flyService.launchMachine(config: config, token: token)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.removeMachine(tempId)
                    if case .failure(let error) = completion {
                        Logger.log("Launch failed: \(error.localizedDescription)", category: .system)
                    }
                },
                receiveValue: { [weak self] machine in
                    self?.removeMachine(tempId)
                    self?.addMachine(machine)
                    self?.refreshMachine(machine.id)
                }
            )
            .store(in: &cancellables)
    }
    
    func refreshAllMachines() {
        let appName = SettingsViewModel.shared.defaultAppName
        let token = SettingsViewModel.shared.flyAPIToken
        
        flyService.listMachines(appName: appName, token: token)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        Logger.log("Refresh failed: \(error.localizedDescription)", category: .system)
                    }
                },
                receiveValue: { [weak self] machines in
                    self?.updateMachines(machines)
                }
            )
            .store(in: &cancellables)
    }
    
    func performAction(_ action: MachineAction, on machineId: String) {
        switch action {
        case .activate:
            setActiveMachine(machineId)
            startMachine(machineId)
        case .pause:
            suspendMachine(machineId)
        case .delete:
            deleteMachine(machineId)
        case .none:
            break
        }
    }
    
    func setActiveMachine(_ machineId: String) {
        guard machines.contains(where: { $0.id == machineId }) else { return }
        
        Logger.log("Setting active machine: \(machineId)", category: .system)
        
        // Disconnect from previous machine
        if let previousId = activeMachineId, previousId != machineId {
            disconnectFromMachine(previousId)
        }
        
        activeMachineId = machineId
        
        // Connect to new active machine ONLY if it's running AND connected
        if let state = uiStates[machineId], 
           state.flyState == .started && state.isConnected {
            Logger.log("Machine \(machineId) is started and connected, connecting terminal", category: .system)
            // Terminal connection will be handled by TerminalViewModel binding
        } else if let state = uiStates[machineId], state.flyState == .started {
            Logger.log("Machine \(machineId) is started but not connected, will connect", category: .system)
            connectToMachine(machineId)
        }
    }
    
    // MARK: - Terminal Integration
    
    func sendTerminalMessage(_ message: String) async throws {
        guard let activeId = activeMachineId else { 
            throw URLError(.notConnectedToInternet)
        }
        try await streamingServices[activeId]?.send(message)
    }
    
    private func connectToMachine(_ machineId: String) {
        guard let machine = machines.first(where: { $0.id == machineId }) else { return }
        
        setOperation(machineId, .connecting)
        Logger.log("Connecting to machine: \(machineId)", category: .network)
        
        let appName = SettingsViewModel.shared.defaultAppName
        let token = SettingsViewModel.shared.flyAPIToken
        
        // Use same URL format as working main branch
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "\(appName).fly.dev"
        components.path = "/agents/\(machineId)/stream"
        
        let streamingService = AgentStreamingService()
        streamingServices[machineId] = streamingService
        
        // Bind to connection state changes
        streamingService.connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                Logger.log("Connection state changed for \(machineId): \(state)", category: .network)
                switch state {
                case .connected:
                    self?.updateConnectionState(machineId, connected: true)
                case .failed:
                    self?.clearOperation(machineId)
                case .disconnected:
                    self?.updateConnectionState(machineId, connected: false)
                case .connecting:
                    break // Already set connecting operation
                }
            }
            .store(in: &cancellables)
        
        Task {
            do {
                guard let wsURL = components.url else { 
                    Logger.log("Invalid WebSocket URL components", category: .network)
                    throw URLError(.badURL) 
                }
                Logger.log("Attempting connection to: \(wsURL.absoluteString)", category: .network)
                try await streamingService.connect(to: wsURL, with: token)
            } catch {
                Logger.log("Connection failed for \(machineId): \(error.localizedDescription)", category: .network)
                await MainActor.run {
                    self.clearOperation(machineId)
                }
            }
        }
    }
    
    private func disconnectFromMachine(_ machineId: String) {
        Logger.log("Disconnecting from machine: \(machineId)", category: .network)
        streamingServices[machineId]?.disconnect()
        streamingServices.removeValue(forKey: machineId)
        updateConnectionState(machineId, connected: false)
    }
    
    // MARK: - Machine Operations
    
    private func startMachine(_ machineId: String) {
        setOperation(machineId, .starting)
        
        let appName = SettingsViewModel.shared.defaultAppName
        let token = SettingsViewModel.shared.flyAPIToken
        
        flyService.startMachine(appName: appName, machineId: machineId, token: token)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        Logger.log("Start failed: \(error.localizedDescription)", category: .system)
                        self?.clearOperation(machineId)
                    }
                },
                receiveValue: { [weak self] _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self?.refreshMachine(machineId)
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private func suspendMachine(_ machineId: String) {
        setOperation(machineId, .suspending)
        disconnectFromMachine(machineId)
        
        let appName = SettingsViewModel.shared.defaultAppName
        let token = SettingsViewModel.shared.flyAPIToken
        
        flyService.suspendMachine(appName: appName, machineId: machineId, token: token)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        Logger.log("Suspend failed: \(error.localizedDescription)", category: .system)
                        self?.clearOperation(machineId)
                    }
                },
                receiveValue: { [weak self] _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self?.refreshMachine(machineId)
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private func deleteMachine(_ machineId: String) {
        setOperation(machineId, .deleting)
        disconnectFromMachine(machineId)
        
        let appName = SettingsViewModel.shared.defaultAppName
        let token = SettingsViewModel.shared.flyAPIToken
        
        flyService.deleteMachine(appName: appName, machineId: machineId, token: token)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        Logger.log("Delete failed: \(error.localizedDescription)", category: .system)
                        self?.clearOperation(machineId)
                    } else {
                        self?.removeMachine(machineId)
                        if self?.activeMachineId == machineId {
                            self?.activeMachineId = self?.machines.first?.id
                        }
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
    }
    
    private func refreshMachine(_ machineId: String) {
        let appName = SettingsViewModel.shared.defaultAppName
        let token = SettingsViewModel.shared.flyAPIToken
        
        flyService.getMachineStatus(appName: appName, machineId: machineId, token: token)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        Logger.log("Refresh failed: \(error.localizedDescription)", category: .system)
                    }
                },
                receiveValue: { [weak self] machine in
                    self?.updateMachine(machine)
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Private Helpers
    
    private func addMachine(_ machine: FlyMachine, withOperation operation: MachineOperation? = nil) {
        if !machines.contains(where: { $0.id == machine.id }) {
            machines.append(machine)
        }
        
        uiStates[machine.id] = MachineUIState(
            machine: machine,
            flyState: FlyMachineState(from: machine.state),
            isConnected: false,
            operation: operation
        )
        
        if activeMachineId == nil {
            activeMachineId = machine.id
        }
    }
    
    private func removeMachine(_ machineId: String) {
        machines.removeAll { $0.id == machineId }
        uiStates.removeValue(forKey: machineId)
    }
    
    private func updateMachine(_ machine: FlyMachine) {
        // Add to machines array if not already present
        if let index = machines.firstIndex(where: { $0.id == machine.id }) {
            machines[index] = machine
        } else {
            machines.append(machine)
            Logger.log("Added new machine: \(machine.name) (\(machine.id))", category: .system)
        }
        
        let current = uiStates[machine.id]
        let newState = FlyMachineState(from: machine.state)
        
        uiStates[machine.id] = MachineUIState(
            machine: machine,
            flyState: newState,
            isConnected: current?.isConnected ?? false,
            operation: nil
        )
        
        // Auto-connect if this is the active machine and it just became started
        if activeMachineId == machine.id && current?.flyState != .started && newState == .started {
            Logger.log("Machine \(machine.id) transitioned to started, auto-connecting", category: .system)
            connectToMachine(machine.id)
        }
        
        // If machine is still in transitional state, schedule another refresh
        if newState == .starting {
            Logger.log("Machine \(machine.id) still in transitional state (\(newState)), will refresh again in 3s", category: .system)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.refreshMachine(machine.id)
            }
        }
    }
    
    private func updateMachines(_ newMachines: [FlyMachine]) {
        for machine in newMachines {
            updateMachine(machine)
        }
        
        if activeMachineId == nil, let firstMachine = newMachines.first {
            activeMachineId = firstMachine.id
        }
    }
    
    private func setOperation(_ machineId: String, _ operation: MachineOperation) {
        guard let current = uiStates[machineId] else { return }
        uiStates[machineId] = MachineUIState(
            machine: current.machine,
            flyState: current.flyState,
            isConnected: current.isConnected,
            operation: operation
        )
    }
    
    private func clearOperation(_ machineId: String) {
        guard let current = uiStates[machineId] else { return }
        uiStates[machineId] = MachineUIState(
            machine: current.machine,
            flyState: current.flyState,
            isConnected: current.isConnected,
            operation: nil
        )
    }
    
    private func updateConnectionState(_ machineId: String, connected: Bool) {
        guard let current = uiStates[machineId] else { return }
        uiStates[machineId] = MachineUIState(
            machine: current.machine,
            flyState: current.flyState,
            isConnected: connected,
            operation: connected ? nil : current.operation
        )
    }
}