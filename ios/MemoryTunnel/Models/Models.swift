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

struct Memory: Codable, Identifiable, Equatable {
    static func == (lhs: Memory, rhs: Memory) -> Bool {
        lhs.id == rhs.id &&
        lhs.caption == rhs.caption &&
        lhs.eventDate == rhs.eventDate &&
        lhs.emotionTags == rhs.emotionTags &&
        lhs.locationName == rhs.locationName &&
        lhs.takenAt == rhs.takenAt &&
        lhs.mediaType == rhs.mediaType
    }

    let id: String
    let chapterID: String
    let ownerID: String
    var mediaURL: URL?             // nil for text and location_checkin memories
    var mediaType: String          // "photo" | "voice" | "text" | "location_checkin"
    var caption: String?
    var takenAt: Date?
    var eventDate: String?         // "YYYY-MM-DD" date of the event being described
    var emotionTags: [String]?     // ["nostalgic", "grateful", ...]
    var width: Int?                // photo width in pixels (for pre-sizing)
    var height: Int?               // photo height in pixels (for pre-sizing)
    var visibility: String
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
    let createdAt: Date

    /// When this memory's mediaURL was signed (set at decode time).
    /// Used to proactively refresh URLs before the 1hr presigned TTL expires.
    var signedAt: Date = Date()

    var isVoice: Bool { mediaType == "voice" }

    /// Returns true when the signed mediaURL is approaching its 1hr expiry.
    /// Triggers a proactive refresh at 50 minutes (10min safety margin).
    var needsURLRefresh: Bool {
        guard mediaURL != nil else { return false }
        return Date().timeIntervalSince(signedAt) > 50 * 60
    }

    /// The single source-of-truth date for display and sorting.
    /// Prefers event_date (parsed from "yyyy-MM-dd"), then taken_at, then created_at.
    var displayDate: Date {
        if let str = eventDate {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            if let d = f.date(from: str) { return d }
        }
        return takenAt ?? createdAt
    }

    /// Aspect ratio for pre-sizing photo frames before AsyncImage loads
    var aspectRatio: CGFloat? {
        guard let w = width, let h = height, w > 0, h > 0 else { return nil }
        return CGFloat(w) / CGFloat(h)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case chapterID    = "chapter_id"
        case ownerID      = "owner_id"
        case mediaURL     = "media_url"
        case mediaType    = "media_type"
        case caption
        case takenAt      = "taken_at"
        case eventDate    = "event_date"
        case emotionTags  = "emotion_tags"
        case width, height
        case visibility
        case locationName = "location_name"
        case latitude
        case longitude
        case createdAt    = "created_at"
    }

    // Rails serializes decimal columns as strings ("37.50002") to preserve precision.
    // Swift's default Codable expects Double. Custom decoder handles both.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        chapterID = try c.decode(String.self, forKey: .chapterID)
        ownerID = try c.decode(String.self, forKey: .ownerID)
        mediaURL = try c.decodeIfPresent(URL.self, forKey: .mediaURL)
        mediaType = try c.decode(String.self, forKey: .mediaType)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        takenAt = try c.decodeIfPresent(Date.self, forKey: .takenAt)
        eventDate = try c.decodeIfPresent(String.self, forKey: .eventDate)
        emotionTags = try c.decodeIfPresent([String].self, forKey: .emotionTags)
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)
        visibility = try c.decode(String.self, forKey: .visibility)
        locationName = try c.decodeIfPresent(String.self, forKey: .locationName)
        createdAt = try c.decode(Date.self, forKey: .createdAt)

        // Decode latitude/longitude as String or Double (Rails sends strings for decimals)
        if let str = try? c.decodeIfPresent(String.self, forKey: .latitude) {
            latitude = Double(str)
        } else {
            latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        }
        if let str = try? c.decodeIfPresent(String.self, forKey: .longitude) {
            longitude = Double(str)
        } else {
            longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        }
    }
}

// MARK: - Invitation Preview (unauthenticated)

struct InvitationPreview: Codable {
    let inviterName: String
    let chapterName: String?
    let previewImageURL: URL?
    let invitationID: String

    enum CodingKeys: String, CodingKey {
        case inviterName    = "inviter_name"
        case chapterName    = "chapter_name"
        case previewImageURL = "preview_image_url"
        case invitationID   = "invitation_id"
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
