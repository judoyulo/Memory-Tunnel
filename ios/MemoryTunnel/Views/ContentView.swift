import SwiftUI

/// Root navigation for authenticated users.
/// The home screen is always the Daily Card queue — one card per day.
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: NotificationRouter
    @State private var selectedTab: Tab = .home

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
        .onChange(of: router.pendingChapterID) { _, chapterID in
            if chapterID != nil { selectedTab = .chapters }
        }
    }
}
