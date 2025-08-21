import Foundation
import Combine

class FlyLaunchViewModel: ObservableObject {
    @Published var appName: String
    @Published var image: String
    @Published var region: String
    @Published var selectedRepository: GitRepository?
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var launchedMachine: FlyMachine?
    @Published var statusMessage: String = ""
    
    private let service: FlyLaunchServiceProtocol
    private let settings = SettingsViewModel.shared
    private var cancellables = Set<AnyCancellable>()
    
    init(service: FlyLaunchServiceProtocol = FlyLaunchService()) {
        self.service = service
        
        // Initialize with safe defaults first
        self.appName = "claudeagents"
        self.image = "ghcr.io/aplucche/cc_ios-claude-agent:latest"
        self.region = "ord"
        
        // Then update with settings values asynchronously
        DispatchQueue.main.async { [weak self] in
            self?.loadSettingsValues()
            self?.setupSettingsBindings()
        }
    }
    
    private func loadSettingsValues() {
        self.appName = settings.defaultAppName
        self.image = settings.defaultDockerImage
        self.region = settings.defaultRegion
    }
    
    private func setupSettingsBindings() {
        // Update fields when settings change
        settings.$defaultAppName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newAppName in
                self?.appName = newAppName
            }
            .store(in: &cancellables)
        
        settings.$defaultDockerImage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newImage in
                self?.image = newImage
            }
            .store(in: &cancellables)
        
        settings.$defaultRegion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newRegion in
                self?.region = newRegion
            }
            .store(in: &cancellables)
    }
    
    var canLaunch: Bool {
        settings.hasRequiredAPIKeys && !appName.isEmpty && !image.isEmpty && !isLoading
    }
    
    func launchMachine() {
        guard canLaunch else { 
            Logger.log("Launch blocked - missing required fields", category: .ui)
            return 
        }
        
        Logger.log("User initiated machine launch for app: \(appName), image: \(image)", category: .ui)
        
        // Prepare environment variables for the container
        var envVars: [String: String] = [:]
        
        // Add Anthropic API key if available
        if !settings.claudeAPIKey.isEmpty {
            envVars["ANTHROPIC_API_KEY"] = settings.claudeAPIKey
        }
        
        // Add git credentials if repository is selected and credentials are available
        if selectedRepository != nil && settings.hasGitCredentials {
            envVars["GIT_USERNAME"] = settings.gitUsername
            envVars["GIT_TOKEN"] = settings.gitToken
        }
        
        let config = FlyLaunchConfig(
            appName: appName,
            image: image,
            region: region,
            env: envVars,
            selectedRepository: selectedRepository
        )
        
        isLoading = true
        errorMessage = nil
        
        statusMessage = "Starting deployment..."
        
        service.launchMachine(config: config, token: settings.flyAPIToken)
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
                    AppStateManager.shared.addMachine(machine, appName: self?.appName ?? "", token: self?.settings.flyAPIToken ?? "")
                }
            )
            .store(in: &cancellables)
    }
    
    func refreshStatus() {
        guard let machine = launchedMachine, !settings.flyAPIToken.isEmpty else { 
            Logger.log("Status refresh blocked - no machine or token", category: .ui)
            return 
        }
        
        Logger.log("User refreshing status for machine: \(machine.id)", category: .ui)
        
        service.getMachineStatus(appName: appName, machineId: machine.id, token: settings.flyAPIToken)
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