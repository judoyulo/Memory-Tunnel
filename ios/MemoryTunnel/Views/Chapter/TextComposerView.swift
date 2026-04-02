import SwiftUI

// MARK: - Text Composer View
//
// Warm text entry sheet. Replaces the plain TextField-in-sheet approach.
// Cream background, generous padding, spring animation on save.

struct TextComposerView: View {
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
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

                Spacer()
            }
            .padding(Spacing.xl)
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
                        text = ""
                        dismiss()
                        onSave(content)
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
