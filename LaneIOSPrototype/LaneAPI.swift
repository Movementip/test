import Foundation

struct APIResult {
    let status: Int
    let headers: [AnyHashable: Any]
    let data: Data

    var pretty: String {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: formatted, encoding: .utf8) {
            return string
        }
        return String(data: data, encoding: .utf8) ?? "<binary: \(data.count) bytes>"
    }

    var json: Any? {
        try? JSONSerialization.jsonObject(with: data)
    }
}

enum LaneAPIError: LocalizedError {
    case invalidURL
    case nonHTTP
    case http(Int, String)
    case decoding(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .nonHTTP: return "Non-HTTP response"
        case let .http(code, body): return "HTTP \(code): \(body)"
        case let .decoding(message): return "Decode error: \(message)"
        case .emptyResponse: return "Lane returned an empty response"
        }
    }
}

actor LaneAPI {
    static let shared = LaneAPI()

    private var base = URL(string: "https://laneapi.com")!

    func setBase(_ value: String) {
        if let url = URL(string: value) {
            base = url
        }
    }

    private func build(
        path: String,
        method: String,
        token: String?,
        query: [URLQueryItem],
        headers: [String: String],
        json: Any?
    ) throws -> URLRequest {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(url: base.appendingPathComponent(clean), resolvingAgainstBaseURL: false) else {
            throw LaneAPIError.invalidURL
        }

        let cleanQuery = query.filter { item in
            guard let value = item.value else { return false }
            return !value.isEmpty
        }
        if !cleanQuery.isEmpty {
            components.queryItems = cleanQuery
        }

        guard let url = components.url else {
            throw LaneAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }

        return request
    }

    func request(
        path: String,
        method: String = "GET",
        token: String? = nil,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        json: Any? = nil
    ) async throws -> APIResult {
        let request = try build(path: path, method: method, token: token, query: query, headers: headers, json: json)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LaneAPIError.nonHTTP
        }

        return APIResult(status: http.statusCode, headers: http.allHeaderFields, data: data)
    }

    private func decoded<T: Decodable>(
        _ type: T.Type,
        path: String,
        method: String = "GET",
        token: String? = nil,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        json: Any? = nil
    ) async throws -> T {
        let result = try await request(path: path, method: method, token: token, query: query, headers: headers, json: json)

        guard (200..<300).contains(result.status) else {
            throw LaneAPIError.http(result.status, result.pretty)
        }

        do {
            return try JSONDecoder().decode(T.self, from: result.data)
        } catch {
            throw LaneAPIError.decoding(error.localizedDescription + "\n" + result.pretty)
        }
    }

    // MARK: Telegram auth
    // APK: https://t.me/lane_music_bot?start=auth<android_id>
    // APK: GET /auth/{authId}, 20 attempts, 3 seconds between attempts.
    func pollAuth(authId: String, attempts: Int = 20) async throws -> LaneTokenResponse {
        let clean = authId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            throw LaneAPIError.decoding("Empty Telegram auth id")
        }

        var lastStatus = 0
        for index in 0..<attempts {
            let result = try await request(path: "/auth/\(clean)")
            lastStatus = result.status

            if (200..<300).contains(result.status), !result.data.isEmpty {
                if let response = try? JSONDecoder().decode(LaneTokenResponse.self, from: result.data) {
                    return response
                }

                // Some Lane backend revisions wrap the bearer token differently.
                // Accept a token discovered anywhere in the JSON response.
                if let object = result.json,
                   let token = JSONProbe.token(object),
                   !token.isEmpty {
                    return LaneTokenResponse(token: token, isFirstAuth: nil)
                }
            }

            if index + 1 < attempts {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }

        throw LaneAPIError.http(lastStatus, "Authorization token was not returned after \(attempts) attempts")
    }

    // MARK: Catalog / player
    // Exact TrackRepositoryImpl search call recovered from APK:
    // /platforms/search?q=<query>&platform=all&ver=1.0
    func search(token: String, query: String) async throws -> LaneCombinedSearchResponse {
        try await decoded(
            LaneCombinedSearchResponse.self,
            path: "/platforms/search",
            token: token,
            query: [
                .init(name: "q", value: query),
                .init(name: "platform", value: "all"),
                .init(name: "ver", value: "1.0")
            ]
        )
    }

    func searchRaw(token: String, query: String) async throws -> APIResult {
        try await request(
            path: "/platforms/search",
            token: token,
            query: [
                .init(name: "q", value: query),
                .init(name: "platform", value: "all"),
                .init(name: "ver", value: "1.0")
            ]
        )
    }

    func searchHints(token: String, query: String) async throws -> APIResult {
        try await request(path: "/platforms/v2/hints", token: token, query: [.init(name: "q", value: query)])
    }

    func stream(token: String, trackId: String, refId: String?, quality: String?) async throws -> TrackStreamingResult {
        try await decoded(
            TrackStreamingResult.self,
            path: "/track/stream",
            token: token,
            query: [
                .init(name: "trackId", value: trackId),
                .init(name: "refId", value: refId),
                .init(name: "streamQuality", value: quality)
            ]
        )
    }

    func downloadURL(token: String, trackId: String, quality: String?) async throws -> TrackStreamingResult {
        try await decoded(
            TrackStreamingResult.self,
            path: "/track/download",
            token: token,
            query: [
                .init(name: "trackId", value: trackId),
                .init(name: "streamQuality", value: quality)
            ]
        )
    }

    func trackStats(token: String, trackId: String) async throws -> TrackStatsDTO {
        try await decoded(TrackStatsDTO.self, path: "/track/stats", token: token, query: [.init(name: "trackId", value: trackId)])
    }

    func trackLyrics(token: String, trackId: String) async throws -> APIResult {
        try await request(path: "/track/\(trackId)/lyrics", token: token)
    }

    func recommendations(token: String, trackId: String, platform: String) async throws -> APIResult {
        try await request(
            path: "/platforms/recommendations",
            token: token,
            query: [
                .init(name: "trackId", value: trackId),
                .init(name: "platform", value: platform)
            ]
        )
    }

    func album(token: String, albumId: String) async throws -> APIResult {
        try await request(path: "/platforms/album", token: token, query: [.init(name: "albumId", value: albumId)])
    }

    func artist(token: String, artistId: String) async throws -> APIResult {
        try await request(path: "/platforms/artist", token: token, query: [.init(name: "artistId", value: artistId)])
    }

    // MARK: Home / account
    func home(token: String) async throws -> APIResult {
        try await request(path: "/feed/home", token: token)
    }

    func account(token: String, deviceLanguage: String) async throws -> UserAccountDTO {
        try await decoded(UserAccountDTO.self, path: "/account", token: token, headers: ["DL": deviceLanguage])
    }

    func userInfo(token: String, laneId: String) async throws -> UserInfoDTO {
        try await decoded(UserInfoDTO.self, path: "/user-info", token: token, query: [.init(name: "laneId", value: laneId)])
    }

    func editProfile(
        token: String,
        name: String,
        username: String,
        avatarURL: String,
        headerURL: String,
        statusText: String
    ) async throws -> APIResult {
        try await request(
            path: "/user/edit",
            method: "POST",
            token: token,
            json: [
                "name": name,
                "username": username,
                "avatarUrl": avatarURL,
                "headerUrl": headerURL,
                "statusText": statusText
            ]
        )
    }

    func checkUsername(token: String, username: String) async throws -> APIResult {
        try await request(path: "/user/check-user-name", token: token, query: [.init(name: "username", value: username)])
    }

    // MARK: Library
    func userPlaylists(token: String) async throws -> [LanePlaylist] {
        try await decoded([LanePlaylist].self, path: "/user/playlists", token: token)
    }

    func userAlbums(token: String) async throws -> [LaneAlbum] {
        try await decoded([LaneAlbum].self, path: "/user/albums", token: token)
    }

    func userArtists(token: String) async throws -> [LaneArtist] {
        try await decoded([LaneArtist].self, path: "/user/artists", token: token)
    }

    func recentRaw(token: String) async throws -> APIResult {
        try await request(path: "/user/recent", token: token)
    }

    func playlist(token: String, playlistId: String, platform: String? = nil) async throws -> APIResult {
        try await request(
            path: "/playlist/\(playlistId)",
            token: token,
            query: [.init(name: "platform", value: platform)]
        )
    }

    func playlistTracks(token: String, playlistId: String, page: Int = 0, pageSize: Int = 100) async throws -> PaginatedResult<TrackData> {
        try await decoded(
            PaginatedResult<TrackData>.self,
            path: "/playlist/\(playlistId)/tracks",
            token: token,
            query: [
                .init(name: "page", value: String(page)),
                .init(name: "pageSize", value: String(pageSize))
            ]
        )
    }

    // CreatePlaylist fields recovered from APK:
    // playlistImageUrl, playlistName, playlistDescription, playlistTracks, creatorLid
    func createPlaylist(
        token: String,
        imageURL: String,
        name: String,
        description: String,
        tracks: [String],
        creatorLid: String
    ) async throws -> APIResult {
        try await request(
            path: "/create-playlist",
            method: "POST",
            token: token,
            json: [
                "playlistImageUrl": imageURL,
                "playlistName": name,
                "playlistDescription": description,
                "playlistTracks": tracks,
                "creatorLid": creatorLid
            ]
        )
    }

    func editPlaylist(
        token: String,
        playlistId: String,
        imageURL: String,
        name: String,
        description: String
    ) async throws -> APIResult {
        try await request(
            path: "/edit-playlist",
            method: "POST",
            token: token,
            json: [
                "playlistImageUrl": imageURL,
                "playlistName": name,
                "playlistDescription": description,
                "playlistId": playlistId
            ]
        )
    }

    func deletePlaylist(token: String, playlistId: String) async throws -> APIResult {
        try await request(path: "/delete-playlist", token: token, query: [.init(name: "playlistId", value: playlistId)])
    }

    func addPlaylistToLibrary(token: String, playlistId: String) async throws -> APIResult {
        try await request(path: "/user/playlist/add", token: token, query: [.init(name: "playlistId", value: playlistId)])
    }

    func addTracks(token: String, playlistId: String, trackIds: [String]) async throws -> APIResult {
        try await request(
            path: "/user/playlist/add-tracks",
            method: "POST",
            token: token,
            query: [.init(name: "playlistId", value: playlistId)],
            json: trackIds
        )
    }

    func removeTrack(token: String, playlistId: String, trackId: String) async throws -> APIResult {
        try await request(
            path: "/user/playlist/remove-track",
            token: token,
            query: [
                .init(name: "playlistId", value: playlistId),
                .init(name: "trackId", value: trackId)
            ]
        )
    }

    // MARK: Social
    func friends(token: String, page: Int = 0, pageSize: Int = 50, query: String = "") async throws -> PaginatedResult<UserInfoDTO> {
        try await decoded(
            PaginatedResult<UserInfoDTO>.self,
            path: "/user/friends",
            token: token,
            query: [
                .init(name: "page", value: String(page)),
                .init(name: "pageSize", value: String(pageSize)),
                .init(name: "q", value: query)
            ]
        )
    }

    func userSearch(token: String, query: String) async throws -> [UserInfoDTO] {
        try await decoded([UserInfoDTO].self, path: "/users/search", token: token, query: [.init(name: "q", value: query)])
    }

    func follow(token: String, userId: String) async throws -> APIResult {
        try await request(path: "/user/follow/\(userId)", method: "POST", token: token)
    }

    func unfollow(token: String, userId: String) async throws -> APIResult {
        try await request(path: "/user/unfollow/\(userId)", method: "DELETE", token: token)
    }

    func followers(token: String, laneId: String, page: Int = 0, pageSize: Int = 50) async throws -> PaginatedResult<UserInfoDTO> {
        try await decoded(
            PaginatedResult<UserInfoDTO>.self,
            path: "/user/followers",
            token: token,
            query: [
                .init(name: "laneId", value: laneId),
                .init(name: "page", value: String(page)),
                .init(name: "pageSize", value: String(pageSize))
            ]
        )
    }

    func following(token: String, laneId: String, page: Int = 0, pageSize: Int = 50) async throws -> PaginatedResult<UserInfoDTO> {
        try await decoded(
            PaginatedResult<UserInfoDTO>.self,
            path: "/user/following",
            token: token,
            query: [
                .init(name: "laneId", value: laneId),
                .init(name: "page", value: String(page)),
                .init(name: "pageSize", value: String(pageSize))
            ]
        )
    }

    func friendPresence(token: String) async throws -> APIResult {
        try await request(path: "/user/friends/presence", token: token)
    }

    // MARK: Comments
    func comments(
        token: String,
        trackId: String,
        page: Int = 0,
        pageSize: Int = 50,
        sortBy: String? = nil
    ) async throws -> PaginatedResult<LaneTrackCommentDTO> {
        try await decoded(
            PaginatedResult<LaneTrackCommentDTO>.self,
            path: "/track/\(trackId)/comments",
            token: token,
            query: [
                .init(name: "page", value: String(page)),
                .init(name: "pageSize", value: String(pageSize)),
                .init(name: "sortBy", value: sortBy)
            ]
        )
    }

    // CreateTrackComment fields recovered from APK: text, trackId, attachment
    func createTrackComment(token: String, trackId: String, text: String, attachment: String = "") async throws -> APIResult {
        try await request(
            path: "/comment/track",
            method: "POST",
            token: token,
            json: [
                "text": text,
                "trackId": trackId,
                "attachment": attachment
            ]
        )
    }

    func likeComment(token: String, commentId: String) async throws -> APIResult {
        try await request(path: "/comment/\(commentId)/like", method: "POST", token: token)
    }

    func unlikeComment(token: String, commentId: String) async throws -> APIResult {
        try await request(path: "/comment/\(commentId)/like", method: "DELETE", token: token)
    }

    func replies(token: String, commentId: String, page: Int = 0, pageSize: Int = 50) async throws -> PaginatedResult<LaneTrackCommentDTO> {
        try await decoded(
            PaginatedResult<LaneTrackCommentDTO>.self,
            path: "/comment/\(commentId)/replies",
            token: token,
            query: [
                .init(name: "page", value: String(page)),
                .init(name: "pageSize", value: String(pageSize))
            ]
        )
    }

    // CreateReply fields recovered from APK: text, attachment, replyToUserId
    func createReply(
        token: String,
        commentId: String,
        text: String,
        attachment: String = "",
        replyToUserId: String = ""
    ) async throws -> APIResult {
        try await request(
            path: "/comment/\(commentId)/reply",
            method: "POST",
            token: token,
            json: [
                "text": text,
                "attachment": attachment,
                "replyToUserId": replyToUserId
            ]
        )
    }

    // MARK: Notifications / history / import
    func notifications(token: String, page: Int = 0, pageSize: Int = 50, filter: String? = nil) async throws -> APIResult {
        try await request(
            path: "/notifications",
            token: token,
            query: [
                .init(name: "page", value: String(page)),
                .init(name: "pageSize", value: String(pageSize)),
                .init(name: "filter", value: filter)
            ]
        )
    }

    func unreadNotifications(token: String) async throws -> APIResult {
        try await request(path: "/notifications/unread-count", token: token)
    }

    func markNotificationRead(token: String, id: String) async throws -> APIResult {
        try await request(path: "/notifications/\(id)/read", method: "POST", token: token)
    }

    func markAllNotificationsRead(token: String) async throws -> APIResult {
        try await request(path: "/notifications/read-all", method: "POST", token: token)
    }

    func searchHistory(token: String) async throws -> APIResult {
        try await request(path: "/user/search/history", token: token)
    }

    func telegramImportStart(token: String) async throws -> APIResult {
        try await request(path: "/import/telegram/start", token: token)
    }

    func telegramImportFinish(token: String) async throws -> APIResult {
        try await request(path: "/import/telegram/finish", token: token)
    }
}
