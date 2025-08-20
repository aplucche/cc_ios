import Foundation
import Combine
import SwiftTerm

// Extension to convert Combine publishers to async/await
extension AnyPublisher {
    func asyncValue() async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = self
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            break
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                        cancellable?.cancel()
                    },
                    receiveValue: { value in
                        continuation.resume(returning: value)
                        cancellable?.cancel()
                    }
                )
        }
    }
}

struct MachineSession {
    let machine: FlyMachine
    let streamingService: AgentStreamingServiceProtocol
    let url: String
    let authToken: String
    
    var isConnected: Bool {
        streamingService.isConnected
    }
}

class SessionManager: ObservableObject {
    static let shared = SessionManager()
    
    @Published var activeSessions: [String: MachineSession] = [:] // machineId -> session
    @Published var activeSessionId: String?
    
    private var cancellables = Set<AnyCancellable>()
    private let flyService: FlyLaunchServiceProtocol
    
    private init(flyService: FlyLaunchServiceProtocol = FlyLaunchService()) {
        self.flyService = flyService
    }
    
    var activeSession: MachineSession? {
        guard let activeId = activeSessionId else { return nil }
        return activeSessions[activeId]
    }
    
    var sessionCount: Int {
        activeSessions.count
    }
    
    func createSession(for machine: FlyMachine, appName: String, authToken: String) {
        Logger.log("Creating session for machine: \(machine.id)", category: .system)
        
        // Avoid creating duplicate sessions
        if activeSessions[machine.id] != nil {
            Logger.log("Session already exists for machine: \(machine.id)", category: .system)
            return
        }
        
        // Use public app hostname instead of private IP
        let publicHostname = "\(appName).fly.dev"
        
        let streamingService = AgentStreamingService()
        let session = MachineSession(
            machine: machine,
            streamingService: streamingService,
            url: publicHostname,
            authToken: authToken
        )
        
        activeSessions[machine.id] = session
        
        // Set as active if it's the first/only session
        DispatchQueue.main.async { [weak self] in
            if self?.activeSessionId == nil {
                self?.activeSessionId = machine.id
            }
        }
        
        // Auto-connect to the session with delay
        Task {
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 second delay
            await MainActor.run { [weak self] in
                self?.connectToSession(machineId: machine.id)
            }
        }
    }
    
    func connectToSession(machineId: String) {
        guard let session = activeSessions[machineId] else {
            Logger.log("No session found for machine: \(machineId)", category: .system)
            return
        }
        
        Logger.log("Connecting to session: \(machineId)", category: .network)
        
        Task {
            await connectWithStateCheck(session: session, machineId: machineId)
        }
    }
    
    private func connectWithStateCheck(session: MachineSession, machineId: String) async {
        // First, check current machine state
        Logger.log("Checking machine state before connection: \(machineId)", category: .network)
        
        do {
            // Get the app name from the session URL
            let appName = extractAppName(from: session.url)
            
            let updatedMachine = try await flyService.getMachineStatus(
                appName: appName,
                machineId: machineId,
                token: session.authToken
            )
            .asyncValue()
            
            Logger.log("Machine \(machineId) state: \(updatedMachine.state)", category: .network)
            
            // Update the machine state in AppStateManager
            await MainActor.run {
                AppStateManager.shared.updateMachine(updatedMachine)
            }
            
            // If machine is stopped or suspended, start it first
            if updatedMachine.state == "stopped" || updatedMachine.state == "suspended" {
                Logger.log("Machine is \(updatedMachine.state), starting it first...", category: .network)
                
                try await flyService.startMachine(
                    appName: appName,
                    machineId: machineId,
                    token: session.authToken
                )
                .asyncValue()
                
                Logger.log("✅ Machine start command sent, waiting for startup...", category: .network)
                
                // Wait for machine to start up
                try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            }
            
            // Now attempt the connection
            await attemptConnection(session: session, machineId: machineId, retries: 5)
            
        } catch {
            Logger.log("Failed to check/start machine \(machineId): \(error.localizedDescription)", category: .network)
            // Fall back to regular connection attempt
            await attemptConnection(session: session, machineId: machineId, retries: 5)
        }
    }
    
    private func extractAppName(from url: String) -> String {
        // URL format is typically "appname.fly.dev" or similar
        let components = url.components(separatedBy: ".")
        return components.first ?? url
    }
    
    private func attemptConnection(session: MachineSession, machineId: String, retries: Int) async {
        do {
            // First check if the service is responding via HTTP health check
            let healthCheckPassed = await performHealthCheck(url: session.url)
            
            if !healthCheckPassed && retries > 0 {
                Logger.log("Health check failed, retrying in 15 seconds... (\(retries) retries left)", category: .network)
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await attemptConnection(session: session, machineId: machineId, retries: retries - 1)
                return
            }
            
            // Construct WebSocket URL for public hostname
            var components = URLComponents()
            components.scheme = "wss"  // Use secure WebSocket with proper TLS
            components.host = session.url
            components.path = "/agents/default/stream"
            
            guard let wsURL = components.url else {
                Logger.log("Invalid WebSocket URL for: \(session.url)", category: .network)
                return
            }
            
            Logger.log("Attempting WebSocket connection to: \(wsURL.absoluteString)", category: .network)
            Logger.log("Machine state: \(session.machine.state)", category: .network)
            
            try await session.streamingService.connect(to: wsURL, with: session.authToken)
            Logger.log("✅ Connected to machine: \(machineId)", category: .network)
            
        } catch {
            Logger.log("Failed to connect to machine \(machineId): \(error.localizedDescription)", category: .network)
            
            if retries > 0 {
                Logger.log("Retrying connection in 15 seconds... (\(retries) retries left)", category: .network)
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds - longer for deployment
                await attemptConnection(session: session, machineId: machineId, retries: retries - 1)
            } else {
                Logger.log("❌ All connection attempts failed for machine: \(machineId)", category: .network)
            }
        }
    }
    
    private func performHealthCheck(url: String) async -> Bool {
        do {
            // Configure URLSession for better iOS/Fly.io SSL compatibility
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 30
            config.tlsMinimumSupportedProtocolVersion = .TLSv12  // Force TLS 1.2+
            
            let urlSession = URLSession(configuration: config)
            
            let healthURL = URL(string: "https://\(url)/")!
            Logger.log("Health check: \(healthURL.absoluteString)", category: .network)
            
            var request = URLRequest(url: healthURL)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData  // Fix from research
            request.setValue("ClaudeApp/1.0", forHTTPHeaderField: "User-Agent")
            
            let (_, response) = try await urlSession.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                // Accept any response that shows the server is responding
                let success = httpResponse.statusCode < 500
                Logger.log("Health check \(success ? "✅ passed" : "❌ failed") (\(httpResponse.statusCode))", category: .network)
                return success
            }
            
            return false
        } catch {
            Logger.log("Health check failed: \(error.localizedDescription)", category: .network)
            return false
        }
    }
    
    func setActiveSession(_ machineId: String) {
        guard activeSessions[machineId] != nil else {
            Logger.log("Cannot set active session - machine not found: \(machineId)", category: .system)
            return
        }
        
        Logger.log("Setting active session: \(machineId)", category: .system)
        activeSessionId = machineId
    }
    
    func removeSession(machineId: String) {
        Logger.log("Removing session: \(machineId)", category: .system)
        
        // Disconnect if connected
        activeSessions[machineId]?.streamingService.disconnect()
        
        // Remove from sessions
        activeSessions.removeValue(forKey: machineId)
        
        // Update active session if needed
        if activeSessionId == machineId {
            activeSessionId = activeSessions.keys.first
        }
    }
    
    func disconnectSession(machineId: String) {
        Logger.log("Disconnecting session: \(machineId)", category: .network)
        activeSessions[machineId]?.streamingService.disconnect()
    }
    
    func sendToActiveSession(_ message: String) async throws {
        guard let activeSession = activeSession else {
            throw SessionError.noActiveSession
        }
        
        try await activeSession.streamingService.send(message)
    }
    
    func clearAllSessions() {
        Logger.log("Clearing all sessions", category: .system)
        
        for session in activeSessions.values {
            session.streamingService.disconnect()
        }
        
        activeSessions.removeAll()
        activeSessionId = nil
    }
    
    func refreshMachineState(machineId: String) {
        guard let session = activeSessions[machineId] else {
            Logger.log("No session found for machine: \(machineId)", category: .system)
            return
        }
        
        Logger.log("Refreshing machine state: \(machineId)", category: .network)
        
        Task {
            do {
                let appName = extractAppName(from: session.url)
                
                let updatedMachine = try await flyService.getMachineStatus(
                    appName: appName,
                    machineId: machineId,
                    token: session.authToken
                )
                .asyncValue()
                
                Logger.log("Machine \(machineId) refreshed state: \(updatedMachine.state)", category: .network)
                
                await MainActor.run {
                    AppStateManager.shared.updateMachine(updatedMachine)
                }
            } catch {
                Logger.log("Failed to refresh machine state: \(error.localizedDescription)", category: .network)
            }
        }
    }
    
    func startMachine(machineId: String) {
        guard let session = activeSessions[machineId] else {
            Logger.log("No session found for machine: \(machineId)", category: .system)
            return
        }
        
        Logger.log("Starting machine: \(machineId)", category: .network)
        
        Task {
            do {
                let appName = extractAppName(from: session.url)
                
                try await flyService.startMachine(
                    appName: appName,
                    machineId: machineId,
                    token: session.authToken
                )
                .asyncValue()
                
                Logger.log("✅ Machine start command sent: \(machineId)", category: .network)
                
                // Refresh state after a delay
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                refreshMachineState(machineId: machineId)
                
            } catch {
                Logger.log("Failed to start machine: \(error.localizedDescription)", category: .network)
            }
        }
    }
    
    func stopMachine(machineId: String) {
        guard let session = activeSessions[machineId] else {
            Logger.log("No session found for machine: \(machineId)", category: .system)
            return
        }
        
        Logger.log("Stopping machine: \(machineId)", category: .network)
        
        Task {
            do {
                let appName = extractAppName(from: session.url)
                
                try await flyService.stopMachine(
                    appName: appName,
                    machineId: machineId,
                    token: session.authToken
                )
                .asyncValue()
                
                Logger.log("✅ Machine stop command sent: \(machineId)", category: .network)
                
                // Disconnect the session
                disconnectSession(machineId: machineId)
                
                // Refresh state after a delay
                try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                refreshMachineState(machineId: machineId)
                
            } catch {
                Logger.log("Failed to stop machine: \(error.localizedDescription)", category: .network)
            }
        }
    }
}

enum SessionError: LocalizedError {
    case noActiveSession
    case sessionNotFound(String)
    case connectionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noActiveSession:
            return "No active session selected"
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .connectionFailed(let id):
            return "Failed to connect to session: \(id)"
        }
    }
}