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
        let string = String(bytes: data, encoding: .utf8) ?? ""
        Logger.log("Terminal input: '\(string)'", category: .ui)
        sendInput(string)
    }
    
    func scrolled(source: SwiftTerm.TerminalView, position: Double) {
        // Handle scroll events if needed
    }
    
    func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {
        Logger.log("Terminal title: \(title)", category: .ui)
    }
    
    func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
        Logger.log("Terminal size: \(newCols)x\(newRows)", category: .ui)
        // TODO: Consider notifying remote end of size change if protocol supports it
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