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
    
    init() {
        setupBindings()
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
                guard let sessionId = sessionId else { return nil }
                return SessionManager.shared.activeSessions[sessionId]
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (session: MachineSession) in
                self?.bindToSession(session)
            }
            .store(in: &cancellables)
    }
    
    private func bindToSession(_ session: MachineSession) {
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