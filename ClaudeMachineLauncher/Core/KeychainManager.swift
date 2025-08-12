import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
    private let serviceName = "ClaudeMachineLauncher"
    
    func storeKey(_ key: String, forService service: String) -> Bool {
        guard !key.isEmpty else {
            Logger.log("Cannot store empty key for service: \(service)", category: .system)
            return false
        }
        
        let keyData = key.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: service,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete any existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            Logger.log("Successfully stored key for service: \(service)", category: .system)
            return true
        } else {
            Logger.log("Failed to store key for service: \(service), status: \(status)", category: .system)
            return false
        }
    }
    
    func retrieveKey(forService service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let keyData = result as? Data,
           let key = String(data: keyData, encoding: .utf8) {
            Logger.log("Successfully retrieved key for service: \(service)", category: .system)
            return key
        } else if status == errSecItemNotFound {
            Logger.log("No key found for service: \(service)", category: .system)
            return nil
        } else {
            Logger.log("Failed to retrieve key for service: \(service), status: \(status)", category: .system)
            return nil
        }
    }
    
    func deleteKey(forService service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess {
            Logger.log("Successfully deleted key for service: \(service)", category: .system)
            return true
        } else if status == errSecItemNotFound {
            Logger.log("No key to delete for service: \(service)", category: .system)
            return true // Consider this success
        } else {
            Logger.log("Failed to delete key for service: \(service), status: \(status)", category: .system)
            return false
        }
    }
    
    func clearAllKeys() {
        _ = deleteKey(forService: "flyapi")
        _ = deleteKey(forService: "anthropic")
        Logger.log("Cleared all API keys from keychain", category: .system)
    }
}

// Service identifiers for consistency
extension KeychainManager {
    static let flyAPIService = "flyapi"
    static let anthropicAPIService = "anthropic"
}