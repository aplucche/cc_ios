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
        
        // Load non-sensitive settings from UserDefaults
        self.defaultAppName = UserDefaults.standard.string(forKey: "defaultAppName") ?? "claude"
        self.defaultDockerImage = UserDefaults.standard.string(forKey: "defaultDockerImage") ?? "python:3.11-slim"
        self.defaultRegion = UserDefaults.standard.string(forKey: "defaultRegion") ?? "ord"
        self.autoLaunchClaude = UserDefaults.standard.bool(forKey: "autoLaunchClaude")
        
        Logger.log("Settings loaded from Keychain and UserDefaults", category: .system)
    }
    
    var hasRequiredAPIKeys: Bool {
        !flyAPIToken.isEmpty && !claudeAPIKey.isEmpty
    }
    
    func clearAPIKeys() {
        flyAPIToken = ""
        claudeAPIKey = ""
        KeychainManager.shared.clearAllKeys()
        Logger.log("API keys cleared from settings and keychain", category: .system)
    }
}