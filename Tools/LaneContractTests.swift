import Foundation
import CryptoKit

// Independent inverse of the APK's metadata encoder. Verify the HMAC against
// the actual ciphertext on the wire, not against the unencrypted test payload.
enum BNITWireFixture {
    static let key = Data("SqperSzvbntKmv_CbnngeThis_12303!".utf8)

    static func metadata(_ request: URLRequest) throws -> [String] {
        let alphabet = Array("zxcvbnmasdfghjklqwertyuiop1234567890-_QWERTYUIOPASDFGHJKLZXCVBNM")
        let standard = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
        let encoded = request.value(forHTTPHeaderField: "X-Core-Token") ?? ""
        let normalized = String(encoded.map { character in
            if character == "." { return "=" }
            return alphabet.firstIndex(of: character).map { standard[$0] } ?? "?"
        })
        guard let bytes = Data(base64Encoded: normalized), bytes.count >= 4 else {
            throw URLError(.cannotDecodeContentData)
        }
        let salt = Array(bytes.prefix(4))
        let secret = Array(key)
        var state = Array(0...255).map(UInt8.init)
        var j = 0
        for i in 0..<256 {
            j = (j + Int(state[i]) + Int(secret[i & 31]) + Int(salt[i & 3])) & 255
            state.swapAt(i, j)
        }
        var i = 0
        j = 0
        var previous: UInt8 = 0x5a
        var plain = Data()
        for cipher in bytes.dropFirst(4) {
            i = (i + 1) & 255
            let oldSi = state[i]
            j = (j + Int(oldSi)) & 255
            let oldSj = state[j]
            state.swapAt(i, j)
            let rotated = cipher &- previous
            plain.append(((rotated >> 3) | (rotated << 5)) ^ state[((Int(oldSi) + Int(oldSj)) & 255) ^ Int(previous)])
            previous = cipher
        }
        let fields = String(data: plain, encoding: .utf8)?.components(separatedBy: "|") ?? []
        guard fields.count == 6 else { throw URLError(.cannotDecodeContentData) }
        return fields
    }

    static func plaintext(_ request: URLRequest, wireBody: Data) throws -> Data {
        let fields = try metadata(request)
        let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        var query: [String: String] = [:]
        for item in parts.queryItems ?? [] where query[item.name] == nil {
            query[item.name] = item.value ?? ""
        }
        let canonicalQuery = query.keys.sorted().map { "\($0)=\(query[$0]!)" }.joined(separator: "&")
        var canonical = Data("\(request.httpMethod!):\(parts.percentEncodedPath):\(canonicalQuery):\(fields[1]):\(fields[2]):".utf8)
        canonical.append(wireBody)
        canonical.append(Data(":\(fields[3]):\(fields[4])".utf8))
        let hmac = HMAC<SHA256>.authenticationCode(for: canonical, using: SymmetricKey(data: key))
            .map { String(format: "%02x", $0) }.joined()
        precondition(hmac == fields[0], "Signature must authenticate the transmitted ciphertext")
        precondition(fields[5] == (wireBody.isEmpty ? "0" : "1"))
        return BNITLaneRequestSigner.encryptRequestBody(wireBody, nonce: fields[2], timestamp: fields[1])
    }
}

// LaneAPI normally uses this transport for the official no-VPN fallback. The
// contract suite stays in custom-backend mode and supplies a macOS test stub.
enum AndroidNetworkTransport {
    struct Response {
        let data: Data
        let response: HTTPURLResponse
    }

    static func data(for request: URLRequest, timeout: TimeInterval = 12) async throws -> Response {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LaneMockURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var direct = request
        direct.setValue("1", forHTTPHeaderField: "X-Test-Direct")
        let (data, response) = try await session.data(for: direct)
        return Response(data: data, response: response as! HTTPURLResponse)
    }
}

final class LaneMockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var paths = Set<String>()
    private static var didUseObjectAddFallback = false
    private static var didUsePlaylistTracksFallback = false
    private static var playlists: [String: [String]] = [:]
    private static var importWriteSizes: [Int] = []
    private static var didFailMiddleBatch = false
    private static var failedNonce: String?
    private static var didVerifyDirectRetry = false

    static func savedIDs(_ id: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return playlists[id] ?? []
    }

    static func batchSizes() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return importWriteSizes
    }

    static func verifiedDirectRetry() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return didVerifyDirectRetry
    }

    static func received(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return paths.contains(path)
    }

    static func usedObjectAddFallback() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return didUseObjectAddFallback
    }

    static func usedPlaylistTracksFallback() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return didUsePlaylistTracksFallback
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "lane.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        Self.lock.lock()
        Self.paths.insert(url.path)
        Self.lock.unlock()

        do {
            if url.query?.contains("transportProbe=true") == true, request.value(forHTTPHeaderField: "X-Test-Direct") == nil {
                let nonce = try BNITWireFixture.metadata(request)[2]
                Self.lock.lock()
                Self.failedNonce = nonce
                Self.lock.unlock()
                client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
                return
            }
            let result = try response(for: request)
            let response = HTTPURLResponse(
                url: url,
                statusCode: result.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func response(for request: URLRequest) throws -> (status: Int, data: Data) {
        let path = request.url?.path ?? ""
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let wire = try requestBody(request)
        let body = try BNITWireFixture.plaintext(request, wireBody: wire)

        if query.contains(where: { $0.name == "transportProbe" }) {
            let nonce = try BNITWireFixture.metadata(request)[2]
            Self.lock.lock()
            let oldNonce = Self.failedNonce
            Self.didVerifyDirectRetry = nonce != oldNonce
            Self.lock.unlock()
            try require(nonce != oldNonce, "DNS retry must use a fresh nonce")
            let json = try object(body)
            try require(json["trackIds"] as? [String] == ["track-1"], "DNS retry must not double-encrypt JSON")
            return (200, Data(#"{"ok":true}"#.utf8))
        }

        switch path {
        case "/create-playlist":
            try require(request.httpMethod == "POST", "create-playlist must be POST")
            let json = try object(body)
            try require(json["playlistName"] as? String == "Road Trip", "playlistName body mismatch")
            try require(json["playlistTracks"] as? [String] == ["track-1"], "playlistTracks body mismatch")
            try require(json["creatorLid"] as? String == "lane-user", "creatorLid body mismatch")
            return (200, Data(#"{"playlistId":"playlist-created"}"#.utf8))

        case "/user/playlist/add-tracks":
            try require(request.httpMethod == "POST", "add-tracks must be POST")
            let playlistID = query.first(where: { $0.name == "playlistId" })?.value
            if let playlistID, playlistID.hasPrefix("import-") || playlistID == "lane_likes" {
                guard let ids = try JSONSerialization.jsonObject(with: body) as? [String] else {
                    return (400, Data(#"{"code":"INVALID_PLAYLIST_TRACKS_BODY"}"#.utf8))
                }
                try require(!ids.isEmpty && ids.count <= 15, "Every import write must contain at most 15 canonical IDs")
                Self.lock.lock()
                defer { Self.lock.unlock() }
                Self.importWriteSizes.append(ids.count)
                if playlistID == "import-resume", !Self.didFailMiddleBatch, !(Self.playlists[playlistID] ?? []).isEmpty {
                    Self.didFailMiddleBatch = true
                    return (503, Data(#"{"code":"TEMPORARY_FAILURE"}"#.utf8))
                }
                var saved = Self.playlists[playlistID] ?? []
                for id in ids where !saved.contains(id) { saved.append(id) }
                Self.playlists[playlistID] = saved
                return (200, Data(#"{"ok":true}"#.utf8))
            }
            if playlistID == "playlist-fallback" {
                if let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                   json["trackIds"] as? [String] == ["track-3"] {
                    Self.lock.lock()
                    Self.didUseObjectAddFallback = true
                    Self.lock.unlock()
                    return (200, Data(#"{"ok":true}"#.utf8))
                }
                return (
                    400,
                    Data(#"{"code":"INVALID_PLAYLIST_TRACKS_BODY","message":"Invalid playlist tracks body"}"#.utf8)
                )
            }
            if playlistID == "playlist-fallback-modern" {
                if let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                   json["playlistTracks"] as? [String] == ["track-4"] {
                    Self.lock.lock()
                    Self.didUsePlaylistTracksFallback = true
                    Self.lock.unlock()
                    return (200, Data(#"{"ok":true}"#.utf8))
                }
                return (
                    400,
                    Data(#"{"code":"INVALID_PLAYLIST_TRACKS_BODY","message":"Invalid playlist tracks body"}"#.utf8)
                )
            }

            try require(playlistID == "playlist-created", "playlistId query mismatch")
            let array = try JSONSerialization.jsonObject(with: body) as? [String]
            try require(array == ["track-1", "track-2"], "add-tracks must send the APK raw JSON array")
            return (200, Data(#"{"ok":true}"#.utf8))

        case "/user/tracks":
            try require(request.httpMethod == "POST", "user/tracks must be POST")
            if let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
               let ids = json["trackIds"] as? [String], ids.first?.hasPrefix("source-") == true {
                try require(ids.count <= 15, "Every resolver request must contain at most 15 source IDs")
                let tracks = ids.map { ["songId": $0.replacingOccurrences(of: "source-", with: "lane-"), "title": $0] }
                return (200, try JSONSerialization.data(withJSONObject: tracks))
            }
            if let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
               json["trackIds"] as? [String] == ["track-1", "track-2"] {
                return (200, Data(#"[{"songId":"track-1","platform":"spotify","title":"One","artistsDisplayedName":"Lane","spData":{"artists":["artist-1"],"album":"album-1"}},{"songId":"track-2","title":"Two","artistsDisplayedName":"Lane"}]"#.utf8))
            }
            return (
                400,
                Data(#"{"code":"INVALID_TRACK_IDS_BODY","message":"Invalid track ids body"}"#.utf8)
            )

        case "/playlist/playlist-created/tracks":
            try require(query.first(where: { $0.name == "page" })?.value == "1", "playlist page must be 1-based")
            return (200, Data(#"{"items":[{"songId":"track-1","title":"One","artistsDisplayedName":"Lane"}],"totalItems":1,"page":1,"pageSize":50,"totalPages":1}"#.utf8))

        case "/track/stats":
            try require(query.first(where: { $0.name == "trackId" })?.value == "track-1", "stats trackId mismatch")
            return (200, Data(#"{"likesCount":27,"commentsCount":4}"#.utf8))

        case "/user/settings/privacy":
            try require(request.httpMethod == "POST", "Privacy must be POST")
            let json = try object(body)
            try require(Set(json.keys) == ["showPlaylists", "showFollowers", "showFollowing"], "Privacy fields must match UpdatePrivacyRequest")
            try require(json["showPlaylists"] as? Bool == false && json["showFollowers"] as? Bool == true && json["showFollowing"] as? Bool == false, "Privacy boolean values changed")
            return (200, Data(#"{"ok":true}"#.utf8))

        case "/notifications":
            try require(query.first { $0.name == "page" }?.value == "0", "Notification page is zero-based")
            return (200, Data(#"{"items":[{"id":"n1","type":"PLAYLIST_INVITATION","read":false,"timestamp":1700000000000,"actorInfo":{"laneId":"friend","displayedName":"Friend"},"invitationId":"invite-1","playlistId":"shared-1","playlistName":"Road Trip"}],"totalPages":1}"#.utf8))

        case "/notifications/unread-count":
            return (200, Data(#"{"unreadCount":7}"#.utf8))

        case "/notifications/n1/read", "/notifications/read-all":
            try require(request.httpMethod == "POST" && body.isEmpty, "Read acknowledgement is an empty POST")
            return (200, Data(#"{"ok":true}"#.utf8))

        case "/playlist/invite/respond":
            try require(request.httpMethod == "POST", "Invitation response must be POST")
            let json = try object(body)
            try require(json["invitationId"] as? String == "invite-1" && json["accept"] as? Bool == true, "Invitation response fields changed")
            return (200, Data(#"{"ok":true}"#.utf8))

        case "/user/import/preview":
            try require(query.first(where: { $0.name == "platform" })?.value == "yandex", "Yandex platform must be lowercase")
            try require(query.first(where: { $0.name == "yandexPlaylistId" })?.value == "https://music.yandex.ru/playlists/lk.42", "Yandex source mismatch")
            return (200, Data(#"{"playlistId":"preview","playlistName":"Yandex","playlistTracksIds":["track-1","track-2"],"tracksCount":2}"#.utf8))

        default:
            if path.hasPrefix("/playlist/import-") || path == "/playlist/lane_likes" {
                let id = String(path.dropFirst("/playlist/".count))
                return (200, try JSONSerialization.data(withJSONObject: ["playlistId": id, "playlistTracksIds": Self.savedIDs(id)]))
            }
            throw NSError(domain: "LaneContractTests", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected request: \(path)"
            ])
        }
    }

    private func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "LaneContractTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Expected JSON object"
            ])
        }
        return value
    }

    private func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }

        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }

    private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw NSError(domain: "LaneContractTests", code: 2, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
    }
}

@main
struct LaneContractTestRunner {
    static func main() async throws {
        let vector = BNITLaneRequestSigner.encryptRequestBody(
            Data(#"["track-1","track-2"]"#.utf8),
            nonce: "00112233445566778899aabbccddeeff",
            timestamp: "1700000000123"
        ).map { String(format: "%02x", $0) }.joined()
        // Generated by executing c760 from lane1.4.7.apk libbnit.so, not by
        // regenerating the expected value with the Swift implementation.
        precondition(vector == "e0293b6251d538f958b18069875fb3b8f679184afe")
        var upload = URLRequest(url: URL(string: "https://lane.test/avatar")!)
        upload.httpMethod = "POST"
        upload.setValue("multipart/form-data; boundary=fixture", forHTTPHeaderField: "Content-Type")
        upload.httpBody = Data("--fixture\r\noriginal-upload\r\n--fixture--".utf8)
        let signedUpload = try BNITLaneRequestSigner().sign(upload, body: upload.httpBody)
        precondition(signedUpload.httpBody == upload.httpBody)
        let excludedUploadBody = try BNITWireFixture.plaintext(signedUpload, wireBody: Data())
        precondition(excludedUploadBody.isEmpty)
        let stalePlaylistSummary = try JSONDecoder().decode(
            LanePlaylist.self,
            from: Data(#"{"playlistId":"library-playlist","playlistTracksIds":["track-1","track-2"],"tracksCount":0}"#.utf8)
        )
        precondition(stalePlaylistSummary.effectiveTrackCount == 2)

        precondition(
            YandexPlaylistSource.normalize("lk.42") ==
                "https://music.yandex.ru/playlists/lk.42"
        )
        precondition(
            YandexPlaylistSource.normalize("owner/17") ==
                "https://music.yandex.ru/users/owner/playlists/17"
        )
        precondition(
            YandexPlaylistSource.normalize(
                "https://music.yandex.ru/playlists/lk.42?utm_source=share#track"
            ) == "https://music.yandex.ru/playlists/lk.42"
        )

        UserDefaults.standard.set("raw", forKey: "lane.diag.addBody")
        UserDefaults.standard.set("object", forKey: "lane.diag.trackBody")
        defer {
            UserDefaults.standard.removeObject(forKey: "lane.diag.addBody")
            UserDefaults.standard.removeObject(forKey: "lane.diag.trackBody")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LaneMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let api = LaneAPI(urlSession: session, requestSigner: BNITLaneRequestSigner())
        await api.setBase("https://lane.test")
        await api.setSigningConfiguration(
            LaneSigningConfiguration(mode: .custom, apiKeyHeader: "", apiKey: "")
        )

        let createResult = try await api.createPlaylist(
            token: "test-token",
            imageURL: "",
            name: "Road Trip",
            description: "Regression fixture",
            tracks: ["track-1"],
            creatorLid: "lane-user"
        )
        try createResult.requireSuccess()
        let created = try JSONDecoder().decode(PlaylistCreationResponse.self, from: createResult.data)
        precondition(created.playlistId == "playlist-created")

        let addResult = try await api.addTracks(
            token: "test-token",
            playlistId: created.playlistId,
            trackIds: ["track-1", "track-2"]
        )
        try addResult.requireSuccess()

        // A value pinned by an older build must not stop the client from
        // switching to the server's current object body contract.
        UserDefaults.standard.set("raw", forKey: "lane.diag.addBody")
        let healedAddResult = try await api.addTracks(
            token: "test-token",
            playlistId: "playlist-fallback",
            trackIds: ["track-3"]
        )
        try healedAddResult.requireSuccess()
        precondition(LaneMockURLProtocol.usedObjectAddFallback())
        precondition(UserDefaults.standard.string(forKey: "lane.diag.addBody") == "object")

        // A newer edge contract may name the collection after the playlist
        // field. Exhaust all safe encodings instead of stopping after the two
        // formats used by older iOS builds.
        UserDefaults.standard.set("raw", forKey: "lane.diag.addBody")
        let modernAddResult = try await api.addTracks(
            token: "test-token",
            playlistId: "playlist-fallback-modern",
            trackIds: ["track-4"]
        )
        try modernAddResult.requireSuccess()
        precondition(LaneMockURLProtocol.usedPlaylistTracksFallback())
        precondition(UserDefaults.standard.string(forKey: "lane.diag.addBody") == "playlistTracks")

        UserDefaults.standard.set("raw", forKey: "lane.diag.trackBody")
        let resolved = try await api.tracksByIds(
            token: "test-token",
            ids: ["track-1", "track-2"],
            prefetch: false
        )
        precondition(resolved.compactMap(\.songId) == ["track-1", "track-2"])
        precondition(UserDefaults.standard.string(forKey: "lane.diag.trackBody") == "object")
        precondition(resolved.first?.artistIDs == ["artist-1"])
        precondition(TrackCandidate(resolved[0]).artistIDs == ["artist-1"])

        let page = try await api.playlistTracks(
            token: "test-token",
            playlistId: created.playlistId,
            page: 1,
            pageSize: 50
        )
        precondition(page.items.first?.songId == "track-1")

        let stats = try await api.trackStats(token: "test-token", trackId: "track-1")
        precondition(stats == TrackStatsDTO(likesCount: 27, commentsCount: 4))

        let privacyDefaults = try JSONDecoder().decode(LanePrivacySettings.self, from: Data("{}".utf8))
        precondition(privacyDefaults == LanePrivacySettings())
        let privacyWrite = try await api.updatePrivacy(token: "test-token", settings: LanePrivacySettings(showPlaylists: false, showFollowers: true, showFollowing: false))
        try privacyWrite.requireSuccess()
        let notices = try await api.notificationPage(token: "test-token")
        precondition(notices.items.first?.invitationId == "invite-1")
        precondition(notices.items.first?.title == "Friend invited you to a playlist")
        let unread = try await api.notificationUnreadCount(token: "test-token")
        precondition(unread == 7)
        try await api.markNotificationRead(token: "test-token", id: "n1").requireSuccess()
        try await api.markAllNotificationsRead(token: "test-token").requireSuccess()
        try await api.respondToPlaylistInvitation(token: "test-token", invitationId: "invite-1", accept: true).requireSuccess()

        let preview = try await api.importPreview(
            token: "test-token",
            platform: "Yandex",
            yandexPlaylistId: "https://music.yandex.ru/playlists/lk.42"
        )
        precondition(preview.playlistTracksIds == ["track-1", "track-2"])

        UserDefaults.standard.set("raw", forKey: "lane.diag.addBody")
        let sourceIDs = (0..<1151).map { "source-\($0)" }
        let imported = try await api.importTrackBatches(token: "test-token", playlistId: "import-large", sourceIDs: sourceIDs)
        precondition(imported == 1151)
        precondition(LaneMockURLProtocol.savedIDs("import-large").count == 1151)
        precondition(Array(LaneMockURLProtocol.batchSizes().suffix(77)) == Array(repeating: 15, count: 76) + [11])

        // Stop at the failed middle batch; a new client can continue without
        // losing the first 15 or sending duplicate playlist writes.
        do {
            _ = try await api.importTrackBatches(token: "test-token", playlistId: "import-resume", sourceIDs: Array(sourceIDs.prefix(31)))
            preconditionFailure("A rejected batch must not report success")
        } catch {
            precondition(LaneMockURLProtocol.savedIDs("import-resume").count == 15)
        }
        let fresh = LaneAPI(urlSession: session, requestSigner: BNITLaneRequestSigner())
        await fresh.setBase("https://lane.test")
        await fresh.setSigningConfiguration(LaneSigningConfiguration(mode: .custom, apiKeyHeader: "", apiKey: ""))
        let resumed = try await fresh.importTrackBatches(token: "test-token", playlistId: "import-resume", sourceIDs: Array(sourceIDs.prefix(31)))
        precondition(resumed == 31)
        precondition(LaneMockURLProtocol.savedIDs("import-resume").count == 31)

        let like = try await api.addTracks(token: "test-token", playlistId: "lane_likes", trackIds: ["track-1"])
        try like.requireSuccess()
        let serverLikesAfterNewClient = try await fresh.playlist(token: "test-token", playlistId: "lane_likes")
        precondition(serverLikesAfterNewClient.playlistTracksIds == ["track-1"])
        let canonical = try await api.tracksByIds(token: "test-token", ids: ["source-1", "source-2"])
        precondition(LaneTrackBatching.ordered(canonical.map { TrackCandidate($0) }, sourceIDs: ["source-1", "source-2"]).count == 2)

        UserDefaults.standard.set("auto", forKey: "lane.diag.transport")
        defer { UserDefaults.standard.removeObject(forKey: "lane.diag.transport") }
        let retried = try await api.request(path: "/user/tracks", method: "POST", query: [.init(name: "transportProbe", value: "true")], json: ["trackIds": ["track-1"]], candidateBases: [URL(string: "https://lane.test")!])
        precondition(retried.status == 200)
        precondition(LaneMockURLProtocol.verifiedDirectRetry())

        let expectedPaths = [
            "/create-playlist",
            "/user/playlist/add-tracks",
            "/user/tracks",
            "/playlist/playlist-created/tracks",
            "/track/stats",
            "/user/import/preview"
        ]
        precondition(expectedPaths.allSatisfy(LaneMockURLProtocol.received))
        print("Lane contract tests passed: APK-native cipher vector, encrypted/signed bodies, 1151-track 15-item batches, interrupted import resume, canonical album IDs, fresh-client server likes, privacy and notification/invitation contracts.")
    }
}
