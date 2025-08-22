import SwiftUI

struct MachineCardView: View {
    let uiState: MachineUIState
    let onAction: (MachineAction) -> Void
    
    private var repositoryInfo: (name: String, hasRepo: Bool) {
        if let env = uiState.machine.config?.env,
           let repoUrl = env["GIT_REPO_URL"] {
            let repoName = repoUrl.components(separatedBy: "/").last?.replacingOccurrences(of: ".git", with: "") ?? "Unknown Repository"
            return (repoName, true)
        }
        return ("No Repository", false)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Machine info
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: repositoryInfo.hasRepo ? "folder.fill" : "server.rack")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(repositoryInfo.hasRepo ? .blue : .gray)
                        
                        Text(repositoryInfo.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    
                    Text(uiState.machine.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    // Status
                    HStack(spacing: 4) {
                        Circle()
                            .fill(uiState.statusColor)
                            .frame(width: 6, height: 6)
                        Text(uiState.statusText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(uiState.statusColor.opacity(0.15))
                    .cornerRadius(6)
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 8) {
                    PrimaryActionButton(
                        action: uiState.primaryAction,
                        isLoading: uiState.isLoading,
                        statusText: uiState.statusText
                    ) {
                        onAction(uiState.primaryAction)
                    }
                    
                    if uiState.secondaryAction != .none {
                        SecondaryActionButton(action: uiState.secondaryAction) {
                            onAction(uiState.secondaryAction)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}

struct PrimaryActionButton: View {
    let action: MachineAction
    let isLoading: Bool
    let statusText: String
    let onTap: () -> Void
    
    var body: some View {
        Group {
            if isLoading {
                Button(action: {}) {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                        Text(statusText)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .frame(minWidth: 70, maxWidth: 90, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .disabled(true)
            } else {
                switch action {
                case .pause:
                    Button(action: onTap) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(width: 32, height: 28)
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    
                case .activate:
                    Button("Activate", action: onTap)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(minWidth: 70, maxWidth: 90, minHeight: 28)
                        .buttonStyle(.borderedProminent)
                        
                case .none:
                    // Show appropriate text based on current operation or state
                    let buttonText = isLoading ? statusText : "Ready"
                    Button(buttonText) {}
                        .font(.system(size: 12, weight: .medium))
                        .frame(minWidth: 70, maxWidth: 90, minHeight: 28)
                        .buttonStyle(.bordered)
                        .disabled(true)
                        
                case .delete:
                    EmptyView()
                }
            }
        }
    }
}

struct SecondaryActionButton: View {
    let action: MachineAction
    let onTap: () -> Void
    
    var body: some View {
        if action == .delete {
            Button(action: onTap) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red)
            }
            .frame(width: 32, height: 28)
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }
}

#Preview {
    let machine = FlyMachine(
        id: "test-123",
        name: "test-machine",
        state: "started",
        region: "ord",
        instanceId: nil,
        privateIP: nil,
        config: nil
    )
    
    let uiState = MachineUIState(
        machine: machine,
        flyState: .started,
        isConnected: true,
        operation: nil
    )
    
    return MachineCardView(uiState: uiState) { action in
        print("Action: \(action)")
    }
    .padding()
}