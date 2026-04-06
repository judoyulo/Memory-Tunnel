import SwiftUI

/// Root navigation for authenticated users.
/// Default tab is Chapters for new users (no chapters yet), Today for established users.
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: NotificationRouter
    @State private var selectedTab: Tab = .home
    #if DEBUG
    @State private var showDiagnostic = false
    #endif

    enum Tab { case home, chapters }

    var body: some View {
        TabView(selection: $selectedTab) {
            DailyCardContainerView()
                .tabItem { Label("Today", systemImage: "photo.fill") }
                .tag(Tab.home)

            ChapterListView()
                .tabItem { Label("Chapters", systemImage: "person.2.fill") }
                .tag(Tab.chapters)
        }
        .tint(Color.mtLabel)
        .onAppear {
            // Always start on Today tab
            selectedTab = .home
        }
        .onChange(of: router.pendingChapterID) { _, chapterID in
            if chapterID != nil { selectedTab = .chapters }
        }
        #if DEBUG
        .overlay(alignment: .bottomLeading) {
            Button { showDiagnostic = true } label: {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.leading, 16)
            .padding(.bottom, 60)
        }
        .sheet(isPresented: $showDiagnostic) {
            FaceClusterDiagnosticView()
        }
        #endif
    }
}
