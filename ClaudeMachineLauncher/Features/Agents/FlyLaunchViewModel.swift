import Foundation
import Combine

class FlyLaunchViewModel: ObservableObject {
    @Published var flyAPIToken: String = ""
    @Published var appName: String = "claudeagents"
    @Published var image: String = "ghcr.io/aplucche/cc_ios-claude-agent:latest"
    @Published var region: String = "ord"
    @Published var claudeAPIKey: String = ""
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var launchedMachine: FlyMachine?
    @Published var statusMessage: String = ""
    
    private let service: FlyLaunchServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(service: FlyLaunchServiceProtocol = FlyLaunchService()) {
        self.service = service
    }
    
    var canLaunch: Bool {
        !flyAPIToken.isEmpty && !appName.isEmpty && !image.isEmpty && !isLoading
    }
    
    func launchMachine() {
        guard canLaunch else { 
            Logger.log("Launch blocked - missing required fields", category: .ui)
            return 
        }
        
        Logger.log("User initiated machine launch for app: \(appName), image: \(image)", category: .ui)
        
        let config = FlyLaunchConfig(
            appName: appName,
            image: image,
            region: region
        )
        
        isLoading = true
        errorMessage = nil
        
        statusMessage = "Starting deployment..."
        
        service.launchMachine(config: config, token: flyAPIToken)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    self?.statusMessage = ""
                    if case .failure(let error) = completion {
                        Logger.log("Launch failed: \(error.localizedDescription)", category: .ui)
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] machine in
                    Logger.log("Launch succeeded: \(machine.id) in state \(machine.state)", category: .ui)
                    self?.launchedMachine = machine
                    self?.errorMessage = nil
                    self?.statusMessage = ""
                    
                    // Add machine to multi-session management
                    if let machineURL = self?.constructMachineURL(machine: machine) {
                        AppStateManager.shared.addMachine(machine, url: machineURL, token: self?.flyAPIToken ?? "")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func refreshStatus() {
        guard let machine = launchedMachine, !flyAPIToken.isEmpty else { 
            Logger.log("Status refresh blocked - no machine or token", category: .ui)
            return 
        }
        
        Logger.log("User refreshing status for machine: \(machine.id)", category: .ui)
        
        service.getMachineStatus(appName: appName, machineId: machine.id, token: flyAPIToken)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        Logger.log("Status refresh failed: \(error.localizedDescription)", category: .ui)
                        self?.errorMessage = "Status refresh failed: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] updatedMachine in
                    Logger.log("Status updated: \(updatedMachine.state)", category: .ui)
                    self?.launchedMachine = updatedMachine
                }
            )
            .store(in: &cancellables)
    }
    
    func clearMachine() {
        Logger.log("User cleared machine data", category: .ui)
        launchedMachine = nil
        errorMessage = nil
        statusMessage = ""
        AppStateManager.shared.clearAllMachines()
    }
    
    private func constructMachineURL(machine: FlyMachine) -> String? {
        // Try multiple hostname formats for Fly machines
        // Option 1: Machine-specific hostname (if it exists)
        // Option 2: Use private IP directly (IPv6)
        // Option 3: Fallback to app hostname
        
        // Fly machines are accessible via app hostname once the app is deployed
        // The key issue is that we need to deploy the app first to get the hostname
        return "\(appName).fly.dev"
    }
}