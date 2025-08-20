import SwiftUI
import SwiftTerm

struct TerminalView: View {
    @StateObject private var viewModel = TerminalViewModel()
    @StateObject private var appState = AppStateManager.shared
    @StateObject private var sessionManager = SessionManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Minimal Machine Info
            if let activeMachine = appState.selectedMachine {
                minimizedMachineInfo(activeMachine)
            }
            
            if viewModel.isConnected && appState.hasActiveMachine {
                TerminalWrapper()
                    .environmentObject(viewModel)
            } else {
                noSessionView
            }
        }
    }
    
    private func minimizedMachineInfo(_ machine: FlyMachine) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.isConnected ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            
            Text(machine.name)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if viewModel.isConnecting {
                ProgressView()
                    .scaleEffect(0.5)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Color(.systemGray6))
    }
    
    private var noSessionView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            if appState.hasMachines {
                VStack(spacing: 12) {
                    Text("No Active Session")
                        .font(.title3)
                        .fontWeight(.medium)
                    
                    Text("Select a machine from the Agents tab")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button("Go to Agents") {
                        // This would switch to Agents tab - implement if needed
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 12) {
                    Text("No Claude Agents")
                        .font(.title3)
                        .fontWeight(.medium)
                    
                    Text("Launch an agent first")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button("Launch Agent") {
                        // This would switch to Agents tab - implement if needed
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding(.horizontal)
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