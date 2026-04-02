import Foundation

// MARK: - APIError

enum APIError: Error, LocalizedError {
    case noToken
    case httpError(Int, String?)
    case decodingError(Error)
    case noContent                  // 204 — caller checks for nil

    var errorDescription: String? {
        switch self {
        case .noToken:              return "Not authenticated."
        case .httpError(let c, let m): return "HTTP \(c): \(m ?? "Unknown error")"
        case .decodingError(let e): return e.localizedDescription
        case .noContent:            return nil
        }
    }
}

// MARK: - APIClient

/// Thin async/await wrapper around URLSession targeting the Memory Tunnel Rails API.
/// All methods throw `APIError`; callers handle display logic.
actor APIClient {
    static let shared = APIClient()

    // Injected at startup; stored in Keychain via TokenStore
    var token: String? {
        get { TokenStore.shared.token }
        set { TokenStore.shared.token = newValue }
    }

    private let baseURL: URL = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
                ?? "http://localhost:3000"
        return URL(string: raw)!
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.keyEncodingStrategy  = .convertToSnakeCase
        return e
    }()

    // MARK: Auth

    func sendOTP(phone: String) async throws {
        try await post("/api/v1/auth/send_otp", body: ["phone": phone], authenticated: false)
    }

    func verifyOTP(phone: String, code: String, displayName: String?, invitationToken: String?) async throws -> OTPVerifyResponse {
        var body: [String: String] = ["phone": phone, "code": code]
        if let n = displayName     { body["display_name"]    = n }
        if let t = invitationToken { body["invitation_token"] = t }
        let response: OTPVerifyResponse = try await post("/api/v1/auth/verify_otp", body: body, authenticated: false)
        token = response.token
        return response
    }

    func devLogin(code: String) async throws -> OTPVerifyResponse {
        let response: OTPVerifyResponse = try await post("/api/v1/auth/dev_login", body: ["code": code], authenticated: false)
        token = response.token
        return response
    }

    // MARK: Me

    func me() async throws -> User {
        try await get("/api/v1/me")
    }

    func updateMe(displayName: String? = nil, pushToken: String? = nil) async throws -> User {
        var body: [String: String] = [:]
        if let n = displayName { body["display_name"] = n }
        if let t = pushToken   { body["push_token"]   = t }
        return try await patch("/api/v1/me", body: body)
    }

    // MARK: Chapters

    func chapters() async throws -> [Chapter] {
        try await get("/api/v1/chapters")
    }

    func deleteChapter(id: String) async throws {
        try await delete("/api/v1/chapters/\(id)")
    }

    func createChapter(name: String?) async throws -> Chapter {
        var body: [String: String] = [:]
        if let n = name { body["name"] = n }
        return try await post("/api/v1/chapters", body: body)
    }

    func chapter(id: String) async throws -> Chapter {
        try await get("/api/v1/chapters/\(id)")
    }

    func updateVisibility(chapterID: String, visibility: String) async throws {
        try await patch("/api/v1/chapters/\(chapterID)/visibility", body: ["visibility": visibility])
    }

    // MARK: Memories

    func memories(chapterID: String, page: Int = 1) async throws -> [Memory] {
        try await get("/api/v1/chapters/\(chapterID)/memories", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }

    func presign(chapterID: String, contentType: String = "image/jpeg") async throws -> PresignResponse {
        try await post("/api/v1/chapters/\(chapterID)/memories/presign",
                       body: ["content_type": contentType])
    }

    func createMemory(chapterID: String, s3Key: String, caption: String?, takenAt: Date?,
                      visibility: String, mediaType: String = "photo",
                      locationName: String? = nil, latitude: Double? = nil, longitude: Double? = nil,
                      width: Int? = nil, height: Int? = nil) async throws -> Memory {
        var body: [String: String] = ["s3_key": s3Key, "visibility": visibility, "media_type": mediaType]
        if let c = caption { body["caption"] = c }
        if let t = takenAt {
            let iso = ISO8601DateFormatter()
            body["taken_at"] = iso.string(from: t)
        }
        if let l = locationName { body["location_name"] = l }
        if let lat = latitude   { body["latitude"] = String(lat) }
        if let lon = longitude  { body["longitude"] = String(lon) }
        if let w = width        { body["width"] = String(w) }
        if let h = height       { body["height"] = String(h) }
        return try await post("/api/v1/chapters/\(chapterID)/memories", body: body)
    }

    // MARK: Invitation Preview (unauthenticated)

    func fetchInvitationPreview(token: String) async throws -> InvitationPreview {
        try await get("/api/v1/invitation_previews/\(token)", authenticated: false)
    }

    func createTextMemory(chapterID: String, caption: String,
                          locationName: String? = nil, eventDate: Date? = nil,
                          emotionTags: [String]? = nil) async throws -> Memory {
        var body: [String: String] = ["media_type": "text", "caption": caption, "visibility": "this_item"]
        if let l = locationName { body["location_name"] = l }
        if let d = eventDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            body["event_date"] = formatter.string(from: d)
        }
        // emotion_tags: join as JSON array string since body is [String: String]
        // The backend parses this from the JSON body which supports arrays
        return try await post("/api/v1/chapters/\(chapterID)/memories", body: body)
    }

    func createLocationCheckin(chapterID: String, locationName: String, latitude: Double, longitude: Double, caption: String? = nil) async throws -> Memory {
        var body: [String: String] = [
            "media_type": "location_checkin", "visibility": "this_item",
            "location_name": locationName, "latitude": String(latitude), "longitude": String(longitude)
        ]
        if let c = caption { body["caption"] = c }
        return try await post("/api/v1/chapters/\(chapterID)/memories", body: body)
    }

    func updateMemory(chapterID: String, memoryID: String, caption: String?,
                      locationName: String? = nil, eventDate: Date? = nil,
                      emotionTags: [String]? = nil) async throws -> Memory {
        var body: [String: Any] = [:]
        if let c = caption { body["caption"] = c }
        if let l = locationName { body["location_name"] = l }
        if let d = eventDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            body["event_date"] = formatter.string(from: d)
        }
        if let tags = emotionTags { body["emotion_tags"] = tags }

        var req = try buildRequest(method: "PATCH", path: "/api/v1/chapters/\(chapterID)/memories/\(memoryID)")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(req)
    }

    func deleteMemory(chapterID: String, memoryID: String) async throws {
        try await delete("/api/v1/chapters/\(chapterID)/memories/\(memoryID)")
    }

    // MARK: Invitations

    func createInvitation(chapterID: String, memoryID: String) async throws -> Invitation {
        try await post("/api/v1/invitations",
                       body: ["chapter_id": chapterID, "memory_id": memoryID])
    }

    func acceptInvitation(id: String) async throws -> Chapter {
        let res: [String: Chapter] = try await post("/api/v1/invitations/\(id)/accept", body: [:])
        guard let chapter = res["chapter"] else {
            throw APIError.decodingError(NSError(domain: "APIClient", code: 0,
                                                 userInfo: [NSLocalizedDescriptionKey: "Missing chapter in accept response"]))
        }
        return chapter
    }

    // MARK: Daily Card

    /// Returns `nil` when the server responds 204 (no card queued for today).
    func dailyCard() async throws -> DailyCard? {
        do {
            return try await get("/api/v1/daily_card")
        } catch APIError.noContent {
            return nil
        }
    }

    func markDailyCardOpened() async throws {
        try await post("/api/v1/daily_card/open", body: [:])
    }

    /// Signal that a chapter partner has an upcoming birthday (detected on-device via Contacts).
    /// The server queues a birthday daily card. No date data is included in the request.
    func signalBirthday(chapterID: String) async throws {
        try await post("/api/v1/daily_card/birthday_signal", body: ["chapter_id": chapterID])
    }

    // MARK: - S3 Direct Upload

    /// Uploads raw image data directly to S3 using the presigned PUT URL.
    /// Does not go through the Rails server.
    func uploadToS3(data: Data, presign: PresignResponse, contentType: String = "image/jpeg") async throws {
        var request = URLRequest(url: presign.uploadURL)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, "S3 upload failed")
        }
    }

    // MARK: - HTTP primitives

    @discardableResult
    private func get<T: Decodable>(_ path: String, authenticated: Bool = true, queryItems: [URLQueryItem]? = nil) async throws -> T {
        let req = try buildRequest(method: "GET", path: path, authenticated: authenticated, queryItems: queryItems)
        return try await perform(req)
    }

    @discardableResult
    private func post<B: Encodable, T: Decodable>(_ path: String, body: B, authenticated: Bool = true) async throws -> T {
        var req = try buildRequest(method: "POST", path: path, authenticated: authenticated)
        req.httpBody = try encoder.encode(body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(req)
    }

    @discardableResult
    private func post<T: Decodable>(_ path: String, body: [String: String], authenticated: Bool = true) async throws -> T {
        var req = try buildRequest(method: "POST", path: path, authenticated: authenticated)
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(req)
    }

    private func post(_ path: String, body: [String: String], authenticated: Bool = true) async throws {
        var req = try buildRequest(method: "POST", path: path, authenticated: authenticated)
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await performVoid(req)
    }

    @discardableResult
    private func patch<T: Decodable>(_ path: String, body: [String: String]) async throws -> T {
        var req = try buildRequest(method: "PATCH", path: path)
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(req)
    }

    private func patch(_ path: String, body: [String: String]) async throws {
        var req = try buildRequest(method: "PATCH", path: path)
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await performVoid(req)
    }

    private func delete(_ path: String) async throws {
        let req = try buildRequest(method: "DELETE", path: path)
        try await performVoid(req)
    }

    private func buildRequest(method: String, path: String, authenticated: Bool = true, queryItems: [URLQueryItem]? = nil) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if let items = queryItems { components.queryItems = items }
        guard let url = components.url else { throw APIError.httpError(0, "invalid URL") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if authenticated {
            guard let tok = token else { throw APIError.noToken }
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.httpError(0, "invalid response") }

        if http.statusCode == 204 { throw APIError.noContent }

        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)
            throw APIError.httpError(http.statusCode, msg)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func performVoid(_ request: URLRequest) async throws {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.httpError(0, "invalid response") }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)
            throw APIError.httpError(http.statusCode, msg)
        }
    }
}
