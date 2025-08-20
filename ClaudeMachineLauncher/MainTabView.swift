import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Int = 0
    @StateObject private var appState = AppStateManager.shared
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var settings = SettingsViewModel.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Content area
                TabView(selection: $selectedTab) {
                    AgentsContentView()
                        .environmentObject(appState)
                        .environmentObject(sessionManager)
                        .environmentObject(settings)
                        .tag(0)
                    
                    TerminalContentView()
                        .environmentObject(appState)
                        .environmentObject(sessionManager)
                        .environmentObject(settings)
                        .tag(1)
                    
                    SettingsContentView()
                        .environmentObject(settings)
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Custom tab bar at bottom
                HStack {
                    TabBarButton(
                        icon: "server.rack",
                        title: "Agents",
                        isSelected: selectedTab == 0
                    ) {
                        selectedTab = 0
                    }
                    
                    TabBarButton(
                        icon: "terminal",
                        title: "Terminal",
                        isSelected: selectedTab == 1
                    ) {
                        selectedTab = 1
                    }
                    
                    TabBarButton(
                        icon: "gear",
                        title: "Settings",
                        isSelected: selectedTab == 2
                    ) {
                        selectedTab = 2
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(Color(.systemGray6))
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            // Check for API keys on first launch
            if !settings.hasRequiredAPIKeys {
                selectedTab = 2 // Switch to Settings tab
                Logger.log("API keys missing - redirecting to Settings", category: .system)
            }
        }
    }
    
    private var navigationTitle: String {
        switch selectedTab {
        case 0: return "Claude Agents"
        case 1: return "Terminal"
        case 2: return "Settings"
        default: return "Claude Machine Launcher"
        }
    }
}

struct TabBarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption2)
            }
            .foregroundColor(isSelected ? .blue : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// Content views without NavigationView
struct AgentsContentView: View {
    var body: some View {
        AgentsView()
    }
}

struct TerminalContentView: View {
    var body: some View {
        TerminalView()
    }
}

struct SettingsContentView: View {
    var body: some View {
        SettingsView()
    }
}

#Preview {
    MainTabView()
}