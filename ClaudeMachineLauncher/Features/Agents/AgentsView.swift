import SwiftUI

struct AgentsView: View {
    @StateObject private var viewModel = FlyLaunchViewModel()
    @StateObject private var appState = AppStateManager.shared
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var settings = SettingsViewModel.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                configurationSection
                
                // Machine Discovery Status
                if appState.isDiscoveringMachines {
                    discoverySection
                }
                
                // Active Machines Section
                if appState.hasMachines {
                    activeMachinesSection
                }
                
                // Launch New Machine Section
                launchSection
                
                // Current Machine Status (if launching)
                if let machine = viewModel.launchedMachine {
                    currentMachineSection(machine)
                }
                
                if !viewModel.statusMessage.isEmpty {
                    statusSection(viewModel.statusMessage)
                }
                
                if let errorMessage = viewModel.errorMessage {
                    errorSection(errorMessage)
                }
            }
            .padding()
        }
        .onAppear {
            discoverExistingMachines()
        }
    }
    
    private var configurationSection: some View {
        GroupBox("Configuration") {
            VStack(spacing: 12) {
                if !settings.hasRequiredAPIKeys {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Please add API keys in Settings")
                            .foregroundColor(.orange)
                        Spacer()
                    }
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Ready to launch")
                            .foregroundColor(.green)
                        Spacer()
                    }
                }
                
                VStack(spacing: 8) {
                    HStack {
                        Text("App:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(viewModel.appName)
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Text("Region:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(viewModel.region.uppercased())
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Image:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(viewModel.image.split(separator: "/").last?.split(separator: ":").first ?? "Unknown")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                    }
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            }
            .padding(.vertical, 8)
        }
    }
    
    private var discoverySection: some View {
        GroupBox("Discovering Machines") {
            HStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(0.8)
                Text("Looking for existing machines...")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }
    
    private var activeMachinesSection: some View {
        GroupBox("Active Machines") {
            VStack(spacing: 12) {
                HStack {
                    Text("Machines (\(appState.machines.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: {
                        let appName = viewModel.appName
                        appState.discoverExistingMachines(appName: appName)
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .disabled(appState.isDiscoveringMachines)
                }
                
                ForEach(appState.machines, id: \.id) { machine in
                    MachineRowView(
                        machine: machine,
                        isSelected: appState.selectedMachineId == machine.id,
                        isConnected: sessionManager.activeSessions[machine.id]?.isConnected ?? false,
                        onSelect: {
                            appState.selectMachine(machine.id)
                        },
                        onRemove: {
                            appState.removeMachine(machine.id)
                        }
                    )
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var launchSection: some View {
        GroupBox("Launch New Machine") {
            VStack(spacing: 16) {
                Button(action: {
                    viewModel.launchMachine()
                }) {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(viewModel.isLoading ? (viewModel.statusMessage.isEmpty ? "Launching..." : viewModel.statusMessage) : "Launch New Agent")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.canLaunch ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(!viewModel.canLaunch)
            }
            .padding(.vertical, 8)
        }
    }
    
    private func currentMachineSection(_ machine: FlyMachine) -> some View {
        GroupBox("Machine Status") {
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(label: "ID", value: machine.id)
                InfoRow(label: "Name", value: machine.name)
                InfoRow(label: "State", value: machine.state)
                InfoRow(label: "Region", value: machine.region)
                
                if let privateIP = machine.privateIP {
                    InfoRow(label: "Private IP", value: privateIP)
                }
                
                HStack(spacing: 12) {
                    Button("Refresh Status") {
                        viewModel.refreshStatus()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Launch New") {
                        viewModel.clearMachine()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 8)
            }
            .padding(.vertical, 8)
        }
    }
    
    private func statusSection(_ message: String) -> some View {
        GroupBox {
            HStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(0.8)
                Text(message)
                    .foregroundColor(.blue)
                Spacer()
            }
        }
    }
    
    private func errorSection(_ message: String) -> some View {
        GroupBox {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .foregroundColor(.red)
                Spacer()
            }
        }
    }
    
    private func discoverExistingMachines() {
        // Only discover if we have API keys and no machines yet (for automatic discovery on startup)
        guard settings.hasRequiredAPIKeys else {
            Logger.log("Skipping machine discovery - no API keys", category: .system)
            return
        }
        
        guard !appState.hasMachines else {
            Logger.log("Skipping automatic machine discovery - already have machines", category: .system)
            return
        }
        
        // Use the app name from the launch configuration
        let appName = viewModel.appName
        Logger.log("Starting automatic machine discovery for app: \(appName)", category: .system)
        appState.discoverExistingMachines(appName: appName)
    }
}

struct MachineRowView: View {
    let machine: FlyMachine
    let isSelected: Bool
    let isConnected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var appState = AppStateManager.shared
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(machine.name)
                            .font(.headline)
                            .foregroundColor(isSelected ? .blue : .primary)
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                    }
                    
                    HStack {
                        Text(machine.id.prefix(8) + "...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(stateColor)
                                .frame(width: 8, height: 8)
                            Text(stateDisplayText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text("\(machine.state) • \(machine.region)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Button(action: {
                            appState.refreshMachineState(machineId: machine.id)
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        
                        if machine.state == "stopped" || machine.state == "suspended" {
                            Button {
                                sessionManager.startMachine(machineId: machine.id)
                            } label: {
                                HStack(spacing: 4) {
                                    if sessionManager.loadingMachines.contains(machine.id) {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                                    Text(sessionManager.loadingMachines.contains(machine.id) ? "Starting..." : "Start")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .font(.caption)
                            .disabled(sessionManager.loadingMachines.contains(machine.id))
                        } else if machine.state == "started" || machine.state == "starting" {
                            Button {
                                sessionManager.stopMachine(machineId: machine.id)
                            } label: {
                                HStack(spacing: 4) {
                                    if sessionManager.loadingMachines.contains(machine.id) {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                                    Text(sessionManager.loadingMachines.contains(machine.id) ? "Stopping..." : "Stop")
                                }
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                            .disabled(sessionManager.loadingMachines.contains(machine.id))
                        }
                        
                        if !isSelected && machine.state == "started" {
                            Button("Select") {
                                onSelect()
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                    
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            // Connection status bar
            if isSelected {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isConnected ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(isConnected ? "Terminal Connected" : "Terminal Disconnected")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if machine.state == "started" && !isConnected {
                        Button("Connect") {
                            sessionManager.connectToSession(machineId: machine.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.caption2)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .onTapGesture {
            if machine.state == "started" {
                onSelect()
            }
        }
    }
    
    private var stateColor: Color {
        switch machine.state.lowercased() {
        case "started":
            return .green
        case "starting":
            return .orange
        case "stopped":
            return .red
        case "suspended":
            return .yellow
        default:
            return .gray
        }
    }
    
    private var stateDisplayText: String {
        switch machine.state.lowercased() {
        case "started":
            return "Running"
        case "starting":
            return "Starting"
        case "stopped":
            return "Stopped"
        case "suspended":
            return "Suspended"
        default:
            return machine.state.capitalized
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    AgentsView()
}