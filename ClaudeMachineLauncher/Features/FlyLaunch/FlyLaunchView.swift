import SwiftUI

struct FlyLaunchView: View {
    @StateObject private var viewModel = FlyLaunchViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    configurationSection
                    
                    if viewModel.launchedMachine == nil {
                        launchSection
                    } else {
                        machineStatusSection
                    }
                    
                    if let errorMessage = viewModel.errorMessage {
                        errorSection(errorMessage)
                    }
                }
                .padding()
            }
            .navigationTitle("Claude Machine Launcher")
        }
    }
    
    private var configurationSection: some View {
        GroupBox("Configuration") {
            VStack(spacing: 16) {
                SecureField("Fly API Token", text: $viewModel.flyAPIToken)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("App Name", text: $viewModel.appName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
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
    
    private var launchSection: some View {
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
                    Text(viewModel.isLoading ? "Launching..." : "Launch Machine")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.canLaunch ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(!viewModel.canLaunch)
        }
    }
    
    private var machineStatusSection: some View {
        GroupBox("Machine Status") {
            VStack(alignment: .leading, spacing: 12) {
                if let machine = viewModel.launchedMachine {
                    InfoRow(label: "ID", value: machine.id)
                    InfoRow(label: "Name", value: machine.name)
                    InfoRow(label: "State", value: machine.state)
                    InfoRow(label: "Region", value: machine.region)
                    
                    if let privateIP = machine.privateIP {
                        InfoRow(label: "Private IP", value: privateIP)
                    }
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
    FlyLaunchView()
}