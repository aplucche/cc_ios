import Foundation
import SwiftTerm
import Combine
import UIKit

class TerminalViewModel: ObservableObject {
    @Published var activeSessionId: String?
    @Published var activeMachineName: String?
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var errorMessage: String?
    
    private var terminalView: SwiftTerm.TerminalView?
    private var cancellables = Set<AnyCancellable>()
    private var sessionCancellables = Set<AnyCancellable>()
    private var messageBuffer: [String] = []
    
    // Legacy properties for backward compatibility
    @Published var host: String = ""
    @Published var agentId: String = "default"
    @Published var authToken: String = ""
    
    init() {
        setupBindings()
    }
    
    var canConnect: Bool {
        !host.isEmpty && !agentId.isEmpty && !authToken.isEmpty && !isConnecting
    }
    
    private func setupBindings() {
        // Monitor SessionManager for active session changes
        SessionManager.shared.$activeSessionId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessionId in
                self?.activeSessionId = sessionId
                self?.updateConnectionState()
            }
            .store(in: &cancellables)
        
        // Monitor AppStateManager for selected machine changes
        AppStateManager.shared.$selectedMachineId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] machineId in
                if let machineId = machineId,
                   let machine = AppStateManager.shared.selectedMachine {
                    self?.activeMachineName = machine.name
                    self?.updateConnectionState()
                }
            }
            .store(in: &cancellables)
        
        // Monitor active session messages and connection state
        setupActiveSessionBinding()
    }
    
    private func setupActiveSessionBinding() {
        // This will be called whenever active session changes
        SessionManager.shared.$activeSessionId
            .compactMap { (sessionId: String?) -> MachineSession? in
                guard let sessionId = sessionId else {
                    Logger.log("No active session ID", category: .ui)
                    return nil
                }
                let session = SessionManager.shared.activeSessions[sessionId]
                if session == nil {
                    Logger.log("No session found for ID: \(sessionId)", category: .ui)
                }
                return session
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (session: MachineSession) in
                Logger.log("Active session changed, binding to new session", category: .ui)
                self?.bindToSession(session)
            }
            .store(in: &cancellables)
    }
    
    private func bindToSession(_ session: MachineSession) {
        Logger.log("Binding to session for machine: \(session.machine.id)", category: .ui)
        
        // Clear existing session bindings to avoid duplicates
        sessionCancellables.removeAll()
        
        // Bind to session's streaming service
        session.streamingService.connectionState
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
            .store(in: &sessionCancellables)
        
        session.streamingService.messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                Logger.log("TerminalViewModel received message: '\(message.prefix(100))'", category: .ui)
                self?.handleIncomingMessage(message)
            }
            .store(in: &sessionCancellables)
    }
    
    private func handleIncomingMessage(_ message: String) {
        if let terminalView = terminalView {
            Logger.log("Feeding message to SwiftTerm", category: .ui)
            terminalView.feed(text: message)
        } else {
            Logger.log("TerminalView not available - buffering message", category: .ui)
            messageBuffer.append(message)
        }
    }
    
    private func replayBufferedMessages() {
        guard !messageBuffer.isEmpty else { return }
        
        Logger.log("Replaying \(messageBuffer.count) buffered messages", category: .ui)
        for message in messageBuffer {
            terminalView?.feed(text: message)
        }
        messageBuffer.removeAll()
    }
    
    private func updateConnectionState() {
        guard let activeId = activeSessionId,
              let session = SessionManager.shared.activeSessions[activeId] else {
            isConnected = false
            isConnecting = false
            return
        }
        
        isConnected = session.isConnected
    }
    
    func setTerminalView(_ terminalView: SwiftTerm.TerminalView) {
        Logger.log("Setting terminal view in TerminalViewModel", category: .ui)
        self.terminalView = terminalView
        setupTerminalDelegate()
        
        // Replay any buffered messages immediately
        replayBufferedMessages()
    }
    
    private func setupTerminalDelegate() {
        terminalView?.terminalDelegate = self
    }
    
    // Legacy connect method - now handled automatically by SessionManager
    func connect() {
        Logger.log("Legacy connect called - sessions managed automatically", category: .network)
    }
    
    func disconnect() {
        Logger.log("Disconnecting active session", category: .network)
        if let activeId = activeSessionId {
            SessionManager.shared.disconnectSession(machineId: activeId)
        }
    }
    
    func sendInput(_ input: String) {
        Task {
            do {
                try await SessionManager.shared.sendToActiveSession(input)
            } catch {
                Logger.log("Failed to send input: \(error)", category: .network)
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - TerminalViewDelegate
extension TerminalViewModel: TerminalViewDelegate {
    func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
        var processedData = data
        
        // Handle special keys for better terminal compatibility
        if data.count == 1 {
            let byte = data.first!
            switch byte {
            case 0x7F: // DEL key - convert to backspace
                processedData = [0x08] // BS
            case 0x0D: // CR (carriage return) - convert to newline  
                processedData = [0x0A] // LF
            default:
                break
            }
        }
        
        let string = String(bytes: processedData, encoding: .utf8) ?? ""
        Logger.log("Terminal input: '\(string.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\u{08}", with: "\\b"))'", category: .ui)
        sendInput(string)
    }
    
    func scrolled(source: SwiftTerm.TerminalView, position: Double) {
        // Handle scroll events if needed
    }
    
    func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {
        Logger.log("Terminal title: \(title)", category: .ui)
    }
    
    func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
        // Only log meaningful size changes (ignore 0x0 during initialization)
        if newCols > 0 && newRows > 0 {
            Logger.log("Terminal size: \(newCols)x\(newRows)", category: .ui)
            // TODO: Consider notifying remote end of size change if protocol supports it
        }
    }
    
    func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
        if let string = String(data: content, encoding: .utf8) {
            UIPasteboard.general.string = string
            Logger.log("Copied to clipboard: \(string.prefix(50))", category: .ui)
        }
    }
    
    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
        if let directory = directory {
            Logger.log("Directory changed: \(directory)", category: .ui)
        }
    }
    
    func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String:String]) {
        Logger.log("Link requested: \(link)", category: .ui)
        if let fixedup = link.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            if let url = URL(string: fixedup) {
                UIApplication.shared.open(url)
            }
        }
    }
    
    func bell(source: SwiftTerm.TerminalView) {
        Logger.log("Terminal bell", category: .ui)
        // Could add haptic feedback here if desired
    }
    
    func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {
        // Handle iTerm-specific content if needed
        Logger.log("iTerm content received: \(content.count) bytes", category: .ui)
    }
    
    func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
        // Handle terminal buffer range changes
        Logger.log("Range changed: \(startY)-\(endY)", category: .ui)
    }
}