import SwiftUI

// MARK: - Memory Edit Sheet
//
// Long-press a memory → edit caption, location, event date, tags.
// Calls PATCH /memories/:id to persist changes.

struct MemoryEditSheet: View {
    let memory: Memory
    let chapterID: String
    let onSave: (Memory) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var caption: String
    @State private var locationName: String
    @State private var eventDate: Date?
    @State private var emotionTags: Set<String>
    @State private var isSaving = false

    init(memory: Memory, chapterID: String, onSave: @escaping (Memory) -> Void, onDelete: @escaping () -> Void) {
        self.memory = memory
        self.chapterID = chapterID
        self.onSave = onSave
        self.onDelete = onDelete
        _caption = State(initialValue: memory.caption ?? "")
        _locationName = State(initialValue: memory.locationName ?? "")
        // Prefill date: prefer event_date, fall back to taken_at
        let date = Self.parseEventDate(memory.eventDate) ?? memory.takenAt
        _eventDate = State(initialValue: date)
        _emotionTags = State(initialValue: Set(memory.emotionTags ?? []))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Caption
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Caption")
                            .font(.mtCaption)
                            .foregroundStyle(Color.mtTertiary)
                        TextEditor(text: $caption)
                            .font(.mtBody)
                            .foregroundStyle(Color.mtLabel)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 60)
                            .padding(Spacing.sm)
                            .background(Color.mtSurface)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    }

                    // Metadata fields
                    MemoryMetadataFields(
                        locationName: $locationName,
                        eventDate: $eventDate,
                        emotionTags: $emotionTags
                    )

                    // Delete
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete memory")
                        }
                        .font(.mtBody)
                        .foregroundStyle(Color(red: 0.878, green: 0.31, blue: 0.31)) // #E04F4F
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .padding(.top, Spacing.md)
                }
                .padding(Spacing.xl)
            }
            .background(Color.mtBackground)
            .navigationTitle("Edit memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.mtSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .font(.mtButton)
                    .foregroundStyle(Color.mtLabel)
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await APIClient.shared.updateMemory(
                chapterID: chapterID,
                memoryID: memory.id,
                caption: caption,
                locationName: locationName.isEmpty ? nil : locationName,
                eventDate: eventDate,
                emotionTags: Array(emotionTags)
            )
            // Reload from server to get correct data + sort order
            onSave(memory) // trigger reload
            dismiss()
        } catch {
            print("[MemoryEditSheet] save error: \(error)")
        }
    }

    private static func parseEventDate(_ dateString: String?) -> Date? {
        guard let str = dateString else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: str)
    }
}
