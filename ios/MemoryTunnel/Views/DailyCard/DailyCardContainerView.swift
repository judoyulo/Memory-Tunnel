import SwiftUI
import WidgetKit
import Photos

/// Loads today's daily card and presents it full-screen.
@MainActor
final class DailyCardViewModel: ObservableObject {
    @Published var card: DailyCard?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasLoaded = false

    func load() async {
        guard !hasLoaded else { return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            card = try await APIClient.shared.dailyCard()
            updateWidgetData()
        } catch {
            print("[DailyCard] load failed: \(error)")
            card = nil
        }
    }

    func markOpened() {
        Task { try? await APIClient.shared.markDailyCardOpened() }
    }

    private func updateWidgetData() {
        guard let defaults = UserDefaults(suiteName: "group.com.memorytunnel.app") else { return }
        if let card {
            defaults.set(card.chapter.partner?.displayName, forKey: "widget.partnerName")
            defaults.set(card.memories.first?.mediaURL?.absoluteString, forKey: "widget.imageURL")
            defaults.set(card.chapter.id, forKey: "widget.chapterID")
        } else {
            defaults.removeObject(forKey: "widget.partnerName")
            defaults.removeObject(forKey: "widget.imageURL")
            defaults.removeObject(forKey: "widget.chapterID")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Feed ViewModel

@MainActor
final class TodayFeedViewModel: ObservableObject {
    @Published var cards: [FeedCard] = []
    @Published var isScanning = false
    private var hasLoaded = false

    func loadIfNeeded(chapters: [Chapter]) async {
        guard !hasLoaded else { return }
        hasLoaded = true
        isScanning = true
        cards = await TodayFeedService.shared.buildFeed(chapters: chapters)
        isScanning = false
    }

    /// Mark a card as "added" after user took action. ACCUMULATES chapter matches.
    func markCardAdded(cardID: UUID, chapterID: String, chapterName: String) {
        guard let idx = cards.firstIndex(where: { $0.id == cardID }) else { return }
        cards[idx].type = .added
        cards[idx].matchedChapterID = chapterID
        cards[idx].matchedPartnerName = chapterName
        if !cards[idx].allChapterMatches.contains(where: { $0.chapterID == chapterID }) {
            cards[idx].allChapterMatches.append((chapterID: chapterID, partnerName: chapterName))
        }
    }

    /// When a chapter is deleted, revert related cards to newFace
    func onChapterDeleted(chapterID: String) {
        for i in 0 ..< cards.count {
            if cards[i].matchedChapterID == chapterID {
                cards[i].type = .newFace
                cards[i].matchedChapterID = nil
                cards[i].matchedPartnerName = nil
            }
        }
    }
}

// MARK: - Container

struct DailyCardContainerView: View {
    @StateObject private var vm = DailyCardViewModel()
    @StateObject private var feedVM = TodayFeedViewModel()
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Color.mtBackground.ignoresSafeArea()

            if vm.isLoading && !vm.hasLoaded && feedVM.cards.isEmpty {
                ProgressView()
            } else {
                // Full-screen swipeable feed — works with or without chapters
                TodayFeedView(
                    feedVM: feedVM,
                    isScanning: feedVM.isScanning
                )
            }
        }
        .task { await vm.load() }
        .task { await feedVM.loadIfNeeded(chapters: appState.chapters) }
        .onReceive(NotificationCenter.default.publisher(for: .chapterDeleted)) { notif in
            if let chapterID = notif.userInfo?["chapterID"] as? String {
                feedVM.onChapterDeleted(chapterID: chapterID)
            }
        }
    }
}

extension Notification.Name {
    static let chapterDeleted = Notification.Name("chapterDeleted")
}

// MARK: - Full-Screen Swipeable Feed

struct TodayFeedView: View {
    @ObservedObject var feedVM: TodayFeedViewModel
    @ObservedObject var scanProgress = TodayFeedService.scanProgress
    let isScanning: Bool
    @AppStorage("todayHintDismissed") private var hintDismissed = false

    var body: some View {
        TabView {
            // Hint card (first card, shown once for new users)
            if !hintDismissed && !feedVM.cards.isEmpty {
                TodayHintCard { hintDismissed = true }
            }

            ForEach(feedVM.cards) { card in
                FeedCardFullScreen(cardID: card.id, feedVM: feedVM)
            }

            // Scanning indicator at the end
            if isScanning {
                ScanProgressRing(
                    scanned: scanProgress.scanned,
                    total: scanProgress.total,
                    facesFound: feedVM.cards.count
                )
            }

            // End card
            if !feedVM.cards.isEmpty {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.mtAccent)
                    Text(L.thatsAllForToday)
                        .font(.mtTitle)
                        .foregroundStyle(Color.mtLabel)
                    Text(L.comeBackTomorrow)
                        .font(.mtBody)
                        .foregroundStyle(Color.mtSecondary)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .ignoresSafeArea()
    }
}

// MARK: - Today Hint Card (shown once as first card in feed)

private struct TodayHintCard: View {
    let onDismiss: () -> Void
    @State private var ringTrim: CGFloat = 0
    @State private var ringOpacity: Double = 0
    @State private var textOpacity: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.mtBackground

                VStack(spacing: Spacing.xl) {
                    Spacer()

                    // Tunnel icon (draws on, matching splash animation)
                    ZStack {
                        Circle()
                            .trim(from: 0, to: ringTrim)
                            .stroke(Color.mtLabel, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .frame(width: 56, height: 56)
                            .rotationEffect(.degrees(-90))
                            .opacity(ringOpacity)

                        Circle()
                            .fill(Color.mtAccent)
                            .frame(width: 14, height: 14)
                            .opacity(ringOpacity)
                    }
                    .frame(width: 70, height: 70)

                    VStack(spacing: Spacing.md) {
                        Text(L.hintTitle)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.mtLabel)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .opacity(textOpacity)

                        VStack(spacing: Spacing.sm) {
                            hintRow(icon: "hand.draw", text: L.hintSwipe)
                            hintRow(icon: "book.fill", text: L.hintTap)
                            hintRow(icon: "square.and.arrow.up", text: L.hintShare)
                        }
                        .opacity(textOpacity)
                    }

                    Spacer()

                    Button(action: onDismiss) {
                        Text(L.gotIt)
                            .font(.mtButton)
                            .foregroundStyle(Color.mtLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.button)
                                    .stroke(Color.mtLabel, lineWidth: 1.5)
                            )
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, 100)
                    .opacity(textOpacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            // Ring draws on
            withAnimation(.easeOut(duration: 0.15)) { ringOpacity = 1 }
            withAnimation(.easeOut(duration: 0.5)) { ringTrim = 1.0 }
            // Text fades in after ring
            withAnimation(.easeOut(duration: 0.3).delay(0.4)) { textOpacity = 1 }
        }
    }

    private func hintRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.mtSecondary)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Color.mtSecondary)
        }
    }
}

// MARK: - Daily Card (Full-Screen Slide)

private struct DailyCardFullScreen: View {
    let card: DailyCard
    @State private var showSendFlow = false
    @State private var showFacePicker = false
    @State private var loadedPhoto: UIImage?
    @State private var detectedFaces: [(crop: UIImage, embedding: [Float])] = []

    var primaryMemory: Memory? { card.memories.first }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                if let memory = primaryMemory {
                    AsyncImage(url: memory.mediaURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .onAppear { extractUIImage(from: memory) }
                        } else {
                            Color.mtSurface
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                }

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.6)],
                    startPoint: UnitPoint(x: 0.5, y: 0.6),
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Spacer()

                    Text(L.todaysMemory)
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial.opacity(0.8))
                        .clipShape(Capsule())

                    if card.triggerType != "manual" {
                        HStack(spacing: Spacing.xs) {
                            Circle().fill(Color.mtAccent).frame(width: 6, height: 6)
                            Text(triggerLabel).font(.mtCaption).foregroundStyle(Color.white.opacity(0.8))
                        }
                    }

                    if let name = card.chapter.partner?.displayName {
                        Text(name).font(.mtDisplay).foregroundStyle(.white).lineLimit(1)
                    }

                    if let caption = primaryMemory?.caption {
                        Text(caption).font(.mtBody).foregroundStyle(Color.white.opacity(0.85)).lineLimit(2)
                    }

                    // Two buttons: Send + Find more photos
                    VStack(spacing: Spacing.sm) {
                        Button { showSendFlow = true } label: {
                            Text(L.sendAMemory)
                                .font(.mtButton)
                                .foregroundStyle(Color.mtBackground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.mtLabel)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                        }

                        Button { showFacePicker = true } label: {
                            Label(L.findMorePhotos, systemImage: "sparkle.magnifyingglass")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.button)
                                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.top, Spacing.xs)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, 100)
            }
        }
        .sheet(isPresented: $showSendFlow) {
            SendFlowView(chapterID: card.chapter.id)
        }
        .sheet(isPresented: $showFacePicker) {
            if let photo = loadedPhoto {
                // Use same face picker as feed cards
                FacePickerSheet(
                    photo: photo,
                    asset: PHAsset(), // placeholder, photo already loaded
                    faces: detectedFaces
                )
            } else {
                // Photo not loaded yet — show SuggestedPhotos with chapter embedding
                SuggestedPhotosView(
                    chapterID: card.chapter.id,
                    partnerName: card.chapter.partner?.displayName ?? "them"
                ) { _ in showFacePicker = false }
            }
        }
        .task { await loadPhotoFromURL() }
    }

    private var triggerLabel: String {
        switch card.triggerType {
        case "welcome":  return L.firstMemory
        case "birthday": return L.birthdayToday
        case "decay":    return L.itsBeenAWhile
        default:         return ""
        }
    }

    private func extractUIImage(from memory: Memory) {
        // AsyncImage doesn't give us UIImage, load separately for face detection
        if loadedPhoto == nil {
            Task { await loadPhotoFromURL() }
        }
    }

    private func loadPhotoFromURL() async {
        guard let url = primaryMemory?.mediaURL,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data),
              let cgImage = image.cgImage else { return }

        loadedPhoto = image

        // Pre-detect faces
        let observations = await FaceEmbeddingService.shared.detectFaces(in: cgImage)
        var faces: [(crop: UIImage, embedding: [Float])] = []
        for obs in observations {
            if let result = await FaceEmbeddingService.shared.embedding(for: obs, in: cgImage) {
                faces.append((crop: result.crop, embedding: result.embedding))
            }
        }
        detectedFaces = faces
    }
}

// MARK: - Feed Card (Full-Screen Slide)

private struct FeedCardFullScreen: View {
    let cardID: UUID
    @ObservedObject var feedVM: TodayFeedViewModel
    @State private var photo: UIImage?
    @State private var showFacePicker = false
    @State private var currentExcludedIDs: Set<String> = []
    @State private var currentKnownChapterID: String? = nil
    @State private var currentKnownChapterName: String? = nil
    @State private var showSendFlow = false
    @State private var showShareSheet = false
    @State private var detectedFaces: [(crop: UIImage, embedding: [Float])] = []
    @State private var facesReady = false
    @State private var showChapterPicker = false

    /// Live card from feedVM (always fresh after markCardAdded)
    private var card: FeedCard {
        feedVM.cards.first(where: { $0.id == cardID }) ?? feedVM.cards[0]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Color.mtSurface
                    ProgressView()
                }

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.6)],
                    startPoint: UnitPoint(x: 0.5, y: 0.6),
                    endPoint: .bottom
                )

                // Share icon (top-right corner)
                if photo != nil {
                    VStack {
                        HStack {
                            Spacer()
                            Button { showShareSheet = true } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(.ultraThinMaterial.opacity(0.6))
                                    .clipShape(Circle())
                            }
                            .padding(.trailing, Spacing.md)
                            .padding(.top, 60)
                        }
                        Spacer()
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Spacer()

                    Text(card.tagText)
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(card.tagColor.opacity(0.85))
                        .clipShape(Capsule())

                    if let name = card.matchedPartnerName {
                        Text(name).font(.mtDisplay).foregroundStyle(.white).lineLimit(1)
                    }

                    Text(contextLine)
                        .font(.mtBody)
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(2)

                    if card.type == .added {
                        VStack(spacing: Spacing.sm) {
                            Button {
                                showChapterPicker = true
                            } label: {
                                Label(L.viewInMemoryLane, systemImage: "book.fill")
                                    .font(.mtButton)
                                    .foregroundStyle(Color.mtBackground)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color(red: 0.298, green: 0.686, blue: 0.475))
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                            }

                            Button {
                                currentExcludedIDs = Set(card.allChapterMatches.map(\.chapterID)); currentKnownChapterID = card.matchedChapterID; currentKnownChapterName = card.matchedPartnerName; showFacePicker = true
                            } label: {
                                Text(L.addToMoreMemoryLanes)
                                    .font(.mtButton)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.button)
                                            .stroke(Color.white.opacity(0.4), lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.top, Spacing.xs)
                    } else {
                        Button {
                            currentExcludedIDs = Set(card.allChapterMatches.map(\.chapterID)); currentKnownChapterID = card.matchedChapterID; currentKnownChapterName = card.matchedPartnerName; showFacePicker = true
                        } label: {
                            Text(card.type == .newFace ? L.startAMemoryLane : L.addToMemoryLane)
                                .font(.mtButton)
                                .foregroundStyle(Color.mtBackground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.mtLabel)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                        }
                        .padding(.top, Spacing.xs)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, 100)
            }
        }
        .task { await loadPhotoAndDetectFaces() }
        .sheet(isPresented: $showFacePicker) {
            FacePickerSheet(
                photo: photo,
                asset: card.asset,
                faces: detectedFaces,
                knownChapterID: currentKnownChapterID,
                knownChapterName: currentKnownChapterName,
                excludeChapterIDs: currentExcludedIDs,
                onActed: { chapterID, chapterName in
                    feedVM.markCardAdded(cardID: cardID, chapterID: chapterID, chapterName: chapterName)
                    currentExcludedIDs.insert(chapterID)
                    currentKnownChapterID = chapterID
                    currentKnownChapterName = chapterName
                }
            )
        }
        .sheet(isPresented: $showSendFlow) {
            if let chapterID = card.matchedChapterID {
                SendFlowView(chapterID: chapterID)
            }
        }
        .sheet(isPresented: $showChapterPicker) {
            ChapterPickerSheet(chapters: uniqueChapterMatches)
        }
        .sheet(isPresented: $showShareSheet) {
            if let photo {
                ShareCardSheet(
                    photo: photo,
                    creationDate: card.asset.creationDate,
                    locationName: nil,
                    photoDepth: card.photoDepth,
                    asset: card.asset
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
            }
        }
    }

    private var contextLine: String {
        guard let date = card.asset.creationDate else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: date)
    }

    /// Load photo AND pre-detect all faces so picker is instant
    /// Deduplicated chapter matches for this card
    private var uniqueChapterMatches: [(chapterID: String, partnerName: String)] {
        var all = card.allChapterMatches
        // Ensure the primary match is included
        if let chID = card.matchedChapterID, let name = card.matchedPartnerName {
            if !all.contains(where: { $0.chapterID == chID }) {
                all.insert((chapterID: chID, partnerName: name), at: 0)
            }
        }
        var seen = Set<String>()
        return all.filter { match in
            guard !seen.contains(match.chapterID) else { return false }
            seen.insert(match.chapterID)
            return true
        }
    }

    private func loadPhotoAndDetectFaces() async {
        photo = await ReconnectionService.shared.loadFullImage(for: card.asset)

        guard let photo, let cgImage = photo.cgImage else { return }

        let observations = await FaceEmbeddingService.shared.detectFaces(in: cgImage)
        var faces: [(crop: UIImage, embedding: [Float])] = []
        for obs in observations {
            if let result = await FaceEmbeddingService.shared.embedding(for: obs, in: cgImage) {
                faces.append((crop: result.crop, embedding: result.embedding))
            }
        }
        detectedFaces = faces
        facesReady = true
    }
}

// FacePickerSheet moved to FacePickerSheet.swift

/*

    init(photo: UIImage?, asset: PHAsset, faces: [(crop: UIImage, embedding: [Float])], knownChapterID: String? = nil, knownChapterName: String? = nil) {
        self.preloadedPhoto = photo
        self.asset = asset
        self.preloadedFaces = faces
        self.knownChapterID = knownChapterID
        self.knownChapterName = knownChapterName
    }

    private var selectedFace: (crop: UIImage, embedding: [Float])? {
        guard let idx = selectedIndex, idx < faces.count else { return nil }
        return faces[idx]
    }

    private var matchedChapter: (chapterID: String, partnerName: String)? {
        // Check per-face match first (from face picker selection)
        if let idx = selectedIndex, let match = faceChapterMatches[idx] {
            return match
        }
        // Fallback: use known chapter from the feed card
        if let id = knownChapterID, let name = knownChapterName {
            return (chapterID: id, partnerName: name)
        }
        return nil
    }

    var body: some View {
        NavigationView {
            VStack(spacing: Spacing.lg) {
                if isDetecting && faces.isEmpty {
                    Spacer()
                    ProgressView()
                    Text("Detecting faces...")
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtSecondary)
                    Spacer()
                } else if faces.count > 1 {
                    Text("Who do you want to start\na chapter with?")
                        .font(.mtTitle)
                        .foregroundStyle(Color.mtLabel)
                        .multilineTextAlignment(.center)
                        .padding(.top, Spacing.lg)

                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                            .padding(.horizontal, Spacing.md)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.md) {
                            ForEach(Array(faces.enumerated()), id: \.offset) { index, face in
                                Button { selectedIndex = index } label: {
                                    VStack(spacing: 4) {
                                        Image(uiImage: face.crop)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 72, height: 72)
                                            .clipShape(Circle())
                                            .overlay(
                                                Circle().stroke(
                                                    selectedIndex == index ? Color.mtLabel : Color.clear,
                                                    lineWidth: 3
                                                )
                                            )
                                            .shadow(color: selectedIndex == index ? Color.mtLabel.opacity(0.3) : .clear, radius: 6)
                                        // Show chapter name if face matches an existing chapter
                                        if let match = faceChapterMatches[index] {
                                            Text(match.partnerName)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(Color.mtAccent)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                    }
                } else {
                    // Single face
                    Text("Start a chapter")
                        .font(.mtTitle)
                        .foregroundStyle(Color.mtLabel)
                        .padding(.top, Spacing.lg)

                    if let face = faces.first {
                        Image(uiImage: face.crop)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                    }
                }

                Spacer()

                // Per-face chapter match labels
                if !faceChapterMatches.isEmpty {
                    ForEach(Array(faceChapterMatches.keys.sorted()), id: \.self) { idx in
                        if let match = faceChapterMatches[idx], idx < faces.count {
                            HStack(spacing: Spacing.xs) {
                                Image(uiImage: faces[idx].crop)
                                    .resizable().scaledToFill()
                                    .frame(width: 28, height: 28).clipShape(Circle())
                                Text("\(match.partnerName)'s chapter")
                                    .font(.mtCaption).foregroundStyle(Color.mtAccent)
                                Spacer()
                                Button {
                                    // Add this photo directly to that chapter
                                    Task { await addPhotoToChapter(match.chapterID, name: match.partnerName) }
                                } label: {
                                    Text("Add to chapter")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.mtBackground)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Color.mtAccent).clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, Spacing.xl)
                        }
                    }
                }

                // Actions for selected face
                VStack(spacing: Spacing.sm) {
                    if let match = matchedChapter {
                        Button {
                            Task { await addPhotoToChapter(match.chapterID, name: match.partnerName) }
                        } label: {
                            Text("Add to \(match.partnerName)'s chapter")
                                .font(.mtButton)
                                .foregroundStyle(Color.mtBackground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.mtLabel)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                        }
                    } else if showNameInput {
                        // Inline chapter name input
                        VStack(spacing: Spacing.sm) {
                            TextField("Name this chapter", text: $chapterNameInput)
                                .font(.mtBody)
                                .padding(12)
                                .background(Color.mtSurface)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.button))

                            Button {
                                Task { await createChapterInline() }
                            } label: {
                                Text(isCreatingChapter ? "Creating..." : "Create chapter")
                                    .font(.mtButton)
                                    .foregroundStyle(Color.mtBackground)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(!chapterNameInput.isEmpty ? Color.mtLabel : Color.mtTertiary)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                            }
                            .disabled(chapterNameInput.isEmpty || isCreatingChapter)
                        }
                    } else {
                        Button {
                            savedEmbeddingForLink = selectedFace?.embedding
                            savedCropForLink = selectedFace?.crop
                            showNameInput = true
                        } label: {
                            Text("Start a chapter")
                                .font(.mtButton)
                                .foregroundStyle(Color.mtBackground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(canProceed ? Color.mtLabel : Color.mtTertiary)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                        }
                        .disabled(!canProceed)
                    }

                    Button { showSuggestedPhotos = true } label: {
                        Label("Find more photos of this person", systemImage: "sparkle.magnifyingglass")
                            .font(.mtButton)
                            .foregroundStyle(Color.mtLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.button)
                                    .stroke(Color.mtLabel, lineWidth: 1.5)
                            )
                    }
                    .disabled(!canProceed)
                    .opacity(canProceed ? 1 : 0.4)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.lg)
            }
            .background(Color.mtBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showActionSheet) {
                ChapterActionSheet(
                    chapterID: createdChapterID,
                    chapterName: createdChapterName,
                    message: actionSheetMessage,
                    faceEmbedding: savedEmbeddingForLink ?? selectedFace?.embedding,
                    onGoToChapter: {
                        // Dismiss all sheets then switch tab
                        showActionSheet = false
                        NotificationRouter.shared.pendingChapterID = createdChapterID
                        dismiss() // dismiss FacePickerSheet
                    },
                    onDismiss: {
                        showActionSheet = false
                        dismiss() // dismiss FacePickerSheet back to cards
                    }
                )
            }
            .sheet(isPresented: $showSuggestedPhotos) {
                SuggestedPhotosView(
                    chapterID: matchedChapter?.chapterID ?? createdChapterID,
                    partnerName: matchedChapter?.partnerName ?? createdChapterName,
                    directEmbedding: selectedFace?.embedding
                ) { selectedAssets in
                    // SuggestedPhotosView dismisses itself.
                    // After dismiss animation, show next step.
                    let chID = matchedChapter?.chapterID ?? createdChapterID
                    let chName = matchedChapter?.partnerName ?? createdChapterName

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if !chID.isEmpty {
                            // Chapter exists — show action sheet
                            createdChapterID = chID
                            createdChapterName = chName
                            actionSheetMessage = selectedAssets.isEmpty ? "What's next?" : "Photos Found"
                            showActionSheet = true
                        } else {
                            // No chapter yet (new face) — show name input
                            savedEmbeddingForLink = selectedFace?.embedding
                            savedCropForLink = selectedFace?.crop
                            showNameInput = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showSendFlow) {
                if let match = matchedChapter {
                    SendFlowView(chapterID: match.chapterID)
                }
            }
            .task {
                // Load photo if not preloaded
                if let preloadedPhoto {
                    photo = preloadedPhoto
                } else {
                    photo = await ReconnectionService.shared.loadFullImage(for: asset)
                }

                // Use preloaded faces if available, otherwise detect fresh
                if !preloadedFaces.isEmpty {
                    faces = preloadedFaces
                } else if let cgImage = photo?.cgImage {
                    let observations = await FaceEmbeddingService.shared.detectFaces(in: cgImage)
                    var detected: [(crop: UIImage, embedding: [Float])] = []
                    for obs in observations {
                        if let result = await FaceEmbeddingService.shared.embedding(for: obs, in: cgImage) {
                            detected.append((crop: result.crop, embedding: result.embedding))
                        }
                    }
                    faces = detected
                }
                isDetecting = false

                if faces.count == 1 { selectedIndex = 0 }

                // Match each face to existing chapter partners (lenient threshold)
                let pickerMatchThreshold: Float = 0.20
                for chapter in appState.chapters {
                    let partnerID = chapter.partner?.id ?? chapter.id
                    let partnerName = chapter.partner?.displayName ?? chapter.name ?? "Unknown"

                    var partnerEmb = await FaceEmbeddingService.shared.embeddingForPartner(partnerID: partnerID)
                    if partnerEmb == nil {
                        partnerEmb = await FaceEmbeddingService.shared.embeddingForChapter(chapterID: chapter.id)
                    }
                    guard let emb = partnerEmb else { continue }

                    for (index, face) in faces.enumerated() {
                        let sim = FaceEmbeddingService.shared.cosineSimilarity(face.embedding, emb)
                        if sim >= pickerMatchThreshold {
                            faceChapterMatches[index] = (chapterID: chapter.id, partnerName: partnerName)
                        }
                    }
                }
            }
        }
    }

    private var canProceed: Bool {
        faces.isEmpty || selectedIndex != nil
    }

    /// Create a chapter with just a name, link the face, show action sheet
    private func createChapterInline() async {
        isCreatingChapter = true
        defer { isCreatingChapter = false }

        do {
            let chapter = try await APIClient.shared.createChapter(name: chapterNameInput)

            // Link the face to the new chapter
            if let embedding = savedEmbeddingForLink {
                let partnerID = chapter.partner?.id ?? chapter.id
                await FaceEmbeddingService.shared.linkFaceToChapter(
                    embedding: embedding,
                    crop: savedCropForLink,
                    partnerID: partnerID,
                    chapterID: chapter.id
                )
            }

            createdChapterID = chapter.id
            createdChapterName = chapterNameInput
            actionSheetMessage = "Chapter Created"
            showNameInput = false
            showActionSheet = true
        } catch {
            print("[FacePicker] createChapter failed: \(error)")
        }
    }

    /// Add the current photo to an existing chapter and show the action sheet
    private func addPhotoToChapter(_ chapterID: String, name: String) async {
        var uploaded = false

        if let photo, let jpegData = photo.jpegData(compressionQuality: 0.85) {
            do {
                let presign = try await APIClient.shared.presign(chapterID: chapterID)
                try await APIClient.shared.uploadToS3(data: jpegData, presign: presign)
                _ = try await APIClient.shared.createMemory(
                    chapterID: chapterID,
                    s3Key: presign.s3Key,
                    caption: nil,
                    takenAt: nil,
                    visibility: "shared",
                    width: Int(photo.size.width),
                    height: Int(photo.size.height)
                )
                uploaded = true
            } catch {
                print("[FacePicker] upload failed: \(error)")
            }
        }

        createdChapterID = chapterID
        createdChapterName = name
        actionSheetMessage = uploaded ? "Photo Added" : "What's next?"
        savedEmbeddingForLink = selectedFace?.embedding
        showActionSheet = true
    }
*/

// MARK: - State: No Chapters — Warm Onramp

struct TodayWarmOnrampView: View {
    @EnvironmentObject var appState: AppState
    @State private var showInviteFlow = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = appState.currentUser?.displayName ?? ""
        let prefix: String
        switch hour {
        case 5..<12:  prefix = "Good morning"
        case 12..<17: prefix = "Good afternoon"
        default:      prefix = "Good evening"
        }
        return name.isEmpty ? prefix : "\(prefix), \(name)"
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Text(greeting)
                .font(.mtDisplay)
                .foregroundStyle(Color.mtLabel)
                .multilineTextAlignment(.center)

            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.mtAccent)

            Text(L.warmOnrampTitle)
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Button {
                showInviteFlow = true
            } label: {
                Text(L.startAMemoryLane)
                    .font(.mtButton)
                    .foregroundStyle(Color.mtBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.mtLabel)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            }
            .padding(.horizontal, Spacing.xl)

            Spacer()
            Spacer()
        }
        .padding(Spacing.xl)
        .sheet(isPresented: $showInviteFlow) {
            InviteFlowView()
        }
    }
}

// MARK: - DailyCardView (kept for backward compat, used by ReconnectionCardView sheet)

struct DailyCardView: View {
    let card: DailyCard
    var body: some View {
        DailyCardFullScreen(card: card)
    }
}

/// Identifiable wrapper for sheet binding
private struct SendChapterID: Identifiable {
    let id: String
}

// MARK: - Chapter Preview Card with Health Dot

struct ChapterPreviewCard: View {
    let chapter: Chapter
    let onSend: () -> Void

    private var healthColor: Color {
        guard let last = chapter.lastMemoryAt else { return Color.mtAccent }
        let daysSince = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        if daysSince < 30 { return Color(red: 0.298, green: 0.686, blue: 0.475) }
        if daysSince < 90 { return Color.mtTertiary }
        return Color.mtAccent
    }

    private var healthLabel: String {
        guard let last = chapter.lastMemoryAt else { return "No memories yet" }
        let daysSince = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        if daysSince == 0 { return "Active today" }
        if daysSince == 1 { return "Last memory yesterday" }
        return "Last memory \(daysSince) days ago"
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Circle().fill(healthColor).frame(width: 8, height: 8)

            ZStack {
                Circle().fill(Color.mtSurface).frame(width: 44, height: 44)
                Text(avatarLetter).font(.mtLabel).foregroundStyle(Color.mtLabel)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.partner?.displayName ?? chapter.name ?? "Pending")
                    .font(.mtLabel).foregroundStyle(Color.mtLabel)
                Text(healthLabel).font(.mtCaption).foregroundStyle(Color.mtSecondary)
            }

            Spacer()

            Button(action: onSend) {
                Text(L.send)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.mtBackground)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.mtLabel).clipShape(Capsule())
            }
        }
        .padding(Spacing.md)
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }

    private var avatarLetter: String {
        let name = chapter.partner?.displayName ?? chapter.name ?? "?"
        return String(name.prefix(1).uppercased())
    }
}
