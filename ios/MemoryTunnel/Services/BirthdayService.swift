// BirthdayService.swift
// On-device birthday detection via iOS Contacts framework.
//
// Privacy architecture (enforced by design):
//   - Only birthday month+day is stored on-device (Documents/birthday_index.json)
//   - No birthday dates are transmitted to the server
//   - The API signal carries only { chapter_id } — the server queues a birthday card
//     without knowing the actual date
//
// Permission timing (DESIGN.md § Permission Request Timing):
//   - Requested after the user's first chapter activates — not during cold onboarding
//   - ChapterListViewModel calls requestAccessIfNeeded(for:) after each successful load
//
// Trigger window: 7 days before the partner's birthday (inclusive of the birthday itself)

import Contacts
import Foundation

// MARK: - BirthdayService

@MainActor
final class BirthdayService {
    static let shared = BirthdayService()

    private let contactStore = CNContactStore()
    private let cache = BirthdayCache()

    private init() {}

    // MARK: - Permission + Indexing

    /// Request Contacts access if not yet granted, then index birthdays for active chapters.
    /// Safe to call on every chapter list load — no-ops if already authorized and indexed.
    func requestAccessIfNeeded(for chapters: [Chapter]) async {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            await matchAndIndex(chapters: chapters)
        case .notDetermined:
            do {
                let granted = try await contactStore.requestAccess(for: .contacts)
                if granted { await matchAndIndex(chapters: chapters) }
            } catch {
                // User denied or error — birthday detection silently disabled.
                // App functions normally without Contacts access.
            }
        default:
            break // .denied / .restricted — respect the user's choice silently
        }
    }

    // MARK: - Birthday Signaling

    /// Check for upcoming partner birthdays (within 7 days) and signal the server
    /// to queue a birthday card for each match. Idempotent on the server side.
    /// Call on each app foreground from ChapterListViewModel.
    func checkAndSignal(chapters: [Chapter]) async {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return }

        let today = Calendar.current.dateComponents([.month, .day], from: Date())

        for chapter in chapters where chapter.status == "active" {
            guard let partnerID = chapter.partner?.id,
                  let birthday  = await cache.birthday(for: partnerID),
                  isDueWithinWeek(birthday: birthday, relativeTo: today)
            else { continue }

            // Fire-and-forget — server is idempotent if card already queued today
            try? await APIClient.shared.signalBirthday(chapterID: chapter.id)
        }
    }

    // MARK: - Contact Matching

    /// Scans CNContactStore for each active chapter partner and stores birthday month+day.
    /// Runs contact enumeration on a background thread to avoid blocking the main actor.
    private func matchAndIndex(chapters: [Chapter]) async {
        let activeChapters = chapters.filter { $0.status == "active" }
        guard !activeChapters.isEmpty else { return }

        // Build a lookup: "first last" → (month, day) — on a background thread
        let birthdaysByName: [String: BirthdayComponents] = await Task.detached(priority: .background) {
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey  as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactBirthdayKey   as CNKeyDescriptor
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            var result: [String: BirthdayComponents] = [:]

            try? CNContactStore().enumerateContacts(with: request) { contact, _ in
                guard let bday  = contact.birthday,
                      let month = bday.month,
                      let day   = bday.day
                else { return }

                let components = BirthdayComponents(month: month, day: day)
                let full  = "\(contact.givenName) \(contact.familyName)"
                              .lowercased().trimmingCharacters(in: .whitespaces)
                let first = contact.givenName.lowercased()
                              .trimmingCharacters(in: .whitespaces)

                if !full.isEmpty  { result[full]  = components }
                if !first.isEmpty { result[first] = components }  // first-name fallback
            }
            return result
        }.value

        // Match each active chapter partner against the contact lookup
        for chapter in activeChapters {
            guard let partnerID   = chapter.partner?.id,
                  let displayName = chapter.partner?.displayName
            else { continue }

            let key = displayName.lowercased().trimmingCharacters(in: .whitespaces)
            guard let components = birthdaysByName[key] else { continue }

            try? await cache.store(partnerID: partnerID, birthday: components)
        }
    }

    // MARK: - Date Math

    /// Returns true if the birthday falls within the next 7 days (inclusive of today).
    /// Handles year-end wrap-around (e.g. checking Dec 28 against a Jan 2 birthday).
    private func isDueWithinWeek(
        birthday: BirthdayComponents,
        relativeTo today: DateComponents
    ) -> Bool {
        guard let todayMonth    = today.month,
              let todayDay      = today.day
        else { return false }

        // Use a simple ordinal: month*100 + day. Comparable within a year.
        let todayOrdinal    = todayMonth * 100 + todayDay
        let birthdayOrdinal = birthday.month * 100 + birthday.day

        // Distance forward in the year. Handle Dec→Jan wrap by adding 1200 (12 months * 100).
        let distance = birthdayOrdinal >= todayOrdinal
            ? birthdayOrdinal - todayOrdinal
            : (1200 + birthdayOrdinal) - todayOrdinal

        return distance <= 7
    }
}

// MARK: - BirthdayComponents

/// On-device birthday representation: month + day only. Year is never stored.
struct BirthdayComponents: Codable {
    let month: Int
    let day: Int
}

// MARK: - BirthdayCache

/// Thread-safe, file-backed store mapping partnerID → BirthdayComponents.
/// Stored in the app sandbox — never synced, never transmitted.
private actor BirthdayCache {
    private let url: URL
    private var store: [String: BirthdayComponents]

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent("birthday_index.json")
        if let data    = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: BirthdayComponents].self, from: data) {
            store = decoded
        } else {
            store = [:]
        }
    }

    func birthday(for partnerID: String) -> BirthdayComponents? {
        store[partnerID]
    }

    func store(partnerID: String, birthday: BirthdayComponents) throws {
        store[partnerID] = birthday
        let data = try JSONEncoder().encode(store)
        try data.write(to: url, options: .atomic)
    }
}
