import Foundation
import Combine

class SettingsViewModel: ObservableObject {
    static let shared = SettingsViewModel()
    
    @Published var flyAPIToken: String {
        didSet {
            if !flyAPIToken.isEmpty {
                _ = KeychainManager.shared.storeKey(flyAPIToken, forService: KeychainManager.flyAPIService)
            }
        }
    }
    
    @Published var defaultAppName: String {
        didSet { UserDefaults.standard.set(defaultAppName, forKey: "defaultAppName") }
    }
    
    @Published var defaultDockerImage: String {
        didSet { UserDefaults.standard.set(defaultDockerImage, forKey: "defaultDockerImage") }
    }
    
    @Published var defaultRegion: String {
        didSet { UserDefaults.standard.set(defaultRegion, forKey: "defaultRegion") }
    }
    
    @Published var claudeAPIKey: String {
        didSet {
            if !claudeAPIKey.isEmpty {
                _ = KeychainManager.shared.storeKey(claudeAPIKey, forService: KeychainManager.anthropicAPIService)
            }
        }
    }
    
    @Published var autoLaunchClaude: Bool {
        didSet { UserDefaults.standard.set(autoLaunchClaude, forKey: "autoLaunchClaude") }
    }
    
    @Published var gitUsername: String {
        didSet {
            if !gitUsername.isEmpty {
                _ = KeychainManager.shared.storeKey(gitUsername, forService: KeychainManager.gitUsernameService)
            }
        }
    }
    
    @Published var gitToken: String {
        didSet {
            if !gitToken.isEmpty {
                _ = KeychainManager.shared.storeKey(gitToken, forService: KeychainManager.gitTokenService)
            }
        }
    }
    
    @Published var repositories: [GitRepository] = [] {
        didSet { GitRepository.saveRepositories(repositories) }
    }
    
    private init() {
        // Migrate from UserDefaults to Keychain (one-time)
        let oldFlyToken = UserDefaults.standard.string(forKey: "flyAPIToken")
        let oldClaudeKey = UserDefaults.standard.string(forKey: "claudeAPIKey")
        
        // Load API keys from Keychain (or migrate from UserDefaults)
        if let oldFlyToken = oldFlyToken, !oldFlyToken.isEmpty,
           KeychainManager.shared.retrieveKey(forService: KeychainManager.flyAPIService) == nil {
            _ = KeychainManager.shared.storeKey(oldFlyToken, forService: KeychainManager.flyAPIService)
            UserDefaults.standard.removeObject(forKey: "flyAPIToken")
            Logger.log("Migrated Fly API token from UserDefaults to Keychain", category: .system)
        }
        
        if let oldClaudeKey = oldClaudeKey, !oldClaudeKey.isEmpty,
           KeychainManager.shared.retrieveKey(forService: KeychainManager.anthropicAPIService) == nil {
            _ = KeychainManager.shared.storeKey(oldClaudeKey, forService: KeychainManager.anthropicAPIService)
            UserDefaults.standard.removeObject(forKey: "claudeAPIKey")
            Logger.log("Migrated Claude API key from UserDefaults to Keychain", category: .system)
        }
        
        // Load from secure storage
        self.flyAPIToken = KeychainManager.shared.retrieveKey(forService: KeychainManager.flyAPIService) ?? ""
        self.claudeAPIKey = KeychainManager.shared.retrieveKey(forService: KeychainManager.anthropicAPIService) ?? ""
        self.gitUsername = KeychainManager.shared.retrieveKey(forService: KeychainManager.gitUsernameService) ?? ""
        self.gitToken = KeychainManager.shared.retrieveKey(forService: KeychainManager.gitTokenService) ?? ""
        
        // Load non-sensitive settings from UserDefaults
        self.defaultAppName = UserDefaults.standard.string(forKey: "defaultAppName") ?? "claudeagents"
        self.defaultDockerImage = UserDefaults.standard.string(forKey: "defaultDockerImage") ?? "ghcr.io/aplucche/cc_ios-claude-agent:latest"
        self.defaultRegion = UserDefaults.standard.string(forKey: "defaultRegion") ?? "ord"
        self.autoLaunchClaude = UserDefaults.standard.bool(forKey: "autoLaunchClaude")
        self.repositories = GitRepository.loadRepositories()
        
        Logger.log("Settings loaded from Keychain and UserDefaults", category: .system)
    }
    
    var hasRequiredAPIKeys: Bool {
        !flyAPIToken.isEmpty && !claudeAPIKey.isEmpty
    }
    
    var hasGitCredentials: Bool {
        !gitUsername.isEmpty && !gitToken.isEmpty
    }
    
    func clearAPIKeys() {
        flyAPIToken = ""
        claudeAPIKey = ""
        gitUsername = ""
        gitToken = ""
        KeychainManager.shared.clearAllKeys()
        Logger.log("API keys cleared from settings and keychain", category: .system)
    }
    
    func addRepository(_ repository: GitRepository) {
        repositories.append(repository)
        Logger.log("Added repository: \(repository.name)", category: .system)
    }
    
    func updateRepository(_ repository: GitRepository) {
        if let index = repositories.firstIndex(where: { $0.id == repository.id }) {
            repositories[index] = repository
            Logger.log("Updated repository: \(repository.name)", category: .system)
        }
    }
    
    func deleteRepository(_ repository: GitRepository) {
        repositories.removeAll { $0.id == repository.id }
        Logger.log("Deleted repository: \(repository.name)", category: .system)
    }
}