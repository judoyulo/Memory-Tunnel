// SettingsView.swift
// App settings. Language picker + account reset.

import SwiftUI

struct SettingsView: View {
    @AppStorage("appLanguage") private var language: String = "en"
    @EnvironmentObject var appState: AppState
    @State private var showResetConfirm = false
    @State private var showDeleteConfirm = false
    @State private var deleteError: String?
    @State private var isDeletingAccount = false

    var body: some View {
        NavigationStack {
            List {
                // Language
                Section {
                    ForEach(AppLanguage.allCases) { lang in
                        Button {
                            withAnimation(.mtSlide) { language = lang.rawValue }
                        } label: {
                            HStack {
                                Text(lang.displayName)
                                    .font(.mtBody)
                                    .foregroundStyle(Color.mtLabel)
                                Spacer()
                                if language == lang.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.mtAccent)
                                }
                            }
                        }
                    }
                } header: {
                    Text(L.language)
                }

                // Account
                Section {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text(L.resetAccount)
                        }
                        .foregroundStyle(Color.mtError)
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            if isDeletingAccount {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "trash")
                            }
                            Text(L.deleteAccount)
                        }
                        .foregroundStyle(Color.mtError)
                    }
                    .disabled(isDeletingAccount)
                } header: {
                    Text(L.account)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.mtBackground)
            .navigationTitle(L.settings)
            .navigationBarTitleDisplayMode(.inline)
            .alert(L.resetAccount, isPresented: $showResetConfirm) {
                Button(L.resetAccountButton, role: .destructive) {
                    resetAccount()
                }
                Button(L.cancel, role: .cancel) {}
            } message: {
                Text(L.resetAccountConfirm)
            }
            .alert(L.deleteAccount, isPresented: $showDeleteConfirm) {
                Button(L.deleteAccountButton, role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button(L.cancel, role: .cancel) {}
            } message: {
                Text(L.deleteAccountConfirm)
            }
            .alert("Error", isPresented: .constant(deleteError != nil)) {
                Button("OK") { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await APIClient.shared.deleteAccount()
            // Server side gone — now wipe local state
            resetAccount()
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private func resetAccount() {
        // Clear auth
        appState.signOut()

        // Force full onboarding on next login (overrides returning-user shortcut)
        UserDefaults.standard.set(true, forKey: "forceOnboardingAfterReset")

        // Clear onboarding flags
        UserDefaults.standard.removeObject(forKey: "smartStartCompleted")

        // Clear hint dismissal
        UserDefaults.standard.removeObject(forKey: "todayHintDismissed")

        // Clear Daily Dig scan data (all chapters)
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix("dig.") || key.hasPrefix("chapterViewMode_") {
                defaults.removeObject(forKey: key)
            }
        }

        // Clear face embeddings store
        let faceStorePath = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("face_embeddings.json")
        if let path = faceStorePath {
            try? FileManager.default.removeItem(at: path)
        }

        // Keep language preference (don't reset appLanguage)
    }
}
