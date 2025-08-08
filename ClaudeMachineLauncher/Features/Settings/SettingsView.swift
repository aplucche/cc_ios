import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    
    var body: some View {
        NavigationView {
            Form {
                flySection
                claudeSection
                aboutSection
            }
            .navigationTitle("Settings")
        }
    }
    
    private var flySection: some View {
        Section("Fly.io Configuration") {
            SecureField("Fly API Token", text: $viewModel.flyAPIToken)
                .textInputAutocapitalization(.never)
            
            TextField("Default App Name", text: $viewModel.defaultAppName)
                .textInputAutocapitalization(.never)
            
            TextField("Default Docker Image", text: $viewModel.defaultDockerImage)
                .textInputAutocapitalization(.never)
            
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
            SecureField("Claude API Key", text: $viewModel.claudeAPIKey)
                .textInputAutocapitalization(.never)
            
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