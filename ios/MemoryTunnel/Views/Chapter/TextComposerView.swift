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
                                Text("Write a memory, thought, or note...")
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
            .navigationTitle("Write something")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.mtSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
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
