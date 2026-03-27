import Foundation

// MARK: - User

struct User: Codable, Identifiable {
    let id: String
    let phone: String
    var displayName: String
    var avatarURL: URL?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, phone
        case displayName = "display_name"
        case avatarURL   = "avatar_url"
        case createdAt   = "created_at"
    }
}

// MARK: - Chapter

struct Chapter: Codable, Identifiable, Hashable {
    let id: String
    var status: String
    var name: String?
    var lifeChapterTag: String?
    var lastMemoryAt: Date?
    var partner: PartnerStub?

    enum CodingKeys: String, CodingKey {
        case id, status, name
        case lifeChapterTag = "life_chapter_tag"
        case lastMemoryAt   = "last_memory_at"
        case partner
    }
}

struct PartnerStub: Codable, Hashable {
    let id: String?
    let displayName: String?
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarURL   = "avatar_url"
    }
}

// MARK: - Memory

struct Memory: Codable, Identifiable {
    let id: String
    let chapterID: String
    let ownerID: String
    var mediaURL: URL
    var mediaType: String        // "photo" | "voice"
    var caption: String?
    var takenAt: Date?
    var visibility: String
    let createdAt: Date

    var isVoice: Bool { mediaType == "voice" }

    enum CodingKeys: String, CodingKey {
        case id
        case chapterID  = "chapter_id"
        case ownerID    = "owner_id"
        case mediaURL   = "media_url"
        case mediaType  = "media_type"
        case caption
        case takenAt    = "taken_at"
        case visibility
        case createdAt  = "created_at"
    }
}

// MARK: - Invitation

struct Invitation: Codable, Identifiable {
    let id: String
    let chapterID: String
    let token: String
    let shareURL: URL
    let expiresAt: Date
    let previewURL: URL

    enum CodingKeys: String, CodingKey {
        case id
        case chapterID  = "chapter_id"
        case token
        case shareURL   = "share_url"
        case expiresAt  = "expires_at"
        case previewURL = "preview_url"
    }
}

// MARK: - Daily Card

struct DailyCard: Codable, Identifiable {
    let id: String
    let triggerType: String       // "birthday" | "decay" | "manual"
    let scheduledFor: String      // "YYYY-MM-DD"
    let chapter: DailyCardChapter
    let memories: [Memory]

    enum CodingKeys: String, CodingKey {
        case id
        case triggerType  = "trigger_type"
        case scheduledFor = "scheduled_for"
        case chapter, memories
    }
}

struct DailyCardChapter: Codable {
    let id: String
    let name: String?
    let lastMemoryAt: Date?
    let partner: PartnerStub?

    enum CodingKeys: String, CodingKey {
        case id, name
        case lastMemoryAt = "last_memory_at"
        case partner
    }
}

// MARK: - Auth responses

struct OTPVerifyResponse: Codable {
    let token: String
    let user: User
    let chapter: Chapter?
}

// MARK: - Presign

struct PresignResponse: Codable {
    let uploadURL: URL
    let s3Key: String

    enum CodingKeys: String, CodingKey {
        case uploadURL = "upload_url"
        case s3Key     = "s3_key"
    }
}
