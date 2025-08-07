import Testing
@testable import ClaudeMachineLauncher

struct FlyLaunchConfigTests {
    
    @Test func testInitWithDefaults() {
        let config = FlyLaunchConfig(appName: "test-app", image: "nginx")
        
        #expect(config.appName == "test-app")
        #expect(config.image == "nginx")
        #expect(config.region == "ord")
        #expect(config.env.isEmpty)
        #expect(config.internalPort == 8080)
    }
    
    @Test func testInitWithCustomValues() {
        let env = ["PORT": "3000", "NODE_ENV": "production"]
        let config = FlyLaunchConfig(
            appName: "custom-app",
            image: "node:18",
            region: "lax",
            env: env,
            internalPort: 3000
        )
        
        #expect(config.appName == "custom-app")
        #expect(config.image == "node:18")
        #expect(config.region == "lax")
        #expect(config.env["PORT"] == "3000")
        #expect(config.internalPort == 3000)
    }
    
    @Test func testToMachineConfig() {
        let config = FlyLaunchConfig(
            appName: "test-app",
            image: "nginx",
            env: ["DEBUG": "true"]
        )
        
        let machineConfig = config.toMachineConfig()
        
        #expect(machineConfig.image == "nginx")
        #expect(machineConfig.env?["DEBUG"] == "true")
        #expect(machineConfig.services?.count == 1)
        #expect(machineConfig.services?.first?.internalPort == 8080)
    }
    
    @Test func testFlyLaunchRequest() {
        let config = FlyLaunchConfig(appName: "test-app", image: "nginx")
        let request = FlyLaunchRequest(config: config)
        
        #expect(request.name == nil)
        #expect(request.region == "ord")
        #expect(request.config.image == "nginx")
    }
}