import Foundation
import Combine

protocol AgentStreamingServiceProtocol {
    var isConnected: Bool { get }
    var connectionState: AnyPublisher<ConnectionState, Never> { get }
    var messages: AnyPublisher<String, Never> { get }
    
    func connect(to url: URL, with token: String) async throws
    func disconnect()
    func send(_ message: String) async throws
}

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case failed(Error)
}

class AgentStreamingService: AgentStreamingServiceProtocol {
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession
    private let connectionStateSubject = CurrentValueSubject<ConnectionState, Never>(.disconnected)
    private let messagesSubject = PassthroughSubject<String, Never>()
    private var authToken: String = ""
    
    var isConnected: Bool {
        webSocketTask?.state == .running
    }
    
    var connectionState: AnyPublisher<ConnectionState, Never> {
        connectionStateSubject.eraseToAnyPublisher()
    }
    
    var messages: AnyPublisher<String, Never> {
        messagesSubject.eraseToAnyPublisher()
    }
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        
        // Enhanced SSL/TLS configuration for Fly.io WebSocket compatibility
        // Based on research: iOS WebSockets prefer TLS 1.2 over 1.3 for compatibility
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.tlsMaximumSupportedProtocolVersion = .TLSv12  // Force TLS 1.2 for WebSockets
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        
        self.urlSession = URLSession(configuration: config)
    }
    
    func connect(to url: URL, with token: String) async throws {
        Logger.log("Connecting to agent stream: \(url)", category: .network)
        
        disconnect()
        
        self.authToken = token
        connectionStateSubject.send(.connecting)
        
        // Create WebSocket URL with auth token
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "token", value: token)
        ]
        
        guard let wsURL = components?.url else {
            let error = AgentStreamingError.invalidURL
            connectionStateSubject.send(.failed(error))
            throw error
        }
        
        Logger.log("WebSocket URL with token: \(wsURL.absoluteString.replacingOccurrences(of: token, with: "***"))", category: .network)
        
        // Create WebSocket request with auth header and enhanced configuration
        var request = URLRequest(url: wsURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        request.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")
        request.setValue("ClaudeApp/1.0 iOS", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        // Create WebSocket task
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // Start listening for messages immediately to avoid missing server messages
        startListening()
        
        // Brief wait to allow connection handshake
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds (reduced)
        
        // Verify the connection is still running
        guard let task = webSocketTask, task.state == .running else {
            let error = AgentStreamingError.connectionLost
            connectionStateSubject.send(.failed(error))
            throw error
        }
        
        connectionStateSubject.send(.connected)
        Logger.log("WebSocket connection established", category: .network)
    }
    
    func disconnect() {
        Logger.log("Disconnecting from agent stream", category: .network)
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionStateSubject.send(.disconnected)
    }
    
    func send(_ message: String) async throws {
        guard let webSocketTask = webSocketTask, webSocketTask.state == .running else {
            throw AgentStreamingError.notConnected
        }
        
        let message = URLSessionWebSocketTask.Message.string(message)
        try await webSocketTask.send(message)
        
        Logger.log("Sent message to agent: \(message)", category: .network)
    }
    
    private func startListening() {
        guard let webSocketTask = webSocketTask else { return }
        
        Task {
            do {
                Logger.log("Started listening for WebSocket messages", category: .network)
                while webSocketTask.state == .running {
                    let message = try await webSocketTask.receive()
                    await handleMessage(message)
                }
                Logger.log("WebSocket listening stopped - state: \(webSocketTask.state)", category: .network)
            } catch {
                Logger.log("WebSocket listening error: \(error)", category: .network)
                await handleError(error)
            }
        }
    }
    
    @MainActor
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            Logger.log("Received WebSocket message: '\(text.prefix(100))'", category: .network)
            messagesSubject.send(text)
            
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                Logger.log("Received WebSocket data as text: '\(text.prefix(100))'", category: .network)
                messagesSubject.send(text)
            } else {
                Logger.log("Received WebSocket data but failed to convert to UTF-8", category: .network)
            }
            
        @unknown default:
            Logger.log("Received unknown message type from WebSocket", category: .network)
        }
    }
    
    @MainActor
    private func handleError(_ error: Error) {
        Logger.log("WebSocket error: \(error.localizedDescription)", category: .network)
        
        // Provide specific SSL error handling
        if let nsError = error as NSError? {
            if nsError.code == -1200 { // SSL error
                Logger.log("SSL/TLS error detected - certificate or protocol issue", category: .network)
            } else if nsError.code == -9816 { // Network connection lost
                Logger.log("Network connection lost during WebSocket communication", category: .network)
            }
        }
        
        connectionStateSubject.send(.failed(error))
        
        // Attempt to reconnect after a delay
        Task {
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            // Auto-reconnect logic could go here if desired
        }
    }
    
    deinit {
        disconnect()
    }
}

enum AgentStreamingError: LocalizedError {
    case invalidURL
    case notConnected
    case authenticationFailed
    case connectionLost
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid WebSocket URL"
        case .notConnected:
            return "Not connected to agent stream"
        case .authenticationFailed:
            return "Authentication failed"
        case .connectionLost:
            return "Connection to agent lost"
        }
    }
}