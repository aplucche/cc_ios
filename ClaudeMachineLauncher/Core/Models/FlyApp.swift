import Foundation

struct FlyApp: Codable {
    let id: String
    let name: String
    let status: String
    let organization: FlyOrganization
}

struct FlyOrganization: Codable {
    let id: String?
    let name: String
    let slug: String
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