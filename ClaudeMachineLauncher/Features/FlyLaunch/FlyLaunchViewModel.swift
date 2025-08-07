import Foundation
import Combine

class FlyLaunchViewModel: ObservableObject {
    @Published var flyAPIToken: String = ""
    @Published var appName: String = ""
    @Published var image: String = "nginx"
    @Published var region: String = "ord"
    @Published var claudeAPIKey: String = ""
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var launchedMachine: FlyMachine?
    @Published var machineStatus: String = ""
    
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
        
        service.launchMachine(config: config, token: flyAPIToken)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        Logger.log("Launch failed: \(error.localizedDescription)", category: .ui)
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] machine in
                    Logger.log("Launch succeeded: \(machine.id) in state \(machine.state)", category: .ui)
                    self?.launchedMachine = machine
                    self?.machineStatus = machine.state
                    self?.errorMessage = nil
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
                    self?.machineStatus = updatedMachine.state
                }
            )
            .store(in: &cancellables)
    }
    
    func clearMachine() {
        Logger.log("User cleared machine data", category: .ui)
        launchedMachine = nil
        machineStatus = ""
        errorMessage = nil
    }
}