import Foundation
import SwiftTerm
import Combine

class TerminalViewModel: ObservableObject {
    @Published var host: String = ""
    @Published var agentId: String = "default"
    @Published var authToken: String = ""
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var errorMessage: String?
    
    private var terminalView: SwiftTerm.TerminalView?
    private var streamingService: AgentStreamingServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(streamingService: AgentStreamingServiceProtocol = AgentStreamingService()) {
        self.streamingService = streamingService
        setupBindings()
    }
    
    var canConnect: Bool {
        !host.isEmpty && !agentId.isEmpty && !authToken.isEmpty && !isConnecting
    }
    
    private func setupBindings() {
        streamingService.connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .disconnected:
                    self?.isConnected = false
                    self?.isConnecting = false
                    self?.errorMessage = nil
                case .connecting:
                    self?.isConnecting = true
                    self?.errorMessage = nil
                case .connected:
                    self?.isConnected = true
                    self?.isConnecting = false
                    self?.errorMessage = nil
                case .failed(let error):
                    self?.isConnected = false
                    self?.isConnecting = false
                    self?.errorMessage = error.localizedDescription
                }
            }
            .store(in: &cancellables)
        
        streamingService.messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.terminalView?.feed(text: message)
            }
            .store(in: &cancellables)
    }
    
    func setTerminalView(_ terminalView: SwiftTerm.TerminalView) {
        self.terminalView = terminalView
        setupTerminalDelegate()
    }
    
    private func setupTerminalDelegate() {
        // Set up terminal input handling - will implement delegate later
        // terminalView?.terminalDelegate = self
    }
    
    func connect() {
        guard canConnect else { return }
        
        Logger.log("Connecting to agent \(agentId) at \(host)", category: .network)
        
        Task {
            do {
                // Construct WebSocket URL
                var components = URLComponents()
                components.scheme = host.hasPrefix("localhost") || host.contains("127.0.0.1") ? "ws" : "wss"
                components.host = host.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "")
                components.port = host.contains("localhost") ? 8080 : nil
                components.path = "/agents/\(agentId)/stream"
                
                guard let url = components.url else {
                    throw AgentStreamingError.invalidURL
                }
                
                try await streamingService.connect(to: url, with: authToken)
                
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    Logger.log("Agent connection failed: \(error)", category: .network)
                }
            }
        }
    }
    
    func disconnect() {
        Logger.log("Disconnecting from agent stream", category: .network)
        streamingService.disconnect()
    }
    
    func sendInput(_ input: String) {
        Task {
            do {
                try await streamingService.send(input)
            } catch {
                Logger.log("Failed to send input: \(error)", category: .network)
            }
        }
    }
}

// TODO: Implement TerminalViewDelegate when we can determine required methods