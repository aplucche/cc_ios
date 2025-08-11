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
            .compactMap { SessionManager.shared.activeSessions[$0 ?? ""] }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                self?.bindToSession(session)
            }
            .store(in: &cancellables)
    }
    
    private func bindToSession(_ session: MachineSession) {
        // For now, we'll keep all cancellables - optimize later if needed
        
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
            .store(in: &cancellables)
        
        session.streamingService.messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.terminalView?.feed(text: message)
            }
            .store(in: &cancellables)
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
    }
    
    private func setupTerminalDelegate() {
        // TODO: Implement TerminalViewDelegate properly
        // terminalView?.terminalDelegate = self
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
// TODO: Uncomment when we determine correct protocol methods
/*
extension TerminalViewModel: TerminalViewDelegate {
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let string = String(bytes: data, encoding: .utf8) ?? ""
        sendInput(string)
    }
    
    func scrolled(source: TerminalView, position: Double) {
        // Handle scroll events if needed
    }
    
    func setTerminalTitle(source: TerminalView, title: String) {
        Logger.log("Terminal title: \(title)", category: .ui)
    }
    
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        Logger.log("Terminal size: \(newCols)x\(newRows)", category: .ui)
    }
    
    func clipboardCopy(source: TerminalView, content: Data) {
        if let string = String(data: content, encoding: .utf8) {
            UIPasteboard.general.string = string
        }
    }
}
*/