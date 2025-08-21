import SwiftUI

struct AgentsView: View {
    @StateObject private var viewModel = FlyLaunchViewModel()
    @EnvironmentObject private var appState: AppStateManager
    @EnvironmentObject private var sessionManager: SessionManager
    @EnvironmentObject private var settings: SettingsViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Machine Discovery Status
                if appState.isDiscoveringMachines {
                    discoverySection
                }
                
                // Active Machines Section
                if appState.hasMachines {
                    activeMachinesSection
                }
                
                // Combined Launch Section (was Configuration + Launch)
                launchSection
                
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
                        isConnected: (sessionManager.connectionStates[machine.id] ?? false) && (sessionManager.activeSessionId == machine.id),
                        onSelect: {
                            appState.selectMachine(machine.id)
                            // For started machines, also ensure connection
                            if machine.state == "started" {
                                sessionManager.connectToSession(machineId: machine.id)
                            }
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
                // Configuration Info (collapsed from separate section)
                VStack(spacing: 8) {
                    if !settings.hasRequiredAPIKeys {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Please add API keys in Settings")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Spacer()
                        }
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Ready to launch")
                                .font(.caption)
                                .foregroundColor(.green)
                            Spacer()
                        }
                    }
                    
                    HStack {
                        Text("App: \(viewModel.appName)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Region: \(viewModel.region.uppercased())")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(6)
                
                // Repository Selection
                if settings.hasGitCredentials && !settings.repositories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Repository (Optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Picker("Repository", selection: $viewModel.selectedRepository) {
                            Text("No Repository").tag(GitRepository?.none)
                            ForEach(settings.repositories) { repository in
                                Text(repository.displayName).tag(repository as GitRepository?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
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
    
    @EnvironmentObject private var sessionManager: SessionManager
    @EnvironmentObject private var appState: AppStateManager
    
    private var repositoryInfo: (name: String, hasRepo: Bool) {
        if let env = machine.config?.env,
           let repoUrl = env["GIT_REPO_URL"] {
            let repoName = repoUrl.components(separatedBy: "/").last?.replacingOccurrences(of: ".git", with: "") ?? "Unknown Repository"
            return (repoName, true)
        }
        return ("No Repository", false)
    }
    
    private var loadingText: String {
        switch machine.state.lowercased() {
        case "starting":
            return "Starting..."
        case "stopped", "suspended":
            return "Starting..."
        case "started":
            return "Suspending..."
        default:
            return "Processing..."
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    // Repository name (emphasized)
                    HStack {
                        if repositoryInfo.hasRepo {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                        Text(repositoryInfo.name)
                            .font(.headline)
                            .fontWeight(.medium)
                            .foregroundColor(isSelected ? .blue : .primary)
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                    }
                    
                    // Machine name (secondary)
                    Text(machine.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // State indicator (compact)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 8, height: 8)
                        Text(stateDisplayText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        
                        // Machine ID (deemphasized, shorter)
                        Text(machine.id.prefix(8) + "...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(spacing: 6) {
                    // Single primary action button (does the logical next step)
                    if sessionManager.loadingMachines.contains(machine.id) {
                        Button(action: {}) {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text(loadingText)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.caption)
                        .disabled(true)
                    } else {
                        // Handle special states first
                        if machine.state.lowercased() == "starting" {
                            Button("Starting...") {}
                                .buttonStyle(.bordered)
                                .font(.caption)
                                .disabled(true)
                        } else if isSelected {
                            // Currently active machine - allow suspending
                            Button("Suspend") {
                                sessionManager.suspendMachine(machineId: machine.id)
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        } else {
                            // Any non-active machine (stopped, suspended, or started-but-not-selected)
                            Button("Use") {
                                if machine.state.lowercased() == "stopped" || machine.state.lowercased() == "suspended" {
                                    // For stopped/suspended machines, start them first
                                    sessionManager.startMachine(machineId: machine.id)
                                }
                                // Always select to make active (SessionManager handles resume logic)
                                onSelect()
                            }
                            .buttonStyle(.borderedProminent)
                            .font(.caption)
                        }
                    }
                    
                    // Secondary actions
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            // Connection status bar (simplified)
            if isSelected {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(isConnected ? "Terminal Connected" : "Connecting...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
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