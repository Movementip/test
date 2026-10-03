import Foundation
import CryptoKit

final class LaneTestClock: @unchecked Sendable {
    static let shared = LaneTestClock()
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_700_000_000)
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return date }
    private func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; date.addTimeInterval(seconds) }
    var timing: LaneRetryTiming { LaneRetryTiming(now: { self.now() }, sleep: { seconds in
        try Task.checkCancellation()
        self.advance(seconds)
        await Task.yield()
        try Task.checkCancellation()
    }) }
}

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
    private static var followingFriend = false
    private static var equippedBadge: String?
    private static var candleWriteCount = 0
    private static var candleSaved = false
    private static var clearFailedOnce = false
    private static var reorderFailedOnce = false
    private static var limitedUntil: [String: Date] = [:]
    private static var limitedNonce: [String: String] = [:]
    private static var limitedOnce = Set<String>()
    private static var resolverCalls = 0
    private static var membershipReads = 0
    private static var staleOrder: [String: [String]] = [:]
    private static var staleOrderReads: [String: Int] = [:]

    static func resolverCount() -> Int { lock.lock(); defer { lock.unlock() }; return resolverCalls }

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
                headerFields: result.status == 429 ? ["Content-Type": "application/json", "Retry-After": "3"] : ["Content-Type": "application/json"]
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
        let multipart = request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/") == true
        let body = try BNITWireFixture.plaintext(request, wireBody: multipart ? Data() : wire)

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
        case "/user/presence":
            try require(request.httpMethod == "POST", "Presence must be POST")
            let value = try object(body)
            try require(Set(value.keys) == ["trackId", "positionMs", "isPaused"], "APK presence fields changed")
            try require(value["positionMs"] as? Int == 1200 && value["isPaused"] as? Bool == false && value["trackId"] as? String == "track-1", "Presence payload mismatch")
            return (200, Data(#"{"ok":true}"#.utf8))
        case "/user/friends/presence":
            return (200, Data(#"[{"laneId":"friend","userName":"friend","displayedName":"Friend","avatarUrl":null,"trackId":"track-1","trackTitle":"One","isOnline":true,"isPaused":false}]"#.utf8))
        case "/events":
            return (200, Data(#"[{"type":"FRIEND_ACTIVITY","laneId":"friend","trackId":"track-1","positionMs":1200,"isPaused":false},{"type":"FRIEND_ONLINE_STATUS","laneId":"friend","isOnline":true},{"type":"PREMIUM_ACTIVATED","expirationDate":1900000000000,"isPremium":true},{"type":"PROXY_REQUEST","url":"https://untrusted.invalid/"}]"#.utf8))
        case "/payment/pricing":
            return (200, Data(#"{"countryCode":"RU","monthly":{"amount":199,"periodName":"1 month","premiumCurrency":"RUB"},"yearly":{"amount":1499,"periodName":"1 year","premiumCurrency":"RUB"},"lifetime":{"amount":5999,"periodName":"Forever","premiumCurrency":"RUB"}}"#.utf8))
        case "/payment/cancel-subscription":
            try require(request.httpMethod == "POST", "Cancellation must be POST")
            return (200, Data(#"{"status":"cancelled"}"#.utf8))
        case "/v1/share/get":
            try require(request.httpMethod == "GET" && request.value(forHTTPHeaderField: "Authorization") == nil,
                        "Public share resolution must never send the account bearer token")
            let type = query.first { $0.name == "id" }?.value ?? ""
            return (200, try JSONSerialization.data(withJSONObject: ["shareContentType": type, "shareItemId": "canonical-\(type)",
                "trackName": "One", "albumName": "Album", "artistName": "Lane", "playlistName": "Playlist",
                "shareCoverUrl": "", "userName": "Friend", "userId": "friend", "userAvatarUrl": ""]))
        case "/user/upload/photo":
            try require(request.httpMethod == "POST" && multipart, "Image upload is multipart POST")
            let type = query.first { $0.name == "type" }?.value
            try require(type == "avatar" || type == "header_gif", "Image upload target must match the APK")
            let text = String(data: wire, encoding: .utf8) ?? ""
            try require(text.contains("name=\"file\"") && text.contains(type == "header_gif" ? "image/gif" : "image/jpeg"), "Multipart file name/media type changed")
            try require(wire.contains(Data("fixture-image".utf8)), "Multipart bytes must not be encrypted")
            return (200, Data(#"{"url":"https://lane.test/uploaded-image.jpg"}"#.utf8))

        case "/user/edit":
            try require(request.httpMethod == "POST", "Profile edit must be POST")
            let json = try object(body)
            try require(Set(json.keys) == ["name", "username", "avatarUrl", "headerUrl", "statusText"], "EditProfileData fields changed")
            try require(json["name"] as? String == "Updated Lane", "Profile name mismatch")
            return (200, Data(#"{"ok":true}"#.utf8))
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
                if playlistID == "import-rate", let limited = try rateLimited(key: "add", deleting: false, request: request) { return limited }
                Self.importWriteSizes.append(ids.count)
                if playlistID == "import-resume", !Self.didFailMiddleBatch, !(Self.playlists[playlistID] ?? []).isEmpty {
                    Self.didFailMiddleBatch = true
                    return (503, Data(#"{"code":"TEMPORARY_FAILURE"}"#.utf8))
                }
                var saved = Self.playlists[playlistID] ?? []
                // Real edges may insert new batches at the front, not append.
                for id in ids where !saved.contains(id) { saved.insert(id, at: 0) }
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

        case "/playlist/reorder":
            try require(request.httpMethod == "POST", "Reordering must use the APK POST")
            let json = try object(body)
            guard let id = json["playlistId"] as? String, let ids = json["newOrder"] as? [String] else { throw URLError(.badServerResponse) }
            Self.lock.lock(); defer { Self.lock.unlock() }
            try require(Set(ids) == Set(Self.playlists[id] ?? []), "Reordering must retain unrelated tracks and not be used as deletion")
            if id == "import-order-retry", !Self.reorderFailedOnce {
                Self.reorderFailedOnce = true
                return (503, Data(#"{"code":"ORDER_RETRY"}"#.utf8))
            }
            if id == "import-order-lag", Self.staleOrder[id] == nil {
                Self.staleOrder[id] = Self.playlists[id] ?? []
                Self.staleOrderReads[id] = 5
            }
            if id == "import-order-ignored" { return (200, Data(#"{"ok":true}"#.utf8)) }
            try require(id != "import-incomplete", "Partial membership must never be submitted as a reorder permutation")
            Self.playlists[id] = ids
            return (200, Data(#"{"ok":true}"#.utf8))

        case "/user/playlist/remove-track":
            try require(request.httpMethod == "GET" && body.isEmpty, "APK remove-track is an empty-body GET")
            let id = query.first { $0.name == "playlistId" }?.value ?? ""
            let track = query.first { $0.name == "trackId" }?.value ?? ""
            Self.lock.lock(); defer { Self.lock.unlock() }
            if id == "import-clear-rate", let limited = try rateLimited(key: "remove", deleting: true, request: request) { return limited }
            if id == "import-clear-cancel", let limited = try rateLimited(key: "cancel-remove", deleting: true, request: request) { return limited }
            if id == "import-clear", track == "lane-1", !Self.clearFailedOnce {
                Self.clearFailedOnce = true
                return (503, Data(#"{"code":"REMOVE_RETRY"}"#.utf8))
            }
            Self.playlists[id]?.removeAll { $0 == track }
            return (200, Data(#"{"ok":true}"#.utf8))

        case "/user/tracks":
            Self.lock.lock(); Self.resolverCalls += 1; Self.lock.unlock()
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

        case "/user/follow/friend", "/user/unfollow/friend":
            try require(request.httpMethod == (path.contains("/unfollow/") ? "DELETE" : "POST") && body.isEmpty, "APK follow/unfollow must not change method or body")
            Self.lock.lock(); Self.followingFriend = path.contains("/follow/"); Self.lock.unlock()
            return (200, Data(#"{"ok":true}"#.utf8))

        case "/user-info":
            let id = query.first { $0.name == "laneId" }?.value
            try require(id == "friend" || id == "badge-user", "Profile must use laneId")
            Self.lock.lock(); let followed = Self.followingFriend; let equipped = Self.equippedBadge; Self.lock.unlock()
            return (200, try JSONSerialization.data(withJSONObject: ["laneId": id!, "displayedName": "Friend", "isFollowing": followed,
                "equippedBadgeId": equipped.map { $0 as Any } ?? NSNull(),
                "badges": [["definition": ["badgeId": "legend", "name": "Legend", "imageUrl": "https://lane.test/legend.png",
                    "badgeColor": "#ff8284", "description": ["en": "Reward", "ru": "Награда", "uk": "Винагорода"]], "earnedAt": Int64(1700000000000)]]]))

        case "/badges/definitions":
            try require(request.httpMethod == "GET" && body.isEmpty, "Badge definitions must be a read")
            return (200, Data(##"[{"badgeId":"legend","name":"Legend","imageUrl":"https://lane.test/legend.png","badgeColor":"#ff8284","description":{"en":"Reward","ru":"Награда","uk":"Винагорода"}}]"##.utf8))

        case "/user/badge/equip":
            let json = try object(body)
            try require(request.httpMethod == "POST" && Set(json.keys) == ["badgeId"], "EquipBadgeRequest body changed")
            try require(json["badgeId"] as? String == "legend" || json["badgeId"] is NSNull, "Removing a badge must encode explicit null")
            Self.lock.lock(); Self.equippedBadge = json["badgeId"] as? String; Self.lock.unlock()
            return (200, Data())

        case "/platforms/artist/rip/candles-count":
            try require(query.first { $0.name == "artistId" }?.value == "rip-artist", "Candle count uses artistId")
            Self.lock.lock(); let saved = Self.candleSaved; Self.lock.unlock()
            return (200, Data((saved ? "2" : "1").utf8))

        case "/artist/rip-artist/candles":
            try require(request.httpMethod == "GET" && body.isEmpty, "Candles must be GET")
            try require(query.first { $0.name == "page" }?.value == "1" && query.first { $0.name == "pageSize" }?.value == "20", "APK candles use 1-based pages of 20")
            Self.lock.lock(); let saved = Self.candleSaved; Self.lock.unlock()
            let values: [[String: Any]] = [["id": saved ? "saved-candle" : "old-candle", "text": saved ? "Music stays with us" : "A memory",
                "timestamp": Int64(1700000000000), "author": NSNull()]]
            return (200, try JSONSerialization.data(withJSONObject: ["items": values, "page": 1, "pageSize": 20, "totalPages": 1]))

        case "/artist/rip-artist/candle":
            let json = try object(body)
            try require(request.httpMethod == "POST" && Set(json.keys) == ["text"] && json["text"] as? String == "Music stays with us", "PlaceCandleRequest must send only text")
            Self.lock.lock(); Self.candleWriteCount += 1; let writes = Self.candleWriteCount; Self.candleSaved = writes > 1; Self.lock.unlock()
            if writes == 1 { return (503, Data(#"{"message":"Transient candle error"}"#.utf8)) }
            try require(writes == 2, "A non-idempotent candle write must not replay automatically")
            return (200, Data(#"{"id":"saved-candle","text":"Music stays with us","timestamp":1700000000000,"author":null}"#.utf8))

        case "/user/followers", "/user/following":
            try require(query.first { $0.name == "laneId" }?.value == "friend", "People list must use laneId")
            try require(query.first { $0.name == "page" }?.value == "0" && query.first { $0.name == "pageSize" }?.value == "30", "People pagination is zero-based")
            return (200, Data(#"{"items":[{"laneId":"friend","displayedName":"Friend"}],"page":0,"pageSize":30,"totalPages":1}"#.utf8))

        case "/track/effect":
            try require(request.httpMethod == "GET" && body.isEmpty, "Effects use GET, not a speed-adjusted local player")
            try require(query.first { $0.name == "trackId" }?.value == "track-1", "Effect must reference the canonical Lane track")
            try require(["speedup", "slowed_reverb"].contains(query.first { $0.name == "effect" }?.value ?? ""), "APK effect identifiers changed")
            try require(!query.contains(where: { $0.name == "streamQuality" }), "Effect endpoint does not accept streamQuality")
            return (200, Data(#"{"url":"https://lane.test/effect.m4a","trackId":"track-1"}"#.utf8))

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
                try require(request.cachePolicy == .reloadIgnoringLocalCacheData, "Membership confirmation must bypass the local HTTP cache")
                Self.lock.lock(); defer { Self.lock.unlock() }
                var ids = Self.playlists[id] ?? []
                if id == "import-membership-lag", !ids.isEmpty {
                    Self.membershipReads += 1
                    if Self.membershipReads == 2, let limited = try rateLimited(key: "confirm", deleting: false, request: request) { return limited }
                    if Self.membershipReads < 5 { ids = Array(ids.prefix(15)) }
                }
                if let stale = Self.staleOrder[id], (Self.staleOrderReads[id] ?? 0) > 0 {
                    Self.staleOrderReads[id, default: 0] -= 1
                    ids = stale
                }
                if id == "import-incomplete" {
                    return (200, try JSONSerialization.data(withJSONObject: ["playlistId": id, "playlistTracksIds": ids, "tracksCount": ids.count + 5]))
                }
                return (200, try JSONSerialization.data(withJSONObject: ["playlistId": id, "playlistTracksIds": ids]))
            }
            throw NSError(domain: "LaneContractTests", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected request: \(path)"
            ])
        }
    }

    // Called while holding the fixture lock. Reject early retries and verify
    // that a fresh signature authenticates the original body on every retry.
    private func rateLimited(key: String, deleting: Bool, request: URLRequest) throws -> (status: Int, data: Data)? {
        let now = LaneTestClock.shared.now()
        let nonce = try BNITWireFixture.metadata(request)[2]
        if !Self.limitedOnce.contains(key) {
            Self.limitedOnce.insert(key)
            Self.limitedUntil[key] = now.addingTimeInterval(deleting ? 60 : 3)
            Self.limitedNonce[key] = nonce
            return (429, Data(#"{"code":"RATE_LIMITED","message":"Rate limit exceeded. Retry after 3 seconds."}"#.utf8))
        }
        try require(now >= Self.limitedUntil[key]!, "Client retried before the server cooldown expired")
        try require(nonce != Self.limitedNonce[key], "429 retry must be freshly signed")
        return nil
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
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        precondition(LaneRateLimitPolicy.delay(headers: ["retry-after": "3"], data: Data(), now: now, deleting: true) == 60)
        precondition(LaneRateLimitPolicy.delay(headers: ["Retry-After": "90"], data: Data(), now: now, deleting: true) == 90)
        precondition(LaneRateLimitPolicy.delay(headers: [:], data: Data(#"{"message":"Retry after 17 seconds."}"#.utf8), now: now, deleting: false) == 17)
        precondition(LaneRateLimitPolicy.delay(headers: ["Retry-After": "Tue, 14 Nov 2023 22:14:20 GMT"], data: Data(), now: now, deleting: false) == 60)
        let range = LaneAudioHTTPRange.parse("bytes 65536-131071/768044")
        precondition(range?.start == 65536 && range?.end == 131071 && range?.total == 768044)
        for invalid in ["bytes */100", "bytes 20-10/100", "bytes 0-100/100", "bytes 0-10/*", "garbage", "bytes -1-2/100"] {
            precondition(LaneAudioHTTPRange.parse(invalid) == nil)
        }
        precondition(LaneAudioHTTPRange.chunkSize == 65536)
        precondition(LaneTrackEffect.allCases.map(\.rawValue) == ["original", "speedup", "slowed_reverb"])
        precondition(abs(LaneTrackEffect.speedUp.position(from: 30, effect: .slowed) - 30 / 1.22 * 0.91) < 0.00001)
        precondition(LaneTrackEffect.original.position(from: .nan, effect: .speedUp) == 0)
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

        let api = LaneAPI(urlSession: session, requestSigner: BNITLaneRequestSigner(), retryTiming: LaneTestClock.shared.timing)
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
        for effect in [LaneTrackEffect.speedUp, .slowed] {
            let audio = try await api.trackEffect(token: "test-token", trackId: "track-1", effect: effect)
            precondition(audio.trackId == "track-1" && audio.url == "https://lane.test/effect.m4a")
        }
        try await api.follow(token: "test-token", userId: "friend").requireSuccess()
        let followed = try await api.userInfo(token: "test-token", laneId: "friend")
        precondition(followed.isFollowing == true)
        try await api.unfollow(token: "test-token", userId: "friend").requireSuccess()
        let unfollowed = try await api.userInfo(token: "test-token", laneId: "friend")
        precondition(unfollowed.isFollowing == false)
        let followers = try await api.followers(token: "test-token", laneId: "friend", page: 0, pageSize: 30)
        let following = try await api.following(token: "test-token", laneId: "friend", page: 0, pageSize: 30)
        precondition(followers.items.first?.laneId == "friend" && following.items.first?.laneId == "friend")

        let privacyDefaults = try JSONDecoder().decode(LanePrivacySettings.self, from: Data("{}".utf8))
        precondition(privacyDefaults == LanePrivacySettings())
        let definitions = try await api.badgeDefinitions(token: "test-token")
        precondition(definitions.first?.description.localized(language: "ru") == "Награда")
        try await api.equipBadge(token: "test-token", badgeId: "legend").requireSuccess()
        let badgeOwner = try await api.userInfo(token: "test-token", laneId: "badge-user")
        precondition(badgeOwner.equippedBadge?.definition.imageUrl == "https://lane.test/legend.png")
        let freshBadgeAPI = LaneAPI(urlSession: session, requestSigner: BNITLaneRequestSigner())
        await freshBadgeAPI.setBase("https://lane.test")
        let restoredBadge = try await freshBadgeAPI.userInfo(token: "test-token", laneId: "badge-user")
        precondition(restoredBadge.equippedBadgeId == "legend")
        try await api.equipBadge(token: "test-token", badgeId: nil).requireSuccess()
        let removedBadge = try await freshBadgeAPI.userInfo(token: "test-token", laneId: "badge-user")
        precondition(removedBadge.equippedBadge == nil && removedBadge.badges?.count == 1)
        let ripArtist = try JSONDecoder().decode(LaneArtist.self, from: Data(#"{"id":"rip-artist","custom":{"badges":["rip"],"ripInfo":{"startDate":631152000000,"endDate":1700000000000,"additionalText":"Eternal memory"}}}"#.utf8))
        precondition(ripArtist.custom?.ripInfo?.endDate == 1700000000000)
        precondition(LaneCandleText.isValid(String(repeating: "😀", count: 100)))
        precondition(!LaneCandleText.isValid(String(repeating: "😀", count: 101)))
        precondition(!LaneCandleText.isValid(" \n"))
        let beforeCandles = try await api.artistCandleCount(token: "test-token", artistId: "rip-artist")
        precondition(beforeCandles == 1)
        do {
            _ = try await api.placeArtistCandle(token: "test-token", artistId: "rip-artist", text: "Music stays with us")
            preconditionFailure("Rejected candle must not silently retry")
        } catch LaneAPIError.http(let code, _) { precondition(code == 503) }
        let beforePage = try await api.artistCandles(token: "test-token", artistId: "rip-artist")
        precondition(beforePage.items.first?.id == "old-candle")
        let savedCandle = try await api.placeArtistCandle(token: "test-token", artistId: "rip-artist", text: "Music stays with us")
        precondition(savedCandle.id == "saved-candle")
        let restoredCandles = try await freshBadgeAPI.artistCandles(token: "test-token", artistId: "rip-artist")
        let restoredCount = try await freshBadgeAPI.artistCandleCount(token: "test-token", artistId: "rip-artist")
        precondition(restoredCandles.items.first?.id == "saved-candle" && restoredCount == 2)
        for invalidID in ["", "../other", "id?other=1", "id#fragment", "..", "%2F"] {
            do {
                _ = try await api.placeArtistCandle(token: "test-token", artistId: invalidID, text: "Music stays with us")
                preconditionFailure("Invalid artist ID must not issue a write")
            } catch LaneAPIError.decoding { }
        }
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
        let image = try await api.uploadProfileImage(token: "test-token", data: Data("fixture-image".utf8), target: "avatar")
        precondition(image == "https://lane.test/uploaded-image.jpg")
        _ = try await api.uploadProfileImage(token: "test-token", data: Data("fixture-image".utf8), target: "header", isGIF: true)
        try await api.editProfile(token: "test-token", name: "Updated Lane", username: "lane", avatarURL: image, headerURL: "", statusText: "Music").requireSuccess()

        let preview = try await api.importPreview(
            token: "test-token",
            platform: "Yandex",
            yandexPlaylistId: "https://music.yandex.ru/playlists/lk.42"
        )
        precondition(preview.playlistTracksIds == ["track-1", "track-2"])
        let partialPreview = try JSONDecoder().decode([TrackData].self, from: Data(#"[{"songId":"lane-1","title":"One"}]"#.utf8))
        precondition(LanePlaylist(playlistTracksIds: ["source-2", "source-1"], playlistTracks: partialPreview).importSourceIDs == ["source-2", "source-1"], "Partial resolved preview must not reshuffle the source IDs")
        for type in ["track", "artist", "album", "playlist"] {
            let shared = try await api.openShare(id: type)
            precondition(shared.shareContentType == type && shared.shareItemId == "canonical-\(type)")
        }
        do { _ = try await api.openShare(id: "unknown"); preconditionFailure("Unsupported share type must be rejected") }
        catch { }
        for good in ["lane://share/abc-123", "https://music.sk-lane.com/abc-123"] {
            precondition(LaneIncomingShare(url: URL(string: good)!)?.id == "abc-123")
        }
        for bad in ["https://evil.example/abc", "lane://evil/abc", "lane://share/", "lane://share/a/b", "lane://share/a%2Fb", "https://user@music.sk-lane.com/id", "https://music.sk-lane.com.evil/id"] {
            precondition(LaneIncomingShare(url: URL(string: bad)!) == nil)
        }

        UserDefaults.standard.set("raw", forKey: "lane.diag.addBody")
        let sourceIDs = (0..<1151).map { "source-\($0)" }
        let imported = try await api.importTrackBatches(token: "test-token", playlistId: "import-large", sourceIDs: sourceIDs)
        precondition(imported == 1151)
        precondition(LaneMockURLProtocol.savedIDs("import-large").count == 1151)
        precondition(LaneMockURLProtocol.savedIDs("import-large") == sourceIDs.map { $0.replacingOccurrences(of: "source-", with: "lane-") })
        precondition(Array(LaneMockURLProtocol.batchSizes().suffix(77)) == Array(repeating: 15, count: 76) + [11])

        // The real Yandex source has 1,394 available entries, while Lane's
        // importable subset has 1,151. Its ID order can be opposite to Yandex.
        // Repair a completed import using its cached metadata, with no new
        // playlist writes or resolver calls, even through a fresh API client.
        let largeReference = (0..<1394).map { index in
            YandexImportTrack(yandexID: "yandex-\(1393 - index)", originalIndex: index,
                title: "source-\(1393 - index)", artists: [], coverURL: nil)
        }
        let beforeRepairResolutions = LaneMockURLProtocol.resolverCount()
        let beforeRepairWrites = LaneMockURLProtocol.batchSizes().count
        var readBackOrder: [String] = []
        _ = try await api.importTrackBatches(token: "test-token", playlistId: "import-large", sourceIDs: sourceIDs,
            orderReference: largeReference, confirmedOrder: { ids, _ in readBackOrder = ids })
        let sourceOrder = sourceIDs.reversed().map { $0.replacingOccurrences(of: "source-", with: "lane-") }
        precondition(readBackOrder == sourceOrder && LaneMockURLProtocol.savedIDs("import-large") == sourceOrder)
        precondition(LaneMockURLProtocol.resolverCount() == beforeRepairResolutions)
        precondition(LaneMockURLProtocol.batchSizes().count == beforeRepairWrites)
        _ = try await api.importTrackBatches(token: "test-token", playlistId: "import-large", sourceIDs: sourceIDs,
            sort: .oldest, orderReference: largeReference)
        precondition(LaneMockURLProtocol.savedIDs("import-large") == Array(sourceOrder.reversed()))

        // The server's later regional/page snapshot may have the opposite
        // order even after the final reorder was confirmed. The persisted
        // display preference must keep all 1,151 rows stable without reviving
        // removed songs, dropping new likes, or depending on cached metadata.
        let preference = LanePlaylistOrderPreference(trackIDs: sourceOrder, sort: .original)
        let restoredPreference = try JSONDecoder().decode(LanePlaylistOrderPreference.self,
            from: JSONEncoder().encode(preference))
        precondition(restoredPreference.isServerConfirmed, "Old confirmed preferences must retain their status")
        precondition(restoredPreference.orderedMemberIDs(Array(sourceOrder.reversed())) == sourceOrder)
        let membership = ["new-like"] + Array(sourceOrder.dropFirst().reversed())
        precondition(restoredPreference.orderedMemberIDs(membership) == ["new-like"] + Array(sourceOrder.dropFirst()))
        precondition(restoredPreference.orderedMemberIDs([]).isEmpty)
        let oldestPreference = LanePlaylistOrderPreference(trackIDs: Array(sourceOrder.reversed()), sort: .oldest)
        precondition(oldestPreference.orderedMemberIDs(sourceOrder) == Array(sourceOrder.reversed()))
        let pendingPreference = LanePlaylistOrderPreference(trackIDs: sourceOrder, sort: .original, serverConfirmed: false)
        let restoredPending = try JSONDecoder().decode(LanePlaylistOrderPreference.self, from: JSONEncoder().encode(pendingPreference))
        precondition(!restoredPending.isServerConfirmed)
        precondition(restoredPending.orderedMemberIDs(Array(sourceOrder.reversed())) == sourceOrder)

        // Android's sign-in screen sends only the favorite playlist ID from
        // a Collection anchor, never a password, cookie or provider token.
        let accountID = "lk.93c5f910-a510-453b-b478-7d125512d824"
        precondition(YandexAccountImportSource.likedPlaylistID(from: "/playlists/\(accountID)?ref_id=tracking#fragment") == accountID)
        precondition(YandexAccountImportSource.likedPlaylistID(from: "https://music.yandex.ru/playlists/\(accountID)") == accountID)
        precondition(YandexAccountImportSource.likedPlaylistID(from: "https://music.yandex.ru:443/playlists/\(accountID)") == accountID)
        for href in ["https://music.yandex.ru.evil.test/playlists/\(accountID)",
                     "https://music.yandex.ru@evil.test/playlists/\(accountID)",
                     "https://user:password@music.yandex.ru/playlists/\(accountID)",
                     "http://music.yandex.ru/playlists/\(accountID)",
                     "https://music.yandex.ru:8443/playlists/\(accountID)",
                     "https://passport.yandex.ru/playlists/\(accountID)",
                     "/playlists/not-liked", "/playlists/lk.", "/playlists/lk.bad/extra",
                     "/playlists/lk.%2Fbad", "/playlists/lk.неверно"] {
            precondition(YandexAccountImportSource.likedPlaylistID(from: href) == nil, href)
        }
        precondition(YandexAccountImportSource.isCollectionOrigin(YandexAccountImportSource.collectionURL))
        precondition(!YandexAccountImportSource.isCollectionOrigin(URL(string: "https://music.yandex.ru.evil.test/collection")!))
        let loginQuery = URLComponents(url: YandexAccountImportSource.loginURL, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(loginQuery.first { $0.name == "retpath" }?.value == YandexAccountImportSource.collectionURL.absoluteString)

        // Stop at the failed middle batch; a new client can continue without
        // losing the first 15 or sending duplicate playlist writes.
        do {
            _ = try await api.importTrackBatches(token: "test-token", playlistId: "import-resume", sourceIDs: Array(sourceIDs.prefix(31)))
            preconditionFailure("A rejected batch must not report success")
        } catch {
            precondition(LaneMockURLProtocol.savedIDs("import-resume").count == 15)
        }
        let fresh = LaneAPI(urlSession: session, requestSigner: BNITLaneRequestSigner(), retryTiming: LaneTestClock.shared.timing)
        await fresh.setBase("https://lane.test")
        await fresh.setSigningConfiguration(LaneSigningConfiguration(mode: .custom, apiKeyHeader: "", apiKey: ""))
        let resumed = try await fresh.importTrackBatches(token: "test-token", playlistId: "import-resume", sourceIDs: Array(sourceIDs.prefix(31)))
        precondition(resumed == 31)
        precondition(LaneMockURLProtocol.savedIDs("import-resume").count == 31)

        // Cross-batch sort is durable, not just a reversed eight-row preview.
        let small = Array(sourceIDs.prefix(31))
        let duplicateTitleTracks = try JSONDecoder().decode([TrackData].self, from: Data(#"[{"songId":"wrong-artist","title":"Днями ночами","artistsDisplayedName":"Other artist"},{"songId":"right-artist","title":"Днями ночами","artistsDisplayedName":"МУККА & pyrokinesis"}]"#.utf8))
        let punctuationSource = [YandexImportTrack(yandexID: "63606604", originalIndex: 1515,
            title: "Днями-ночами", artists: ["pyrokinesis", "МУККА"], coverURL: nil)]
        precondition(LaneImportOrdering.sourceOrder(duplicateTitleTracks, reference: punctuationSource).matched == 1)
        precondition(LaneImportOrdering.ordered(duplicateTitleTracks, sort: .original, reference: punctuationSource).first?.songId == "right-artist")
        do {
            _ = try await api.importTrackBatches(token: "test-token", playlistId: "import-unmatched", sourceIDs: small,
                orderReference: [YandexImportTrack(yandexID: "unknown", originalIndex: 0, title: "Unmatched metadata", artists: [], coverURL: nil)],
                selectedOrder: { _, _ in preconditionFailure("Unmatched metadata cannot create a guessed display preference") })
            preconditionFailure("No source matches must not be presented as confirmed source order")
        } catch let LaneImportConfirmationError.order(saved, detail) {
            precondition(saved == 31 && detail.contains("No guessed ordering"))
        }
        _ = try await api.importTrackBatches(token: "test-token", playlistId: "import-oldest", sourceIDs: small, sort: .oldest)
        precondition(LaneMockURLProtocol.savedIDs("import-oldest") == small.reversed().map { $0.replacingOccurrences(of: "source-", with: "lane-") })
        try await api.addTracks(token: "test-token", playlistId: "import-reference", trackIds: ["unrelated"]).requireSuccess()
        let reference = (0..<31).reversed().map { YandexImportTrack(yandexID: "yandex-\($0)", originalIndex: 30 - $0, title: "source-\($0)", artists: [], coverURL: nil) }
        _ = try await api.importTrackBatches(token: "test-token", playlistId: "import-reference", sourceIDs: small, orderReference: reference)
        precondition(LaneMockURLProtocol.savedIDs("import-reference") == small.reversed().map { $0.replacingOccurrences(of: "source-", with: "lane-") } + ["unrelated"])
        do {
            _ = try await api.importTrackBatches(token: "test-token", playlistId: "import-order-retry", sourceIDs: small)
            preconditionFailure("Failed server ordering must not report ordered import success")
        } catch { precondition(LaneMockURLProtocol.savedIDs("import-order-retry").count == 31) }
        let resolutionsBeforeRetry = LaneMockURLProtocol.resolverCount()
        let writesBeforeRetry = LaneMockURLProtocol.batchSizes().count
        _ = try await fresh.importTrackBatches(token: "test-token", playlistId: "import-order-retry", sourceIDs: small)
        precondition(LaneMockURLProtocol.savedIDs("import-order-retry") == small.map { $0.replacingOccurrences(of: "source-", with: "lane-") })
        precondition(LaneMockURLProtocol.resolverCount() == resolutionsBeforeRetry, "Ordering resume must not resolve all source tracks again")
        precondition(LaneMockURLProtocol.batchSizes().count == writesBeforeRetry, "Ordering resume must not resend already saved batches")
        _ = try await api.importTrackBatches(token: "test-token", playlistId: "import-rate", sourceIDs: small)
        _ = try await api.importTrackBatches(token: "test-token", playlistId: "import-order-lag", sourceIDs: small)
        _ = try await api.importTrackBatches(token: "test-token", playlistId: "import-membership-lag", sourceIDs: small, progress: { processed, _, saved, _ in
            // The first resolver/write callback cannot show unconfirmed IDs.
            if processed == 15 { precondition(saved.isEmpty, "A 2xx write must not display durable checkmarks") }
        })
        var ignoredDisplayOrder: [String] = []
        do {
            _ = try await api.importTrackBatches(token: "test-token", playlistId: "import-order-ignored", sourceIDs: sourceIDs,
                sort: .oldest, orderReference: largeReference,
                selectedOrder: { ids, _ in ignoredDisplayOrder = ids },
                confirmedOrder: { _, _ in preconditionFailure("An ignored server reorder cannot report confirmation") })
            preconditionFailure("An ignored reorder must not claim the requested order is durable")
        } catch let LaneImportConfirmationError.order(saved, _) { precondition(saved == 1151) }
        precondition(ignoredDisplayOrder == Array(sourceOrder.reversed()))
        precondition(LaneMockURLProtocol.savedIDs("import-order-ignored") != ignoredDisplayOrder)
        precondition(Set(LaneMockURLProtocol.savedIDs("import-order-ignored")) == Set(ignoredDisplayOrder))
        do {
            _ = try await api.importTrackBatches(token: "test-token", playlistId: "import-incomplete", sourceIDs: small,
                selectedOrder: { _, _ in preconditionFailure("Incomplete membership cannot create a complete order preference") })
            preconditionFailure("Incomplete membership must not reorder away unrelated songs")
        } catch let LaneImportConfirmationError.order(saved, detail) {
            precondition(saved == 31 && detail.contains("incomplete"))
        }
        do {
            _ = try await api.clearPlaylistTracks(token: "test-token", playlistId: "import-incomplete")
            preconditionFailure("Partial playlist metadata must not claim a complete clear")
        } catch { precondition(LaneMockURLProtocol.savedIDs("import-incomplete").count == 31) }
        // The server rejected the first delete for 3 seconds, but the user's
        // deletion policy requires at least one minute. No regional retry rush.
        _ = try await api.importTrackBatches(token: "test-token", playlistId: "import-clear-rate", sourceIDs: small)
        let beforeCooldown = LaneTestClock.shared.now()
        _ = try await api.clearPlaylistTracks(token: "test-token", playlistId: "import-clear-rate", stage: { stage in
            if stage.contains("Лимит") { precondition(stage.contains("удалено")) }
        })
        precondition(LaneTestClock.shared.now().timeIntervalSince(beforeCooldown) >= 60)
        precondition(LaneMockURLProtocol.savedIDs("import-clear-rate").isEmpty)
        _ = try await api.importTrackBatches(token: "test-token", playlistId: "import-clear-cancel", sourceIDs: small)
        var allowDeletion = true
        do {
            _ = try await api.clearPlaylistTracks(token: "test-token", playlistId: "import-clear-cancel",
                shouldContinue: { allowDeletion }, stage: { if $0.contains("Лимит") { allowDeletion = false } })
            preconditionFailure("Logout/cancel during the minute wait must stop further mutations")
        } catch is CancellationError { }
        precondition(LaneMockURLProtocol.savedIDs("import-clear-cancel").count == 31)

        _ = try await api.importTrackBatches(token: "test-token", playlistId: "import-clear", sourceIDs: small)
        do {
            _ = try await api.clearPlaylistTracks(token: "test-token", playlistId: "import-clear")
            preconditionFailure("Partial deletion must not report success")
        } catch { precondition(!LaneMockURLProtocol.savedIDs("import-clear").isEmpty) }
        _ = try await fresh.clearPlaylistTracks(token: "test-token", playlistId: "import-clear")
        precondition(LaneMockURLProtocol.savedIDs("import-clear").isEmpty)
        precondition(LaneMockURLProtocol.savedIDs("import-large").count == 1151, "Clearing must only affect its target")
        do {
            _ = try await api.clearPlaylistTracks(token: "test-token", playlistId: "import-resume", shouldContinue: { false })
            preconditionFailure("A changed account must cancel deletion")
        } catch is CancellationError { }
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

        try await api.updatePresence(token: "test-token", trackID: "track-1", positionMs: 1200, isPaused: false)
        let activity = try await api.friendActivity(token: "test-token")
        precondition(activity.count == 1 && activity[0].trackId == "track-1" && activity[0].isOnline == true)
        let events = try await api.serverEvents(token: "test-token")
        precondition(events.filter(\.refreshesFriends).count == 2 && events.filter(\.refreshesAccount).count == 1)
        precondition(!events.last!.refreshesFriends && !events.last!.refreshesAccount)
        let prices = try await api.pricing(token: "test-token")
        precondition(prices.monthly.amount == 199 && prices.lifetime.premiumCurrency == "RUB")
        let cancellation = try await api.cancelSubscription(token: "test-token")
        precondition(cancellation.status == "cancelled")
        print("0.93 social/payment contracts passed: exact presence body, friend DTO defaults, known/unknown inert events, Lane pricing and mock-only cancellation.")

        let expectedPaths = [
            "/create-playlist",
            "/user/playlist/add-tracks",
            "/user/tracks",
            "/playlist/playlist-created/tracks",
            "/track/stats",
            "/user/import/preview"
        ]
        precondition(expectedPaths.allSatisfy(LaneMockURLProtocol.received))
        print("Additional 0.92 contracts passed: Yandex account playlist-ID parsing/security boundaries, 1151-track ignored reorder keeps selected display order but never confirms server order, pending preference roundtrip, incomplete/unmatched source cannot create an unsafe preference.")
        print("Lane contract tests passed: APK-native cipher/signature, 1151 tracks in batches of 15, source order from 1394-entry reference, confirmed-order callback, persisted source/reverse display preference through reversed membership snapshots/new likes/removals, completed-import order repair without new resolver calls/writes, punctuation and collaborator matching, 429 fresh-signature retries, minimum 60-second deletion cooldown/cancellation, delayed membership/order readback, truthful saved-vs-order states, ordering-only resume without re-resolving/rewriting, durable source/reverse order, partial clear/retry, canonical albums, server likes, privacy, notifications, multipart uploads, ranges/effects, earned badges/server equip-removal, memorial pagination/count and non-replayed confirmed candle writes.")
    }
}
