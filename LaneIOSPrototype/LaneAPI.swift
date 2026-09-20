import Foundation

private struct LaneReserveResponse: Decodable {
    let apiUrl: String
    let cdnUrl: String
    let countryCode: String?
}

private struct LaneServerTimeResponse: Decodable {
    let timestamp: Int64
}

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
    case protectedClientSignatureRequired

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .nonHTTP: return "Non-HTTP response"
        case let .http(code, body): return "HTTP \(code): \(body)"
        case let .decoding(message): return "Decode error: \(message)"
        case .emptyResponse: return "Lane returned an empty response"
        case .protectedClientSignatureRequired:
            return "The official Lane API requires its supported client-signature mechanism. Configure an authorized signer/SDK or switch to a custom backend."
        }
    }
}

actor LaneAPI {
    static let shared = LaneAPI()

    private var base = URL(string: "https://laneapi.com")!
    private var serviceLDI = ""
    private var signingConfiguration = LaneSigningConfiguration.official
    private var timeOffsetMilliseconds: Int64 = 0

    func setBase(_ value: String) {
        if let url = URL(string: value) {
            base = url
        }
    }

    func currentBaseURL() -> String {
        base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func setServiceLDI(_ value: String) {
        serviceLDI = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setSigningConfiguration(_ value: LaneSigningConfiguration) {
        signingConfiguration = value
    }


    private func decodeOfficialTransport(_ data: Data, response: HTTPURLResponse) throws -> Data {
        guard signingConfiguration.mode == .official,
              response.value(forHTTPHeaderField: "X-Core-Red") == "1",
              let nonce = response.value(forHTTPHeaderField: "X-Resp-Nonce"),
              !nonce.isEmpty else {
            return data
        }

        var decoded = BNITLaneRequestSigner.decryptResponse(data, responseNonce: nonce)

        if response.value(forHTTPHeaderField: "X-Core-Compressed") == "1" {
            decoded = try LaneGzip.decompress(decoded)
        }

        return decoded
    }

    private func syncOfficialServerTime() async throws {
        guard let url = URL(string: "https://laneapi.com/time") else {
            throw LaneAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("close", forHTTPHeaderField: "Connection")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LaneAPIError.nonHTTP
        }

        guard (200..<300).contains(http.statusCode) else {
            throw LaneAPIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let server = try JSONDecoder().decode(LaneServerTimeResponse.self, from: data)
        timeOffsetMilliseconds = server.timestamp - Int64(Date().timeIntervalSince1970 * 1000.0)
    }

    private func isRussianLaneTimezone(_ value: String) -> Bool {
        let zones: Set<String> = [
            "Europe/Kaliningrad", "Europe/Moscow", "Europe/Simferopol", "Europe/Kirov",
            "Europe/Astrakhan", "Europe/Volgograd", "Europe/Saratov", "Europe/Ulyanovsk",
            "Europe/Samara", "Asia/Yekaterinburg", "Asia/Omsk", "Asia/Novosibirsk",
            "Asia/Barnaul", "Asia/Tomsk", "Asia/Novokuznetsk", "Asia/Krasnoyarsk",
            "Asia/Irkutsk", "Asia/Chita", "Asia/Yakutsk", "Asia/Khandyga",
            "Asia/Vladivostok", "Asia/Ust-Nera", "Asia/Magadan", "Asia/Sakhalin",
            "Asia/Srednekolymsk", "Asia/Kamchatka", "Asia/Anadyr"
        ]
        return zones.contains(value)
    }

    @discardableResult
    func discoverOfficialServer() async throws -> String {
        guard signingConfiguration.mode == .official else {
            return currentBaseURL()
        }

        var timezone = TimeZone.current.identifier
        if timezone == "Europe/Kiev" { timezone = "Europe/Kyiv" }

        // LaneApp uses the RU server directly for Russian time zones.
        if isRussianLaneTimezone(timezone) {
            base = URL(string: "https://ru.laneapi.com")!
            return currentBaseURL()
        }

        guard let reserveURL = URL(string: "https://laneapi.com/reserve") else {
            throw LaneAPIError.invalidURL
        }

        func fetchReserve() async throws -> (Data, HTTPURLResponse) {
            var reserveRequest = URLRequest(url: reserveURL)
            reserveRequest.httpMethod = "GET"
            reserveRequest.timeoutInterval = 8
            reserveRequest.setValue(timezone, forHTTPHeaderField: "TZ")
            reserveRequest.setValue("close", forHTTPHeaderField: "Connection")

            let signer = signingConfiguration.signer(timeOffsetMilliseconds: timeOffsetMilliseconds)
            let signed = try signer.sign(reserveRequest, body: nil)
            let (rawData, response) = try await URLSession.shared.data(for: signed)

            guard let http = response as? HTTPURLResponse else {
                throw LaneAPIError.nonHTTP
            }

            let decoded = try decodeOfficialTransport(rawData, response: http)
            return (decoded, http)
        }

        var (data, response) = try await fetchReserve()

        // Android retries /reserve after correcting its clock when the signature
        // is rejected due to time drift.
        if response.statusCode == 401 {
            try await syncOfficialServerTime()
            (data, response) = try await fetchReserve()
        }

        guard (200..<300).contains(response.statusCode) else {
            throw LaneAPIError.http(
                response.statusCode,
                String(data: data, encoding: .utf8) ?? "<reserve response>"
            )
        }

        let reserve = try JSONDecoder().decode(LaneReserveResponse.self, from: data)
        guard let discovered = URL(string: reserve.apiUrl), discovered.host != nil else {
            throw LaneAPIError.invalidURL
        }

        base = discovered
        return currentBaseURL()
    }

    func backendConfig() async throws -> LaneBackendConfig {
        let result = try await request(path: "/config")
        guard (200..<300).contains(result.status) else {
            throw LaneAPIError.http(result.status, result.pretty)
        }
        return try JSONDecoder().decode(LaneBackendConfig.self, from: result.data)
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

        // Mirror Lane Android 1.4.7 ServiceInfoInterceptor exactly.
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        var timezone = TimeZone.current.identifier
        if timezone == "Europe/Kiev" { timezone = "Europe/Kyiv" }

        request.setValue(language, forHTTPHeaderField: "Accept-Language")
        if !serviceLDI.isEmpty {
            request.setValue(serviceLDI, forHTTPHeaderField: "LDI")
        }
        request.setValue(timezone, forHTTPHeaderField: "TZ")
        request.setValue("207", forHTTPHeaderField: "X-App-Version")
        request.setValue("android", forHTTPHeaderField: "X-Platform")
        request.setValue("dark", forHTTPHeaderField: "X-Theme")
        request.setValue("LaneMusic/1.0 (Android; Mobile)", forHTTPHeaderField: "User-Agent")

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
        let unsigned = try build(path: path, method: method, token: token, query: query, headers: headers, json: json)
        let signer = signingConfiguration.signer(timeOffsetMilliseconds: timeOffsetMilliseconds)
        let request = try signer.sign(unsigned, body: unsigned.httpBody)
        let (rawData, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LaneAPIError.nonHTTP
        }

        let data = try decodeOfficialTransport(rawData, response: http)
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
            if result.status == 401,
               signingConfiguration.mode == .official,
               result.pretty.contains("MISSING_SIGNATURE_TOKEN") {
                throw LaneAPIError.protectedClientSignatureRequired
            }
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

        if serviceLDI.isEmpty {
            serviceLDI = clean
        }

        var candidates: [URL] = []

        if signingConfiguration.mode == .custom {
            candidates = [base]
        } else {
            // Match Android startup: choose the actual regional API server before
            // polling /auth/{ANDROID_ID}. /reserve is itself BNIT protected.
            if let discovered = try? await discoverOfficialServer(),
               let discoveredURL = URL(string: discovered) {
                candidates.append(discoveredURL)
            }

            for candidate in [
                base,
                URL(string: "https://laneapi.com")!,
                URL(string: "https://ru.laneapi.com")!
            ] {
                if !candidates.contains(where: { $0.host == candidate.host }) {
                    candidates.append(candidate)
                }
            }
        }

        var lastStatus = 0
        var lastBody = "No response from Lane authentication servers."

        for index in 0..<attempts {
            for host in candidates {
                let url = host
                    .appendingPathComponent("auth")
                    .appendingPathComponent(clean)

                var req = URLRequest(url: url)
                req.httpMethod = "GET"
                req.timeoutInterval = 8
                req.setValue("application/json", forHTTPHeaderField: "Accept")

                let language = Locale.current.language.languageCode?.identifier ?? "en"
                var timezone = TimeZone.current.identifier
                if timezone == "Europe/Kiev" { timezone = "Europe/Kyiv" }

                req.setValue(language, forHTTPHeaderField: "Accept-Language")
                req.setValue(serviceLDI.isEmpty ? clean : serviceLDI, forHTTPHeaderField: "LDI")
                req.setValue(timezone, forHTTPHeaderField: "TZ")
                req.setValue("207", forHTTPHeaderField: "X-App-Version")
                req.setValue("android", forHTTPHeaderField: "X-Platform")
                req.setValue("dark", forHTTPHeaderField: "X-Theme")
                req.setValue("LaneMusic/1.0 (Android; Mobile)", forHTTPHeaderField: "User-Agent")

                do {
                    let signer = signingConfiguration.signer(timeOffsetMilliseconds: timeOffsetMilliseconds)
                    let signedReq = try signer.sign(req, body: nil)
                    let (rawData, response) = try await URLSession.shared.data(for: signedReq)
                    guard let http = response as? HTTPURLResponse else { continue }

                    let data = try decodeOfficialTransport(rawData, response: http)
                    lastStatus = http.statusCode
                    let result = APIResult(status: http.statusCode, headers: http.allHeaderFields, data: data)
                    lastBody = result.pretty

                    if http.statusCode == 401,
                       signingConfiguration.mode == .official,
                       result.pretty.contains("MISSING_SIGNATURE_TOKEN") {
                        // Re-sync once just like ServerDiscoveryRepository does.
                        try? await syncOfficialServerTime()
                        continue
                    }

                    guard (200..<300).contains(http.statusCode), !data.isEmpty else {
                        continue
                    }

                    if let decoded = try? JSONDecoder().decode(LaneTokenResponse.self, from: data),
                       !decoded.token.isEmpty {
                        base = host
                        return decoded
                    }

                    if let object = result.json,
                       let token = JSONProbe.token(object),
                       !token.isEmpty {
                        base = host
                        return LaneTokenResponse(token: token, isFirstAuth: nil)
                    }

                    if let jsonString = try? JSONDecoder().decode(String.self, from: data),
                       isPlausibleBearerToken(jsonString) {
                        base = host
                        return LaneTokenResponse(token: jsonString, isFirstAuth: nil)
                    }

                    if let plain = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       isPlausibleBearerToken(plain) {
                        base = host
                        return LaneTokenResponse(token: plain, isFirstAuth: nil)
                    }
                } catch {
                    lastBody = error.localizedDescription
                }
            }

            if index + 1 < attempts {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }

        throw LaneAPIError.http(
            lastStatus,
            lastStatus == 404
                ? "No pending Telegram token exists for Authentication ID \(clean). Open Telegram from this screen and send /start auth\(clean), then return and check again."
                : "Lane auth polling ended without a token. Server: \(currentBaseURL()). Last response: \(lastBody)"
        )
    }

    private func isPlausibleBearerToken(_ value: String) -> Bool {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= 20 else { return false }

        let rejected = ["null", "nil", "true", "false", "pending", "waiting", "success", "ok"]
        return !rejected.contains(token.lowercased())
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

    func searchRaw(token: String, query: String, version: String?) async throws -> APIResult {
        try await request(
            path: "/platforms/search",
            token: token,
            query: [
                .init(name: "q", value: query),
                .init(name: "platform", value: "all"),
                .init(name: "ver", value: version)
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

    func trackLyricsTyped(token: String, trackId: String) async throws -> LaneTrackLyrics {
        try await decoded(
            LaneTrackLyrics.self,
            path: "/track/\(trackId)/lyrics",
            token: token
        )
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

    func albumDetail(token: String, albumId: String) async throws -> LaneAlbum {
        try await decoded(LaneAlbum.self, path: "/platforms/album", token: token, query: [.init(name: "albumId", value: albumId)])
    }

    func artist(token: String, artistId: String) async throws -> APIResult {
        try await request(path: "/platforms/artist", token: token, query: [.init(name: "artistId", value: artistId)])
    }

    func artistDetail(token: String, artistId: String) async throws -> LaneArtist {
        try await decoded(LaneArtist.self, path: "/platforms/artist", token: token, query: [.init(name: "artistId", value: artistId)])
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

    // Exact UserApi endpoint recovered from Lane Android 1.4.7:
    // POST /user/tracks?prefetch=<bool> with {"trackIds":[...]}.
    func tracksByIds(token: String, ids: [String], prefetch: Bool = false) async throws -> [TrackData] {
        guard !ids.isEmpty else { return [] }
        return try await decoded(
            [TrackData].self,
            path: "/user/tracks",
            method: "POST",
            token: token,
            query: [.init(name: "prefetch", value: prefetch ? "true" : "false")],
            json: ["trackIds": ids]
        )
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
                .init(name: "sortBy", value: sortBy ?? "Relevance"),
                .init(name: "highlightCommentId", value: nil)
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
