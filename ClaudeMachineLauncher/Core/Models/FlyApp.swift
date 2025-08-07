import Foundation

struct FlyApp: Codable {
    let id: String
    let name: String
    let status: String
    let organization: FlyOrganization
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

struct FlyAppCreateResponse: Codable {
    let id: String
    let createdAt: Int64
    
    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
    }
}