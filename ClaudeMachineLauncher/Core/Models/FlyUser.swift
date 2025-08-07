import Foundation

struct FlyUser: Codable {
    let id: String
    let email: String
    let name: String
    let personal_org: FlyOrganization
    
    enum CodingKeys: String, CodingKey {
        case id, email, name
        case personal_org
    }
}

struct FlyOrganization: Codable {
    let id: String?
    let name: String
    let slug: String
}