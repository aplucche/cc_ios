import Foundation

class SettingsViewModel: ObservableObject {
    @Published var flyAPIToken: String {
        didSet { UserDefaults.standard.set(flyAPIToken, forKey: "flyAPIToken") }
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
        didSet { UserDefaults.standard.set(claudeAPIKey, forKey: "claudeAPIKey") }
    }
    
    @Published var autoLaunchClaude: Bool {
        didSet { UserDefaults.standard.set(autoLaunchClaude, forKey: "autoLaunchClaude") }
    }
    
    init() {
        // Load values from UserDefaults
        self.flyAPIToken = UserDefaults.standard.string(forKey: "flyAPIToken") ?? ""
        self.defaultAppName = UserDefaults.standard.string(forKey: "defaultAppName") ?? "claude"
        self.defaultDockerImage = UserDefaults.standard.string(forKey: "defaultDockerImage") ?? "python:3.11-slim"
        self.defaultRegion = UserDefaults.standard.string(forKey: "defaultRegion") ?? "ord"
        self.claudeAPIKey = UserDefaults.standard.string(forKey: "claudeAPIKey") ?? ""
        self.autoLaunchClaude = UserDefaults.standard.bool(forKey: "autoLaunchClaude")
        
        Logger.log("Settings loaded from UserDefaults", category: .system)
    }
}