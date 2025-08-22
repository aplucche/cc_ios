import SwiftUI

struct AgentsView: View {
    @StateObject private var viewModel = FlyLaunchViewModel()
    @StateObject private var machineState = MachineStateManager.shared
    @EnvironmentObject private var settings: SettingsViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Active Machines Section
                if !machineState.machines.isEmpty {
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
    
    
    
    private var activeMachinesSection: some View {
        VStack(spacing: 0) {
            // Header with subtle styling
            HStack {
                Text("Active Machines")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("\(machineState.machines.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                
                Spacer()
                
                Button(action: {
                    machineState.refreshAllMachines()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            // Machine cards
            LazyVStack(spacing: 12) {
                ForEach(machineState.machines, id: \.id) { machine in
                    if let uiState = machineState.uiState(for: machine.id) {
                        MachineCardView(uiState: uiState) { action in
                            machineState.performAction(action, on: machine.id)
                            
                            // Set as active when activating
                            if action == .activate {
                                machineState.setActiveMachine(machine.id)
                            }
                        }
                    }
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
        
        guard machineState.machines.isEmpty else {
            Logger.log("Skipping automatic machine discovery - already have machines", category: .system)
            return
        }
        
        Logger.log("Starting automatic machine discovery", category: .system)
        machineState.refreshAllMachines()
    }
}

#Preview {
    AgentsView()
}