import Foundation
import SwiftTerm
import Combine

class TerminalViewModel: ObservableObject {
    @Published var host: String = ""
    @Published var username: String = "root"
    @Published var password: String = ""
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var errorMessage: String?
    
    private var terminalView: SwiftTerm.TerminalView?
    private var cancellables = Set<AnyCancellable>()
    
    var canConnect: Bool {
        !host.isEmpty && !username.isEmpty && !isConnecting
    }
    
    func setTerminalView(_ terminalView: SwiftTerm.TerminalView) {
        self.terminalView = terminalView
    }
    
    func connect() {
        guard canConnect else { return }
        
        Logger.log("Attempting SSH connection to \(username)@\(host)", category: .network)
        
        isConnecting = true
        errorMessage = nil
        
        // TODO: Implement actual SSH connection using SwiftSH or similar
        // For now, simulate a connection delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.simulateConnection()
        }
    }
    
    func disconnect() {
        Logger.log("Disconnecting from SSH session", category: .network)
        
        isConnected = false
        isConnecting = false
        errorMessage = nil
        
        // TODO: Close actual SSH connection
    }
    
    private func simulateConnection() {
        // This is a placeholder - we'll implement real SSH later
        if !host.isEmpty {
            isConnected = true
            isConnecting = false
            Logger.log("SSH connection established (simulated)", category: .network)
            
            // Send welcome message to terminal
            terminalView?.feed(text: "Welcome to Claude Machine Terminal\r\n")
            terminalView?.feed(text: "Connected to \(host) as \(username)\r\n")
            terminalView?.feed(text: "$ ")
        } else {
            isConnecting = false
            errorMessage = "Connection failed: Invalid host"
            Logger.log("SSH connection failed", category: .network)
        }
    }
}