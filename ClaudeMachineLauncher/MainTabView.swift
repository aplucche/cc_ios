import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Int = 0
    @StateObject private var settings = SettingsViewModel.shared
    
    var body: some View {
        TabView(selection: $selectedTab) {
            AgentsView()
                .tabItem {
                    Image(systemName: "server.rack")
                    Text("Agents")
                }
                .tag(0)
            
            TerminalView()
                .tabItem {
                    Image(systemName: "terminal")
                    Text("Terminal")
                }
                .tag(1)
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(2)
        }
        .onAppear {
            // Check for API keys on first launch
            if !settings.hasRequiredAPIKeys {
                selectedTab = 2 // Switch to Settings tab
                Logger.log("API keys missing - redirecting to Settings", category: .system)
            }
        }
    }
}


#Preview {
    MainTabView()
}