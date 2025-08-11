import Foundation
import Combine
import SwiftTerm

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
    
    private init() {}
    
    var activeSession: MachineSession? {
        guard let activeId = activeSessionId else { return nil }
        return activeSessions[activeId]
    }
    
    var sessionCount: Int {
        activeSessions.count
    }
    
    func createSession(for machine: FlyMachine, url: String, authToken: String) {
        Logger.log("Creating session for machine: \(machine.id)", category: .system)
        
        // Avoid creating duplicate sessions
        if activeSessions[machine.id] != nil {
            Logger.log("Session already exists for machine: \(machine.id)", category: .system)
            return
        }
        
        let streamingService = AgentStreamingService()
        let session = MachineSession(
            machine: machine,
            streamingService: streamingService,
            url: url,
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
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
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
            // Wait for machine to be ready (containers need time to boot)
            try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            
            await attemptConnection(session: session, machineId: machineId, retries: 5)
        }
    }
    
    private func attemptConnection(session: MachineSession, machineId: String, retries: Int) async {
        do {
            // Construct WebSocket URL
            var components = URLComponents()
            components.scheme = session.url.contains("[") ? "ws" : "wss"  // Use ws for private IPs
            components.host = session.url
            components.path = "/agents/default/stream"
            
            // For private IPs, use port 8080 directly
            if session.url.contains("[") {
                components.port = 8080
            }
            
            guard let wsURL = components.url else {
                Logger.log("Invalid WebSocket URL for: \(session.url)", category: .network)
                return
            }
            
            Logger.log("Attempting WebSocket connection to: \(wsURL.absoluteString)", category: .network)
            Logger.log("Machine state: \(session.machine.state)", category: .network)
            
            try await session.streamingService.connect(to: wsURL, with: session.authToken)
            Logger.log("Connected to machine: \(machineId)", category: .network)
            
        } catch {
            Logger.log("Failed to connect to machine \(machineId): \(error.localizedDescription)", category: .network)
            
            if retries > 0 {
                Logger.log("Retrying connection in 10 seconds... (\(retries) retries left)", category: .network)
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                await attemptConnection(session: session, machineId: machineId, retries: retries - 1)
            } else {
                Logger.log("All connection attempts failed for machine: \(machineId)", category: .network)
            }
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