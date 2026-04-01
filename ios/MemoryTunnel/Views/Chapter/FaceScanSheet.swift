import SwiftUI

/// Sheet presented from the "+" menu in ChapterListView.
/// Reuses FaceBubblesView to find people in photos and create chapters.
struct FaceScanSheet: View {
    let onDismiss: () -> Void
    @State private var suggestions: [FaceSuggestion] = []
    @State private var isScanning = true
    @State private var completedFaces: Set<UUID> = []
    @State private var showChapterCreation = false
    @State private var selectedSuggestion: FaceSuggestion?

    var body: some View {
        NavigationStack {
            FaceBubblesView(
                suggestions: $suggestions,
                isScanning: isScanning,
                onSelectFace: { index in
                    guard index < suggestions.count else { return }
                    selectedSuggestion = suggestions[index]
                    showChapterCreation = true
                },
                onManualCreate: {
                    selectedSuggestion = nil
                    showChapterCreation = true
                },
                onSkip: { onDismiss() },
                completedFaces: completedFaces
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                        .foregroundStyle(Color.mtSecondary)
                }
            }
            .sheet(isPresented: $showChapterCreation) {
                ChapterCreationView(
                    suggestion: selectedSuggestion,
                    onComplete: { chapterID in
                        if let id = selectedSuggestion?.id { completedFaces.insert(id) }
                        showChapterCreation = false
                        if chapterID != nil { onDismiss() }
                    }
                )
            }
            .task { await startScan() }
        }
    }

    private func startScan() async {
        let stream = await PhotoLibraryScanner.shared.scanFacesProgressively()
        for await snapshot in stream {
            suggestions = snapshot
        }
        isScanning = false
    }
}
