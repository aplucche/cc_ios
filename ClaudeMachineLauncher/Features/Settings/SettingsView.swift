import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel.shared
    
    var body: some View {
        NavigationView {
            Form {
                apiKeysSection
                flySection
                claudeSection
                aboutSection
            }
            .navigationTitle("Settings")
        }
    }
    
    private var apiKeysSection: some View {
        Section("API Keys") {
            SecureField("Fly API Token", text: $viewModel.flyAPIToken)
                .textInputAutocapitalization(.never)
            
            SecureField("Claude API Key", text: $viewModel.claudeAPIKey)
                .textInputAutocapitalization(.never)
            
            if viewModel.hasRequiredAPIKeys {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Saved securely")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Button("Clear API Keys", role: .destructive) {
                viewModel.clearAPIKeys()
            }
            .disabled(!viewModel.hasRequiredAPIKeys)
        }
    }
    
    private var flySection: some View {
        Section(header: Text("Fly.io Configuration"), 
                footer: Text("App name should match your Fly.io app. Container image should include the Claude Code CLI.")) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("App Name", text: $viewModel.defaultAppName)
                    .textInputAutocapitalization(.never)
                Text("Used for machine discovery and deployment")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                TextField("Container Image", text: $viewModel.defaultDockerImage)
                    .textInputAutocapitalization(.never)
                Text("Docker image with Claude Code CLI pre-installed")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Picker("Default Region", selection: $viewModel.defaultRegion) {
                Text("Chicago (ord)").tag("ord")
                Text("Ashburn (iad)").tag("iad")
                Text("Los Angeles (lax)").tag("lax")
                Text("London (lhr)").tag("lhr")
                Text("Tokyo (nrt)").tag("nrt")
                Text("Sydney (syd)").tag("syd")
            }
        }
    }
    
    private var claudeSection: some View {
        Section("Claude Configuration") {
            Toggle("Auto-launch Claude on machine start", isOn: $viewModel.autoLaunchClaude)
        }
    }
    
    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundColor(.secondary)
            }
            
            Link("GitHub Repository", destination: URL(string: "https://github.com/user/claude-machine-launcher")!)
        }
    }
}

#Preview {
    SettingsView()
}