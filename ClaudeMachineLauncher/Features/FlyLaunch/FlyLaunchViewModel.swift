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
        guard canLaunch else { return }
        
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
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] machine in
                    self?.launchedMachine = machine
                    self?.machineStatus = machine.state
                    self?.errorMessage = nil
                }
            )
            .store(in: &cancellables)
    }
    
    func refreshStatus() {
        guard let machine = launchedMachine, !flyAPIToken.isEmpty else { return }
        
        service.getMachineStatus(appName: appName, machineId: machine.id, token: flyAPIToken)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Status refresh failed: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] updatedMachine in
                    self?.launchedMachine = updatedMachine
                    self?.machineStatus = updatedMachine.state
                }
            )
            .store(in: &cancellables)
    }
    
    func clearMachine() {
        launchedMachine = nil
        machineStatus = ""
        errorMessage = nil
    }
}