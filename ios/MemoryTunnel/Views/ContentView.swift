import SwiftUI

/// Root navigation for authenticated users.
/// Default tab is Chapters for new users (no chapters yet), Today for established users.
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: NotificationRouter
    @State private var selectedTab: Tab = .chapters

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
            // Default to Chapters for new users, Today for users with chapters
            selectedTab = appState.hasChapters ? .home : .chapters
        }
        .onChange(of: router.pendingChapterID) { _, chapterID in
            if chapterID != nil { selectedTab = .chapters }
        }
    }
}
