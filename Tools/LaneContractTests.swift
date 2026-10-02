import Foundation

// LaneAPI normally uses this transport for the official no-VPN fallback. The
// contract suite stays in custom-backend mode and supplies a macOS test stub.
enum AndroidNetworkTransport {
    struct Response {
        let data: Data
        let response: HTTPURLResponse
    }

    static func data(for request: URLRequest, timeout: TimeInterval = 12) async throws -> Response {
        throw URLError(.unsupportedURL)
    }
}

final class LaneMockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var paths = Set<String>()
    private static var didUseObjectAddFallback = false
    private static var didUsePlaylistTracksFallback = false

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
        let body = try requestBody(request)

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

        case "/user/import/preview":
            try require(query.first(where: { $0.name == "platform" })?.value == "yandex", "Yandex platform must be lowercase")
            try require(query.first(where: { $0.name == "yandexPlaylistId" })?.value == "https://music.yandex.ru/playlists/lk.42", "Yandex source mismatch")
            return (200, Data(#"{"playlistId":"preview","playlistName":"Yandex","playlistTracksIds":["track-1","track-2"],"tracksCount":2}"#.utf8))

        default:
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

        let api = LaneAPI(urlSession: session)
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

        let preview = try await api.importPreview(
            token: "test-token",
            platform: "Yandex",
            yandexPlaylistId: "https://music.yandex.ru/playlists/lk.42"
        )
        precondition(preview.playlistTracksIds == ["track-1", "track-2"])

        let expectedPaths = [
            "/create-playlist",
            "/user/playlist/add-tracks",
            "/user/tracks",
            "/playlist/playlist-created/tracks",
            "/track/stats",
            "/user/import/preview"
        ]
        precondition(expectedPaths.allSatisfy(LaneMockURLProtocol.received))
        print("Lane contract tests passed (\(expectedPaths.count + 3) mocked API scenarios).")
    }
}
