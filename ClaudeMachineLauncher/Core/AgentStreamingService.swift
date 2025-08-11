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
        
        // Create WebSocket request with auth header
        var request = URLRequest(url: wsURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        
        // Create WebSocket task
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // Start listening for messages
        startListening()
        
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
                while webSocketTask.state == .running {
                    let message = try await webSocketTask.receive()
                    await handleMessage(message)
                }
            } catch {
                await handleError(error)
            }
        }
    }
    
    @MainActor
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            messagesSubject.send(text)
            Logger.log("Received message from agent", category: .network)
            
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                messagesSubject.send(text)
            }
            
        @unknown default:
            Logger.log("Received unknown message type from WebSocket", category: .network)
        }
    }
    
    @MainActor
    private func handleError(_ error: Error) {
        Logger.log("WebSocket error: \(error.localizedDescription)", category: .network)
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