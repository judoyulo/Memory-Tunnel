import SwiftUI

// MARK: - Memory Metadata Fields
//
// Reusable component for location, event date, and emotion tags.
// Used in: TextComposerView, SendFlowView, VoiceRecorderView, MemoryEditSheet.

struct MemoryMetadataFields: View {
    @Binding var locationName: String
    @Binding var eventDate: Date?
    @Binding var emotionTags: Set<String>

    @State private var showDatePicker = false

    static let availableTags = ["nostalgic", "grateful", "excited", "missing you", "funny", "proud"]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Location
            VStack(alignment: .leading, spacing: 4) {
                Text("Where was this?")
                    .font(.mtCaption)
                    .foregroundStyle(Color.mtTertiary)
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "mappin")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.mtSecondary)
                    TextField("Add a location", text: $locationName)
                        .font(.mtBody)
                        .foregroundStyle(Color.mtLabel)
                }
                .padding(Spacing.sm)
                .background(Color.mtSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            }

            // Event date
            VStack(alignment: .leading, spacing: 4) {
                Text("When was this?")
                    .font(.mtCaption)
                    .foregroundStyle(Color.mtTertiary)

                Button {
                    if eventDate == nil { eventDate = Calendar.current.startOfDay(for: Date()) }
                    showDatePicker.toggle()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mtSecondary)
                        if let date = eventDate {
                            Text(date, style: .date)
                                .font(.mtBody)
                                .foregroundStyle(Color.mtLabel)
                            Spacer()
                            Button {
                                eventDate = nil
                                showDatePicker = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.mtTertiary)
                            }
                        } else {
                            Text("Add a date")
                                .font(.mtBody)
                                .foregroundStyle(Color.mtTertiary)
                            Spacer()
                        }
                    }
                    .padding(Spacing.sm)
                    .background(Color.mtSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }
                .buttonStyle(.plain)

                if showDatePicker, let binding = Binding($eventDate) {
                    DatePicker("", selection: binding, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(Color.mtLabel)
                }
            }

            // Emotion tags
            VStack(alignment: .leading, spacing: 4) {
                Text("How does this feel?")
                    .font(.mtCaption)
                    .foregroundStyle(Color.mtTertiary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(Self.availableTags, id: \.self) { tag in
                            let isSelected = emotionTags.contains(tag)
                            Button {
                                if isSelected { emotionTags.remove(tag) }
                                else { emotionTags.insert(tag) }
                            } label: {
                                Text(tag)
                                    .font(.system(size: 13))
                                    .foregroundStyle(isSelected ? Color.mtBackground : Color.mtSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? Color.mtLabel : Color.mtSurface)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
