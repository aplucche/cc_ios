import Foundation

struct FlyApp: Codable {
    let id: String
    let name: String
    let status: String
    let deployed: Bool
    let hostname: String
    let appUrl: String?
    let version: Int
    let release: FlyRelease?
    let organization: FlyOrganization
    
    enum CodingKeys: String, CodingKey {
        case id, name, status, deployed, hostname, version, release, organization
        case appUrl = "app_url"
    }
}

struct FlyRelease: Codable {
    let id: String
    let version: Int
    let stable: Bool
    let inProgress: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, version, stable
        case inProgress = "in_progress"
    }
}

struct FlyAppCreateRequest: Codable {
    let appName: String
    let orgSlug: String
    
    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case orgSlug = "org_slug"  
    }
}