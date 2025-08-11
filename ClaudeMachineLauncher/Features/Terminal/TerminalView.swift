import SwiftUI
import SwiftTerm

struct TerminalView: View {
    @StateObject private var viewModel = TerminalViewModel()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.isConnected {
                    TerminalWrapper()
                        .environmentObject(viewModel)
                } else {
                    connectionView
                }
            }
            .navigationTitle("Terminal")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isConnecting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if viewModel.isConnected {
                        Button("Disconnect") {
                            viewModel.disconnect()
                        }
                    }
                }
            }
        }
    }
    
    private var connectionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "terminal")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("Connect to Claude Agent")
                .font(.title2)
                .fontWeight(.medium)
            
            VStack(spacing: 16) {
                TextField("Host (e.g., agent.fly.dev)", text: $viewModel.host)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                
                TextField("Agent ID (e.g., default)", text: $viewModel.agentId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                
                SecureField("Auth Token", text: $viewModel.authToken)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal)
            
            Button(action: {
                viewModel.connect()
            }) {
                HStack {
                    if viewModel.isConnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        Text("Connecting...")
                    } else {
                        Text("Connect")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.canConnect ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(!viewModel.canConnect)
            .padding(.horizontal)
            
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