import SwiftUI

@main
struct RollcallApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isLoggedIn {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(appState)
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("签到", systemImage: "checkmark.circle.fill", value: 0) {
                DashboardView()
            }
            Tab("课表", systemImage: "calendar", value: 1) {
                CurriculumView()
            }
            Tab("设置", systemImage: "gearshape.fill", value: 2) {
                SettingsView()
            }
        }
    }
}
