import Foundation
import Testing
@testable import ClaudeMachineLauncher

@Test("KeychainManager stores and retrieves keys securely")
func testKeychainManagerBasicOperations() {
    let keychain = KeychainManager.shared
    let testKey = "test-api-key-\(UUID().uuidString)"
    let testService = "test-service"
    
    // Test storing a key
    let storeResult = keychain.storeKey(testKey, forService: testService)
    #expect(storeResult == true)
    
    // Test retrieving the key
    let retrievedKey = keychain.retrieveKey(forService: testService)
    #expect(retrievedKey == testKey)
    
    // Test deleting the key
    let deleteResult = keychain.deleteKey(forService: testService)
    #expect(deleteResult == true)
    
    // Test that key is gone
    let missingKey = keychain.retrieveKey(forService: testService)
    #expect(missingKey == nil)
}

@Test("KeychainManager handles API key services")
func testKeychainAPIKeyServices() {
    let keychain = KeychainManager.shared
    let flyKey = "fly-test-\(UUID().uuidString)"
    let anthropicKey = "anthropic-test-\(UUID().uuidString)"
    
    // Store both keys
    #expect(keychain.storeKey(flyKey, forService: KeychainManager.flyAPIService))
    #expect(keychain.storeKey(anthropicKey, forService: KeychainManager.anthropicAPIService))
    
    // Retrieve both keys
    #expect(keychain.retrieveKey(forService: KeychainManager.flyAPIService) == flyKey)
    #expect(keychain.retrieveKey(forService: KeychainManager.anthropicAPIService) == anthropicKey)
    
    // Clear all keys
    keychain.clearAllKeys()
    
    // Verify both keys are cleared
    #expect(keychain.retrieveKey(forService: KeychainManager.flyAPIService) == nil)
    #expect(keychain.retrieveKey(forService: KeychainManager.anthropicAPIService) == nil)
}

@Test("SettingsViewModel integrates with Keychain")
func testSettingsViewModelKeychain() async {
    // Use shared instance and clean it first
    let settings = SettingsViewModel.shared
    settings.clearAPIKeys()
    
    let testFlyKey = "fly-integration-test-\(UUID().uuidString)"
    let testAnthropicKey = "anthropic-integration-test-\(UUID().uuidString)"
    
    // Set keys through Settings
    settings.flyAPIToken = testFlyKey
    settings.claudeAPIKey = testAnthropicKey
    
    // Wait for async operations
    await TestIsolation.waitForAsync()
    
    // Verify they're stored in keychain
    #expect(KeychainManager.shared.retrieveKey(forService: KeychainManager.flyAPIService) == testFlyKey)
    #expect(KeychainManager.shared.retrieveKey(forService: KeychainManager.anthropicAPIService) == testAnthropicKey)
    
    // Test hasRequiredAPIKeys
    #expect(settings.hasRequiredAPIKeys == true)
    
    // Clear and verify
    settings.clearAPIKeys()
    #expect(settings.hasRequiredAPIKeys == false)
    #expect(KeychainManager.shared.retrieveKey(forService: KeychainManager.flyAPIService) == nil)
}