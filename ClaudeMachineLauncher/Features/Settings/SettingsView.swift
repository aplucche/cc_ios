import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    
    var body: some View {
        Form {
            apiKeysSection
            gitSection
            flySection
            claudeSection
            aboutSection
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
            
            Button("Clear All Keys", role: .destructive) {
                viewModel.clearAPIKeys()
            }
            .disabled(!viewModel.hasRequiredAPIKeys && !viewModel.hasGitCredentials)
        }
    }
    
    private var gitSection: some View {
        Section(header: Text("Git Integration"), 
                footer: Text("GitHub username and Personal Access Token for repository access. Repositories can be selected when launching machines.")) {
            TextField("GitHub Username", text: $viewModel.gitUsername)
                .textInputAutocapitalization(.never)
            
            SecureField("Personal Access Token", text: $viewModel.gitToken)
                .textInputAutocapitalization(.never)
            
            if viewModel.hasGitCredentials {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Git credentials saved")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            NavigationLink("Manage Repositories (\(viewModel.repositories.count))") {
                RepositoryManagementView()
                    .environmentObject(viewModel)
            }
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