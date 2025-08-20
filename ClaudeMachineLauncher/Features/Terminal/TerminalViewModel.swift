import Foundation
import SwiftTerm
import Combine
import UIKit

class TerminalViewModel: ObservableObject {
    @Published var errorMessage: String?
    
    private var terminalView: SwiftTerm.TerminalView?
    private var cancellables = Set<AnyCancellable>()
    private var messageBuffer: [String] = []
    
    // Direct access to SessionManager state instead of duplicating
    var activeSessionId: String? { SessionManager.shared.activeSessionId }
    var activeMachineName: String? { SessionManager.shared.activeSession?.machine.name }
    var isConnected: Bool { 
        guard let activeId = activeSessionId else { return false }
        return SessionManager.shared.connectionStates[activeId] ?? false
    }
    var isConnecting: Bool { SessionManager.shared.loadingMachines.contains(activeSessionId ?? "") }
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        // Monitor session changes to bind messages and trigger UI updates
        SessionManager.shared.$activeSessionId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send() // Trigger UI update for computed properties
                if let session = SessionManager.shared.activeSession {
                    self?.bindToSession(session)
                }
            }
            .store(in: &cancellables)
        
        // Monitor connection state changes for UI updates
        SessionManager.shared.$connectionStates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send() // Trigger UI update
            }
            .store(in: &cancellables)
        
        // Monitor loading state changes for UI updates
        SessionManager.shared.$loadingMachines
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send() // Trigger UI update
            }
            .store(in: &cancellables)
    }
    
    private var sessionCancellables = Set<AnyCancellable>()
    
    private func bindToSession(_ session: MachineSession) {
        // Clear previous session bindings to avoid duplicates
        sessionCancellables.removeAll()
        
        // Only bind to messages - connection state is handled by SessionManager
        session.streamingService.messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                Logger.log("TerminalViewModel received message: '\(message.prefix(100))'", category: .ui)
                self?.handleIncomingMessage(message)
            }
            .store(in: &sessionCancellables)
        
        // Handle errors from connection failures
        session.streamingService.connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if case .failed(let error) = state {
                    self?.errorMessage = error.localizedDescription
                } else {
                    self?.errorMessage = nil
                }
            }
            .store(in: &sessionCancellables)
    }
    
    private func handleIncomingMessage(_ message: String) {
        if let terminalView = terminalView {
            terminalView.feed(text: message)
        } else {
            messageBuffer.append(message)
        }
    }
    
    private func replayBufferedMessages() {
        guard !messageBuffer.isEmpty else { return }
        for message in messageBuffer {
            terminalView?.feed(text: message)
        }
        messageBuffer.removeAll()
    }
    
    
    func setTerminalView(_ terminalView: SwiftTerm.TerminalView) {
        self.terminalView = terminalView
        setupTerminalDelegate()
        replayBufferedMessages()
    }
    
    private func setupTerminalDelegate() {
        terminalView?.terminalDelegate = self
    }
    
    
    func disconnect() {
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
        // Log raw bytes first for debugging
        let rawBytes = Array(data)
        Logger.log("Terminal raw input bytes: \(rawBytes.map { String(format: "0x%02X", $0) }.joined(separator: " "))", category: .ui)
        
        var processedData = data
        
        // Handle special keys for better terminal compatibility
        if data.count == 1 {
            let byte = data.first!
            switch byte {
            case 0x7F: // DEL key - convert to backspace
                processedData = [0x08] // BS
                Logger.log("Converted DEL (0x7F) to BS (0x08)", category: .ui)
            case 0x0D: // CR (carriage return) - try just CR first
                processedData = [0x0D] // Keep as CR
                Logger.log("Keeping CR (0x0D) as-is", category: .ui)
            default:
                break
            }
        }
        
        let string = String(bytes: processedData, encoding: .utf8) ?? ""
        Logger.log("Terminal processed input: '\(string.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\u{08}", with: "\\b"))'", category: .ui)
        sendInput(string)
    }
    
    func scrolled(source: SwiftTerm.TerminalView, position: Double) {
        // Handle scroll events if needed
    }
    
    func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {
        // Terminal title changes - could be used for UI updates if needed
    }
    
    func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
        guard newCols > 0 && newRows > 0 else { return }
        
        Task {
            let sizeMessage = "{\"type\":\"resize\",\"rows\":\(newRows),\"cols\":\(newCols)}"
            try? await SessionManager.shared.sendToActiveSession(sizeMessage)
        }
    }
    
    func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
        UIPasteboard.general.string = String(data: content, encoding: .utf8)
    }
    
    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
        // Directory changes - could update UI if needed
    }
    
    func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String:String]) {
        if let fixedup = link.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: fixedup) {
            UIApplication.shared.open(url)
        }
    }
    
    func bell(source: SwiftTerm.TerminalView) {
        // Terminal bell - could add haptic feedback
    }
    
    func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {
        // iTerm-specific content handling
    }
    
    func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
        // Terminal buffer range changes
    }
}