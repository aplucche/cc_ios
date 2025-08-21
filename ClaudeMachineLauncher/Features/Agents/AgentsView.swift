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
        VStack(spacing: 0) {
            // Header with subtle styling
            HStack {
                Text("Active Machines")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("\(appState.machines.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                
                Spacer()
                
                Button(action: {
                    let appName = viewModel.appName
                    appState.discoverExistingMachines(appName: appName)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
                .disabled(appState.isDiscoveringMachines)
                .opacity(appState.isDiscoveringMachines ? 0.5 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            // Machine cards
            LazyVStack(spacing: 12) {
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
            .padding(.horizontal, 20)
        }
    }
    
    private var launchSection: some View {
        VStack(spacing: 0) {
            // Header with subtle styling
            HStack {
                Text("Launch New Machine")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            // Content card with elegant styling
            VStack(spacing: 20) {
                // Status indicator with refined styling
                HStack {
                    if !settings.hasRequiredAPIKeys {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 16, weight: .medium))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Setup Required")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                            Text("Please add API keys in Settings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 16, weight: .medium))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ready to Launch")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            Text("All requirements satisfied")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(settings.hasRequiredAPIKeys ? Color.green.opacity(0.05) : Color.orange.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(settings.hasRequiredAPIKeys ? Color.green.opacity(0.2) : Color.orange.opacity(0.2), lineWidth: 1)
                        )
                )
                
                // Configuration details with better typography
                VStack(spacing: 12) {
                    HStack {
                        Label("App", systemImage: "app.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(viewModel.appName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                    
                    HStack {
                        Label("Region", systemImage: "globe")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(viewModel.region.uppercased())
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .opacity(0.5)
                )
                
                // Repository selection with improved styling
                if settings.hasGitCredentials && !settings.repositories.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Repository", systemImage: "folder.fill")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("Optional")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray5))
                                .cornerRadius(4)
                        }
                        
                        Picker("Repository", selection: $viewModel.selectedRepository) {
                            Text("No Repository").tag(GitRepository?.none)
                            ForEach(settings.repositories) { repository in
                                Text(repository.displayName).tag(repository as GitRepository?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    )
                }
                
                // Launch button with refined styling
                Button(action: {
                    viewModel.launchMachine()
                }) {
                    HStack(spacing: 8) {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.9)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text(viewModel.isLoading ? (viewModel.statusMessage.isEmpty ? "Launching..." : viewModel.statusMessage) : "Launch New Agent")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: viewModel.canLaunch ? 
                                        [Color.blue, Color.blue.opacity(0.8)] : 
                                        [Color.gray, Color.gray.opacity(0.8)]
                                    ),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: viewModel.canLaunch ? Color.blue.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
                    )
                    .foregroundColor(.white)
                }
                .disabled(!viewModel.canLaunch)
                .scaleEffect(viewModel.canLaunch ? 1.0 : 0.95)
                .animation(.easeInOut(duration: 0.2), value: viewModel.canLaunch)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
            )
            .padding(.horizontal, 20)
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
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Repository and machine info section
                VStack(alignment: .leading, spacing: 8) {
                    // Repository name with refined styling
                    HStack(spacing: 8) {
                        if repositoryInfo.hasRepo {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.blue)
                        } else {
                            Image(systemName: "server.rack")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        
                        Text(repositoryInfo.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isSelected ? .blue : .primary)
                            .lineLimit(1)
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                        }
                    }
                    
                    // Machine name with better hierarchy
                    Text(machine.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    // Status indicator with refined design (no machine ID to reduce clutter)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 6, height: 6)
                        Text(stateDisplayText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(stateColor.opacity(0.15))
                    .cornerRadius(6)
                }
                
                Spacer()
                
                // Action buttons section
                VStack(spacing: 8) {
                    // Primary action button with refined styling
                    if sessionManager.loadingMachines.contains(machine.id) {
                        Button(action: {}) {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(.white)
                                Text(loadingText)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                            }
                            .frame(minWidth: 70, maxWidth: 90, minHeight: 28, maxHeight: 28)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(true)
                    } else {
                        if machine.state.lowercased() == "starting" {
                            Button("Starting") {}
                                .font(.system(size: 12, weight: .medium))
                                .frame(minWidth: 70, maxWidth: 90, minHeight: 28, maxHeight: 28)
                                .buttonStyle(.bordered)
                                .disabled(true)
                        } else if isSelected {
                            Button("Suspend") {
                                sessionManager.suspendMachine(machineId: machine.id)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .frame(minWidth: 70, maxWidth: 90, minHeight: 28, maxHeight: 28)
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        } else {
                            Button("Use") {
                                if machine.state.lowercased() == "stopped" || machine.state.lowercased() == "suspended" {
                                    sessionManager.startMachine(machineId: machine.id)
                                }
                                onSelect()
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .frame(minWidth: 70, maxWidth: 90, minHeight: 28, maxHeight: 28)
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    
                    // Remove button with refined styling
                    Button(action: onRemove) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red)
                            .frame(width: 24, height: 24)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(5)
                    }
                }
            }
            
            // Connection status indicator (refined)
            if isSelected {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.orange)
                        .frame(width: 4, height: 4)
                    
                    Text(isConnected ? "Terminal Connected" : "Connecting...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isConnected ? Color.green.opacity(0.05) : Color.orange.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isConnected ? Color.green.opacity(0.2) : Color.orange.opacity(0.2), lineWidth: 0.5)
                        )
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isSelected ? Color.blue.opacity(0.3) : Color(.separator).opacity(0.2), 
                            lineWidth: isSelected ? 1.5 : 0.5
                        )
                )
                .shadow(
                    color: isSelected ? Color.blue.opacity(0.15) : Color.black.opacity(0.05), 
                    radius: isSelected ? 8 : 4, 
                    x: 0, 
                    y: isSelected ? 4 : 2
                )
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
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