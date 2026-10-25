import SwiftUI
import AVFoundation

@main struct EchoApp: App {
    @StateObject private var library = EchoLibrary()
    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.035, green: 0.055, blue: 0.11, alpha: 1)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    var body: some Scene {
        WindowGroup {
            EchoRootView().environmentObject(library).tint(EchoStyle.accent).preferredColorScheme(.dark)
        }
    }
}

struct EchoRootView: View {
    @EnvironmentObject private var library: EchoLibrary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { ChallengeView(openStudio: { selectedTab = 1 }) }.tabItem { Label("挑战", systemImage: "waveform.path") }.tag(0)
            NavigationStack { StudioView() }.tabItem { Label("创作", systemImage: "square.grid.3x3") }.tag(1)
            NavigationStack { ProfileView() }.tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(2)
        }.environment(\.echoReducedMotion, reduceMotion || library.state.settings.reducedMotion)
            .alert("存档提示", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
            Button("知道了") { library.errorMessage = nil }
        } message: { Text(library.errorMessage ?? "") }
    }
}
