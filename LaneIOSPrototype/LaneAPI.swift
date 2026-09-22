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
    private let lastWorkingRegionalBaseKey = "lane.lastWorkingRegionalBase"

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

    private func officialRegionalBases(preferCurrent: Bool = false) -> [URL] {
        let primary = URL(string: "https://laneapi.com")!
        let russian = URL(string: "https://ru.laneapi.com")!
        let officialHosts = Set([primary.host, russian.host].compactMap { $0 })
        let timezonePreferred = isRussianLaneTimezone(TimeZone.current.identifier) ? russian : primary
        var candidates: [URL] = []

        func appendOnce(_ candidate: URL) {
            guard !candidates.contains(where: { $0.host == candidate.host }) else { return }
            candidates.append(candidate)
        }

        // A host remembered while VPN was enabled must never outrank the
        // timezone region after VPN is disabled. In Russian timezones Android
        // selects ru.laneapi.com directly, so keep that host first for every
        // safe request, including /track/stream.
        appendOnce(timezonePreferred)

        if preferCurrent {
            appendOnce(base)
        }

        // Android selects ru.laneapi.com first in Russian time zones. A host
        // remembered while a VPN was active must not outrank that regional
        // choice after the VPN is disabled.
        if let saved = UserDefaults.standard.string(forKey: lastWorkingRegionalBaseKey),
           let savedURL = URL(string: saved),
           let host = savedURL.host,
           officialHosts.contains(host) {
            appendOnce(savedURL)
        }

        for candidate in [base, primary, russian] {
            appendOnce(candidate)
        }

        return candidates
    }

    private func rememberWorkingRegionalBase(_ candidate: URL) {
        base = candidate
        let resolved = currentBaseURL()
        UserDefaults.standard.set(resolved, forKey: "lane.base")
        UserDefaults.standard.set(resolved, forKey: lastWorkingRegionalBaseKey)
    }

    private func probeOfficialServer(_ candidate: URL) async throws -> LaneServerTimeResponse {
        let url = candidate.appendingPathComponent("time")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("close", forHTTPHeaderField: "Connection")

        let (data, http) = try await performOfficialRequest(request, directTimeout: 5)
        guard (200..<300).contains(http.statusCode) else {
            throw LaneAPIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(LaneServerTimeResponse.self, from: data)
    }

    /// URLSession is kept as the normal path. When the carrier's resolver or
    /// route stalls, retry the same signed request through the APK-style fast
    /// DNS transport without changing the host used for TLS verification.
    private func performOfficialRequest(
        _ request: URLRequest,
        directTimeout: TimeInterval
    ) async throws -> (Data, HTTPURLResponse) {
        let isBNITSigned = request.value(forHTTPHeaderField: "X-Core-Token") != nil

        // This is the route Android 1.4 uses in Russian time zones. Going to
        // the resolved RU edge first avoids the long system-DNS stall seen on
        // affected mobile providers. TLS still validates ru.laneapi.com.
        if request.url?.host == "ru.laneapi.com" {
            if isBNITSigned {
                let direct = try await AndroidNetworkTransport.data(
                    for: request,
                    timeout: directTimeout
                )
                return (direct.data, direct.response)
            }

            if let direct = try? await AndroidNetworkTransport.data(
                for: request,
                timeout: directTimeout
            ) {
                return (direct.data, direct.response)
            }
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LaneAPIError.nonHTTP
            }
            return (data, http)
        } catch {
            // Never reuse BNIT headers on a second transport. LaneAPI's outer
            // safe-read loop rebuilds and signs a fresh request. Mutations do
            // not retry automatically because their commit state is unknown.
            guard signingConfiguration.mode == .official, !isBNITSigned else {
                throw error
            }
            let direct = try await AndroidNetworkTransport.data(
                for: request,
                timeout: directTimeout
            )
            return (direct.data, direct.response)
        }
    }

    /// Chooses a reachable official region before the signed API requests begin.
    /// Request-level failover remains in place, but this avoids paying the same
    /// timeout repeatedly when one Lane hostname is unavailable without a VPN.
    @discardableResult
    func prepareRegionalHost() async -> String {
        guard signingConfiguration.mode == .official else {
            return currentBaseURL()
        }

        for candidate in officialRegionalBases() {
            if let server = try? await probeOfficialServer(candidate) {
                timeOffsetMilliseconds = server.timestamp - Int64(Date().timeIntervalSince1970 * 1000.0)
                rememberWorkingRegionalBase(candidate)
                let resolved = currentBaseURL()
                return resolved
            }
        }

        return currentBaseURL()
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
        var lastError: Error = LaneAPIError.emptyResponse
        for candidate in officialRegionalBases() {
            do {
                let server = try await probeOfficialServer(candidate)
                timeOffsetMilliseconds = server.timestamp - Int64(Date().timeIntervalSince1970 * 1000.0)
                rememberWorkingRegionalBase(candidate)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError
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
        json: Any?,
        baseURL: URL? = nil
    ) throws -> URLRequest {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let targetBase = baseURL ?? base
        guard var components = URLComponents(url: targetBase.appendingPathComponent(clean), resolvingAgainstBaseURL: false) else {
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
            // Lane Android 1.4.7's kotlinx-serialization converter sends this
            // exact media type. Keep it byte-for-byte compatible because the
            // /user/tracks validator is stricter than most Lane endpoints.
            request.setValue("application/json; charset=UTF8", forHTTPHeaderField: "Content-Type")
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
        let upperMethod = method.uppercased()
        let normalizedPath = "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Most Lane reads are GETs, but several legacy mutations are GETs too.
        // Exclude them explicitly so regional retry can never perform an action
        // twice. /user/tracks is the only read-only POST used by Android 1.4.7.
        let mutatingGETPaths: Set<String> = [
            "/createUserOrLogin",
            "/delete-playlist",
            "/import/telegram/start",
            "/import/telegram/finish",
            "/share/create",
            "/user/history-bump-item",
            "/user/history-delete-item",
            "/user/playlist/add",
            "/user/playlist/remove-track"
        ]
        let readOnlyPOSTPaths: Set<String> = ["/user/tracks"]
        let canFailOverRegionalHost =
            (upperMethod == "GET" && !mutatingGETPaths.contains(normalizedPath)) ||
            (upperMethod == "POST" && readOnlyPOSTPaths.contains(normalizedPath))

        let candidates: [URL]
        if signingConfiguration.mode == .official, canFailOverRegionalHost {
            // Re-evaluate region ordering for every safe read so switching VPN
            // state does not leave the app pinned to a stale global endpoint.
            candidates = officialRegionalBases(preferCurrent: true)
        } else {
            candidates = [base]
        }

        var lastError: Error?
        var lastResult: APIResult?
        // Stream resolution already has endpoint/quality compatibility
        // fallbacks at the player layer. One pass over both regional hosts is
        // enough here and prevents the UI appearing to load forever offline.
        let retryRounds = canFailOverRegionalHost &&
            normalizedPath != "/track/stream" &&
            normalizedPath != "/user/tracks" ? 2 : 1
        let longReadPaths: Set<String> = [
            "/user/import/preview",
            "/user/tracks",
            "/platforms/search",
            "/platforms/album",
            "/platforms/artist",
            "/track/stream",
            "/track/download"
        ]
        let requestTimeout: TimeInterval = canFailOverRegionalHost
            ? (normalizedPath == "/user/import/preview" ? 45 : (normalizedPath == "/track/stream" ? 6 : (normalizedPath == "/user/tracks" ? 12 : (longReadPaths.contains(normalizedPath) ? 20 : 12))))
            : 30

        for round in 0..<retryRounds {
            var shouldRetryRound = false

            for (index, targetBase) in candidates.enumerated() {
                do {
                    let unsigned = try build(
                        path: path,
                        method: method,
                        token: token,
                        query: query,
                        headers: headers,
                        json: json,
                        baseURL: targetBase
                    )

                    let signer = signingConfiguration.signer(timeOffsetMilliseconds: timeOffsetMilliseconds)
                    let signed = try signer.sign(unsigned, body: unsigned.httpBody)

                    var request = signed
                    request.timeoutInterval = requestTimeout

                    let (rawData, http) = try await performOfficialRequest(
                        request,
                        directTimeout: min(max(requestTimeout, 5), 12)
                    )

                    let data = try decodeOfficialTransport(rawData, response: http)
                    let result = APIResult(
                        status: http.statusCode,
                        headers: http.allHeaderFields,
                        data: data
                    )
                    lastResult = result

                    if (200..<400).contains(http.statusCode) {
                        if signingConfiguration.mode == .official {
                            rememberWorkingRegionalBase(targetBase)
                        } else {
                            base = targetBase
                        }
                        return result
                    }

                    let replayRejected = http.statusCode == 401 &&
                        result.pretty.localizedCaseInsensitiveContains("REPLAY_ATTACK_DETECTED")
                    let transient = http.statusCode == 408 ||
                        http.statusCode == 425 ||
                        http.statusCode == 429 ||
                        (500...599).contains(http.statusCode) ||
                        (canFailOverRegionalHost && replayRejected)
                    shouldRetryRound = shouldRetryRound || transient

                    // Safe reads may move to the other regional edge. Mutation
                    // requests never enter this branch, so they remain single-shot.
                    let definitiveStreamRejection = normalizedPath == "/track/stream" &&
                        http.statusCode == 403 &&
                        result.pretty.localizedCaseInsensitiveContains("PREMIUM_REQUIRED")
                    if canFailOverRegionalHost,
                       !definitiveStreamRejection,
                       index + 1 < candidates.count {
                        continue
                    }

                    if !transient || round + 1 >= retryRounds {
                        return result
                    }
                } catch {
                    lastError = error
                    shouldRetryRound = true
                    if index + 1 < candidates.count {
                        continue
                    }
                }
            }

            guard shouldRetryRound, round + 1 < retryRounds else { break }
            try? await Task.sleep(nanoseconds: round == 0 ? 350_000_000 : 750_000_000)
        }

        if let lastResult {
            return lastResult
        }

        throw lastError ?? LaneAPIError.emptyResponse
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

    // Exact Lane Android 1.4.7 contract recovered from the APK:
    // @POST("/user/tracks") with @Body TrackIds. Its kotlinx serializer emits
    // {"trackIds":[...]}; a raw JSON array is not a valid TrackIds body.
    func tracksByIds(token: String, ids: [String], prefetch: Bool = false) async throws -> [TrackData] {
        var seen = Set<String>()
        let clean = ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }

        guard !clean.isEmpty else { return [] }

        return try await decoded(
            [TrackData].self,
            path: "/user/tracks",
            method: "POST",
            token: token,
            query: [.init(name: "prefetch", value: prefetch ? "true" : "false")],
            json: ["trackIds": clean]
        )
    }

    func recentRaw(token: String) async throws -> APIResult {
        try await request(path: "/user/recent", token: token)
    }

    func playlist(token: String, playlistId: String, platform: String? = nil) async throws -> LanePlaylist {
        try await decoded(
            LanePlaylist.self,
            path: "/playlist/\(playlistId)",
            token: token,
            query: [.init(name: "platform", value: platform)]
        )
    }

    func playlistTracks(token: String, playlistId: String, page: Int = 1, pageSize: Int = 50) async throws -> PaginatedResult<TrackData> {
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

    func setPlaylistVisibility(token: String, playlistId: String, visibility: String) async throws -> APIResult {
        try await request(
            path: "/playlist/\(playlistId)/visibility",
            method: "POST",
            token: token,
            json: ["visibility": visibility]
        )
    }

    func createShareLink(token: String, elementId: String, type: String) async throws -> LaneShareItem {
        try await decoded(
            LaneShareItem.self,
            path: "/share/create",
            token: token,
            query: [
                .init(name: "shareElementId", value: elementId),
                .init(name: "shareType", value: type)
            ]
        )
    }

    func setStatusTrack(token: String, trackId: String) async throws -> APIResult {
        try await request(
            path: "/user/status",
            method: "POST",
            token: token,
            json: ["trackId": trackId]
        )
    }

    func invitePlaylistUsers(token: String, playlistId: String, userIds: [String]) async throws -> APIResult {
        try await request(
            path: "/playlist/\(playlistId)/invite",
            method: "POST",
            token: token,
            json: ["userIds": userIds]
        )
    }

    func addTracks(token: String, playlistId: String, trackIds: [String]) async throws -> APIResult {
        // The Android UserApi.M signature is @Body List<String>. Retrying a
        // rejected mutation with guessed object shapes only sends extra POSTs
        // and obscures whether a particular track ID is invalid.
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

    func bumpSearchHistoryItem(token: String, key: String) async throws -> APIResult {
        try await request(
            path: "/user/history-bump-item",
            token: token,
            query: [.init(name: "item", value: key)]
        )
    }

    func deleteSearchHistoryItem(token: String, key: String) async throws -> APIResult {
        try await request(
            path: "/user/history-delete-item",
            token: token,
            query: [.init(name: "item", value: key)]
        )
    }

    func importPreview(
        token: String,
        platform: String,
        spotifyBearerToken: String? = nil,
        spotifyClientToken: String? = nil,
        spotifyPlaylistId: String? = nil,
        soundcloudPlaylistId: String? = nil,
        yandexPlaylistId: String? = nil,
        soundcloudProfileUrl: String? = nil
    ) async throws -> LanePlaylist {
        try await decoded(
            LanePlaylist.self,
            path: "/user/import/preview",
            token: token,
            query: [
                // Android sends Platform.name.lowercase(), not the display label.
                .init(name: "platform", value: platform.lowercased()),
                .init(name: "spotifyBearerToken", value: spotifyBearerToken),
                .init(name: "spotifyClientToken", value: spotifyClientToken),
                .init(name: "spotifyPlaylistId", value: spotifyPlaylistId),
                .init(name: "soundcloudPlaylistId", value: soundcloudPlaylistId),
                .init(name: "yandexPlaylistId", value: yandexPlaylistId),
                .init(name: "soundcloudProfileUrl", value: soundcloudProfileUrl)
            ]
        )
    }

    func telegramImportStart(token: String) async throws -> TelegramImportCode {
        try await decoded(TelegramImportCode.self, path: "/import/telegram/start", token: token)
    }

    func telegramImportFinish(token: String) async throws -> LanePlaylist {
        try await decoded(LanePlaylist.self, path: "/import/telegram/finish", token: token)
    }
}
