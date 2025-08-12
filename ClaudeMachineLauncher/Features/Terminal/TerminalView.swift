import SwiftUI
import SwiftTerm

struct TerminalView: View {
    @StateObject private var viewModel = TerminalViewModel()
    @StateObject private var appState = AppStateManager.shared
    @StateObject private var sessionManager = SessionManager.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Active Machine Header
                if let activeMachine = appState.selectedMachine {
                    activeMachineHeader(activeMachine)
                }
                
                if viewModel.isConnected && appState.hasActiveMachine {
                    TerminalWrapper()
                        .environmentObject(viewModel)
                } else {
                    noSessionView
                }
            }
            .navigationTitle("Terminal")
        }
    }
    
    private func activeMachineHeader(_ machine: FlyMachine) -> some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connected to: \(machine.name)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("\(machine.id.prefix(12))...fly.dev")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.isConnected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(viewModel.isConnected ? "Connected" : "Connecting...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if viewModel.isConnecting {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }
            
            Divider()
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .background(Color(.systemBackground))
    }
    
    private var noSessionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "terminal")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            if appState.hasMachines {
                VStack(spacing: 16) {
                    Text("No Active Session")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    Text("Select a machine from the Agents tab to start a terminal session.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Go to Agents") {
                        // This would switch to Agents tab - implement if needed
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 16) {
                    Text("No Claude Agents")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    Text("Launch a Claude agent from the Agents tab to start a terminal session.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Launch Agent") {
                        // This would switch to Agents tab - implement if needed
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .padding()
    }
}

struct TerminalWrapper: UIViewRepresentable {
    @EnvironmentObject var viewModel: TerminalViewModel
    
    func makeUIView(context: Context) -> TerminalViewContainer {
        let container = TerminalViewContainer()
        viewModel.setTerminalView(container.terminalView)
        return container
    }
    
    func updateUIView(_ uiView: TerminalViewContainer, context: Context) {
        // No updates needed for now
    }
}

class TerminalViewContainer: UIView {
    let terminalView: SwiftTerm.TerminalView
    
    override init(frame: CGRect) {
        self.terminalView = SwiftTerm.TerminalView()
        super.init(frame: frame)
        
        // Configure terminal for proper ANSI handling
        terminalView.backgroundColor = UIColor.black
        
        addSubview(terminalView)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#Preview {
    TerminalView()
}