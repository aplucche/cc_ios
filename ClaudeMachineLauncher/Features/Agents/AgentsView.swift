import SwiftUI

struct AgentsView: View {
    @StateObject private var viewModel = FlyLaunchViewModel()
    @StateObject private var appState = AppStateManager.shared
    @StateObject private var sessionManager = SessionManager.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    configurationSection
                    
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
            .navigationTitle("Claude Agents")
        }
    }
    
    private var configurationSection: some View {
        GroupBox("Configuration") {
            VStack(spacing: 16) {
                SecureField("Fly API Token", text: $viewModel.flyAPIToken)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("App Name", text: $viewModel.appName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textInputAutocapitalization(.never)
                
                TextField("Docker Image", text: $viewModel.image)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                HStack {
                    Text("Region:")
                    Spacer()
                    Picker("Region", selection: $viewModel.region) {
                        Text("Chicago (ord)").tag("ord")
                        Text("Ashburn (iad)").tag("iad")
                        Text("Los Angeles (lax)").tag("lax")
                        Text("London (lhr)").tag("lhr")
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                SecureField("Claude API Key (Optional)", text: $viewModel.claudeAPIKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.vertical, 8)
        }
    }
    
    private var activeMachinesSection: some View {
        GroupBox("Active Machines") {
            VStack(spacing: 12) {
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
}

struct MachineRowView: View {
    let machine: FlyMachine
    let isSelected: Bool
    let isConnected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
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
                            .fill(isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(isConnected ? "Connected" : "Disconnected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("\(machine.state) • \(machine.region)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if !isSelected {
                    Button("Select") {
                        onSelect()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
                
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .onTapGesture {
            onSelect()
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