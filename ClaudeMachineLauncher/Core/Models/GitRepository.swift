import Foundation

struct GitRepository: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var url: String
    var branch: String
    let createdAt: Date
    
    init(name: String, url: String, branch: String = "main") {
        self.id = UUID()
        self.name = name
        self.url = url
        self.branch = branch
        self.createdAt = Date()
    }
    
    var displayName: String {
        return name.isEmpty ? url : name
    }
    
    var isValidURL: Bool {
        guard let url = URL(string: url) else { return false }
        return url.scheme == "https" && (url.host?.contains("github.com") == true || url.host?.contains("gitlab.com") == true || url.host?.contains("bitbucket.org") == true)
    }
}

// MARK: - Repository Storage
extension GitRepository {
    static let userDefaultsKey = "savedRepositories"
    
    static func loadRepositories() -> [GitRepository] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return []
        }
        
        do {
            let repositories = try JSONDecoder().decode([GitRepository].self, from: data)
            Logger.log("Loaded \(repositories.count) repositories from UserDefaults", category: .system)
            return repositories
        } catch {
            Logger.log("Failed to load repositories: \(error)", category: .system)
            return []
        }
    }
    
    static func saveRepositories(_ repositories: [GitRepository]) {
        do {
            let data = try JSONEncoder().encode(repositories)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            Logger.log("Saved \(repositories.count) repositories to UserDefaults", category: .system)
        } catch {
            Logger.log("Failed to save repositories: \(error)", category: .system)
        }
    }
}