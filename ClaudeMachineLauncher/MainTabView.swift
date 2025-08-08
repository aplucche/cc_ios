import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            AgentsView()
                .tabItem {
                    Image(systemName: "server.rack")
                    Text("Agents")
                }
            
            TerminalView()
                .tabItem {
                    Image(systemName: "terminal")
                    Text("Terminal")
                }
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
        }
    }
}


#Preview {
    MainTabView()
}