import SwiftUI

// MARK: - Text Composer View
//
// Warm text entry with metadata fields (location, event date, tags).

struct TextComposerView: View {
    let onSave: (String, String?, Date?, [String]) -> Void  // text, location, date, tags
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var locationName = ""
    @State private var eventDate: Date?
    @State private var emotionTags: Set<String> = []
    @FocusState private var isFocused: Bool

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Text area
                    TextEditor(text: $text)
                        .font(.system(size: 17))
                        .foregroundStyle(Color.mtLabel)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .frame(minHeight: 120)
                        .padding(Spacing.sm)
                        .background(Color.mtSurface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(L.writeMemoryPlaceholder)
                                    .font(.system(size: 17))
                                    .foregroundStyle(Color.mtTertiary)
                                    .padding(Spacing.sm)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }

                    // Metadata fields
                    MemoryMetadataFields(
                        locationName: $locationName,
                        eventDate: $eventDate,
                        emotionTags: $emotionTags
                    )
                }
                .padding(Spacing.xl)
            }
            .background(Color.mtBackground)
            .navigationTitle(L.writeSomething)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.cancel) { dismiss() }
                        .foregroundStyle(Color.mtSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.save) {
                        let content = text
                        let loc = locationName.isEmpty ? nil : locationName
                        let tags = Array(emotionTags)
                        dismiss()
                        onSave(content, loc, eventDate, tags)
                    }
                    .font(.mtButton)
                    .foregroundStyle(canSave ? Color.mtLabel : Color.mtTertiary)
                    .disabled(!canSave)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
