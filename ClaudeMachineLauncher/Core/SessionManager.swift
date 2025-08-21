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
    @Published var loadingMachines: Set<String> = [] // Simple loading state
    @Published var connectionStates: [String: Bool] = [:] // machineId -> isConnected
    
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
        connectionStates[machine.id] = false
        
        // Subscribe to connection state changes
        streamingService.connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.connectionStates[machine.id] = (state == .connected)
            }
            .store(in: &cancellables)
        
        // Do NOT auto-set as active or auto-connect
        // Let AppStateManager explicitly control which machine is selected
        // Only the explicitly selected machine should connect
    }
    
    func connectToSession(machineId: String) {
        guard let session = activeSessions[machineId] else {
            Logger.log("No session found for machine: \(machineId)", category: .system)
            return
        }
        
        Logger.log("Connecting to session: \(machineId)", category: .network)
        
        Task {
            await attemptConnection(session: session, machineId: machineId)
        }
    }
    
    private func attemptConnection(session: MachineSession, machineId: String) async {
        // Construct WebSocket URL
        var components = URLComponents()
        components.scheme = "wss"
        components.host = session.url
        components.path = "/agents/\(machineId)/stream"
        
        guard let wsURL = components.url else {
            Logger.log("Invalid WebSocket URL for: \(session.url)", category: .network)
            return
        }
        
        // Simple direct connection with basic retry
        for attempt in 1...3 {
            do {
                Logger.log("Connection attempt \(attempt)/3 to: \(wsURL.absoluteString)", category: .network)
                try await session.streamingService.connect(to: wsURL, with: session.authToken)
                Logger.log("✅ Connected to machine: \(machineId)", category: .network)
                return
            } catch {
                Logger.log("Attempt \(attempt) failed: \(error.localizedDescription)", category: .network)
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 second delay
                }
            }
        }
        
        Logger.log("❌ All connection attempts failed for machine: \(machineId)", category: .network)
    }
    
    private func extractAppName(from url: String) -> String {
        // URL format is typically "appname.fly.dev" or similar
        let components = url.components(separatedBy: ".")
        return components.first ?? url
    }
    
    func setActiveSession(_ machineId: String) {
        guard activeSessions[machineId] != nil else {
            Logger.log("Cannot set active session - machine not found: \(machineId)", category: .system)
            return
        }
        
        // Disconnect all other sessions first
        for (id, session) in activeSessions {
            if id != machineId {
                session.streamingService.disconnect()
                connectionStates[id] = false
            }
        }
        
        Logger.log("Setting active session: \(machineId)", category: .system)
        activeSessionId = machineId
        
        // Connect to the new active session if not already connected
        if connectionStates[machineId] != true {
            connectToSession(machineId: machineId)
        }
    }
    
    func removeSession(machineId: String) {
        Logger.log("Removing session: \(machineId)", category: .system)
        
        // Disconnect if connected
        activeSessions[machineId]?.streamingService.disconnect()
        
        // Remove from sessions and connection states
        activeSessions.removeValue(forKey: machineId)
        connectionStates.removeValue(forKey: machineId)
        
        // Update active session if needed
        if activeSessionId == machineId {
            activeSessionId = activeSessions.keys.first
        }
    }
    
    func disconnectSession(machineId: String) {
        Logger.log("Disconnecting session: \(machineId)", category: .network)
        activeSessions[machineId]?.streamingService.disconnect()
        connectionStates[machineId] = false
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
        connectionStates.removeAll()
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
        
        loadingMachines.insert(machineId)
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
            
            await MainActor.run {
                self.loadingMachines.remove(machineId)
            }
        }
    }
    
    func stopMachine(machineId: String) {
        guard let session = activeSessions[machineId] else {
            Logger.log("No session found for machine: \(machineId)", category: .system)
            return
        }
        
        loadingMachines.insert(machineId)
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
                await MainActor.run {
                    self.disconnectSession(machineId: machineId)
                }
                
                // Refresh state after a delay
                try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                refreshMachineState(machineId: machineId)
                
            } catch {
                Logger.log("Failed to stop machine: \(error.localizedDescription)", category: .network)
            }
            
            await MainActor.run {
                self.loadingMachines.remove(machineId)
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