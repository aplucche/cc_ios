import Foundation
import SwiftTerm
import Combine
import UIKit

class TerminalViewModel: ObservableObject {
    @Published var errorMessage: String?
    
    private var terminalView: SwiftTerm.TerminalView?
    private var cancellables = Set<AnyCancellable>()
    private var messageBuffer: [String] = []
    
    // Direct access to MachineStateManager state
    var activeSessionId: String? { MachineStateManager.shared.activeMachineId }
    var activeMachineName: String? { MachineStateManager.shared.activeMachine?.name }
    var isConnected: Bool { 
        guard let activeId = activeSessionId else { return false }
        return MachineStateManager.shared.isConnected(machineId: activeId)
    }
    var isConnecting: Bool { 
        guard let activeId = activeSessionId else { return false }
        return MachineStateManager.shared.uiState(for: activeId)?.operation == .connecting
    }
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        // Monitor active machine changes and rebind to streaming service
        MachineStateManager.shared.$activeMachineId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] activeId in
                self?.objectWillChange.send() // Trigger UI update for computed properties
                self?.bindToActiveStreamingService(activeId)
            }
            .store(in: &cancellables)
        
        // Monitor UI state changes for connection and operation updates
        // This will trigger rebinding when machines become connected
        MachineStateManager.shared.$uiStates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] uiStates in
                self?.objectWillChange.send() // Trigger UI update
                
                // Check if active machine just became connected - rebind if so
                if let activeId = MachineStateManager.shared.activeMachineId,
                   let activeState = uiStates[activeId],
                   activeState.isConnected {
                    self?.bindToActiveStreamingService(activeId)
                }
            }
            .store(in: &cancellables)
    }
    
    private var streamingCancellables = Set<AnyCancellable>()
    
    private func bindToActiveStreamingService(_ machineId: String?) {
        // Clear previous bindings
        streamingCancellables.removeAll()
        
        guard let machineId = machineId else {
            Logger.log("No active machine to bind to", category: .ui)
            return
        }
        
        // KEY FIX: Only bind if streaming service exists AND machine is connected
        guard let streamingService = MachineStateManager.shared.getStreamingService(for: machineId),
              MachineStateManager.shared.isConnected(machineId: machineId) else {
            Logger.log("No streaming service or not connected for machine: \(machineId) - will retry when connected", category: .ui)
            return
        }
        
        Logger.log("Binding terminal to streaming service for machine: \(machineId)", category: .ui)
        
        // Bind to messages from the active machine's streaming service
        streamingService.messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                Logger.log("TerminalViewModel received message: '\(message.prefix(100))'", category: .ui)
                self?.handleIncomingMessage(message)
            }
            .store(in: &streamingCancellables)
        
        // Handle connection state changes
        streamingService.connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                Logger.log("TerminalViewModel connection state for \(machineId): \(state)", category: .ui)
                switch state {
                case .failed(let error):
                    self?.errorMessage = error.localizedDescription
                case .connected:
                    self?.errorMessage = nil
                    // Trigger terminal refresh by sending resize (causes SIGWINCH)
                    // This refreshes the prompt and any running applications without disrupting them
                    Task {
                        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 second delay
                        
                        // Send resize with standard terminal size to trigger SIGWINCH
                        let sizeMessage = "{\"type\":\"resize\",\"rows\":24,\"cols\":80}"
                        try? await self?.sendInput(sizeMessage)
                        Logger.log("Sent terminal refresh resize to wake up suspended session", category: .ui)
                    }
                default:
                    self?.errorMessage = nil
                }
            }
            .store(in: &streamingCancellables)
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
    
    
    func sendInput(_ input: String) {
        Task {
            do {
                try await MachineStateManager.shared.sendTerminalMessage(input)
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
            try? await MachineStateManager.shared.sendTerminalMessage(sizeMessage)
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