import SwiftUI
import UIKit
#if DEBUG
import Network
#endif

@main
struct LaneIOSPrototypeApp: App {
    @StateObject private var session: LaneSession

    init() {
        let value = LaneSession()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--lane-ui-test") {
            _ = LaneUITestAudioServer.shared
            URLProtocol.registerClass(LaneUITestURLProtocol.self)
            value.backendMode = .custom
            value.baseURL = "https://lane-ui.test"
            value.token = "ui-fixture-token"
            value.serverArtists = [LaneUITestFixtures.artist]
            value.queue = [LaneUITestFixtures.track]
            value.currentIndex = 0
            value.currentTrack = LaneUITestFixtures.track
        }
        #endif
        _session = StateObject(wrappedValue: value)
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--lane-ui-test") {
                LaneUITestRoot().environmentObject(session)
            } else {
                ContentView().environmentObject(session)
            }
            #else
            ContentView().environmentObject(session)
            #endif
        }
    }
}

#if DEBUG
// Isolated, mock-only simulator fixtures. Not compiled into the release IPA.
enum LaneUITestFixtures {
    static let album = LaneAlbum(name: "bastards", id: "fixture-album", platform: "spotify", type: "single",
                                 coverUrl: "https://lane-ui.test/panorama", year: "2025-04-25",
                                 artistsDisplayedName: "shadowraze", tracks: ["source-1", "source-2"])
    static let artist = LaneArtist(name: "Автостопом по фазе сна", id: "fixture-artist", platform: "spotify",
                                   headerUrl: "https://lane-ui.test/panorama", topTracks: ["source-1", "source-2"],
                                   albums: [album])
    static let track = TrackCandidate(id: "lane-1", title: "Fixture track 1", subtitle: "Автостопом по фазе сна",
                                      trackID: "lane-1", platform: "spotify", coverURL: "https://lane-ui.test/panorama",
                                      artistIDs: ["fixture-artist"])
}

private struct LaneUITestRoot: View {
    @EnvironmentObject private var session: LaneSession
    @State private var showPlayer = false
    @State private var showEdit = false
    @State private var result = ""
    @State private var gestureReport = "Waiting for edge swipe"

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                NavigationLink("Recommended artist") { APKArtistDetailScreen(seed: LaneUITestFixtures.artist) }
                NavigationLink("Recommended album") { APKAlbumDetailScreen(seed: LaneUITestFixtures.album) }
                NavigationLink("Privacy settings") { PrivacySettingsScreen() }
                NavigationLink("Notification center") { NotificationsScreen() }
                Button("Open player") { showPlayer = true }
                Button("Run session checks") { Task { await checkSession() } }
                Button("Run playback checks") { Task { await checkPlayback() } }
                Button("Edit profile") { showEdit = true }
                Text(result).accessibilityIdentifier("session.result")
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showPlayer) { APKFullPlayerView().environmentObject(session) }
        .sheet(isPresented: $showEdit) { EditProfileSheet().environmentObject(session) }
        .preferredColorScheme(.dark)
        .overlay(alignment: .bottom) {
            Text(gestureReport).font(.system(size: 9)).accessibilityIdentifier("gesture.report")
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LaneEdgeSwipeUIProbe"))) { message in
            if let value = message.object as? String { gestureReport = value }
        }
    }

    private func checkSession() async {
        do {
            let preview = LanePlaylist(playlistTracksIds: (0..<1151).map { "source-\($0)" })
            let firstPage = try await session.tracksForImportPreview(preview)
            guard firstPage.count == 15 else { throw LaneAPIError.decoding("Preview must resolve only the first 15 tracks") }
            let imported = try await session.importTracks((0..<31).map { "source-\($0)" }, into: "fixture-import", resolvingSourceIDs: true)
            guard imported == 31 else { throw LaneAPIError.emptyResponse }
            session.toggleFavorite(LaneUITestFixtures.track)
            for _ in 0..<50 {
                if !session.isFavoriteSyncPending(LaneUITestFixtures.track) { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard session.isFavorite(LaneUITestFixtures.track), !session.isFavoriteSyncPending(LaneUITestFixtures.track) else {
                throw LaneAPIError.decoding("Like not confirmed")
            }
            // Simulate removal of all on-device favorite state while keeping
            // the mock server intact, then sign into the same account again.
            for key in ["lane.favorites", "lane.pendingFavoriteStates", "lane.cachedTrackMetadata", "lane.cachedPlaylistTracks"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
            let fresh = LaneSession()
            fresh.backendMode = .custom
            fresh.baseURL = "https://lane-ui.test"
            fresh.token = "ui-fixture-token"
            await fresh.refreshAfterLogin()
            guard fresh.isFavorite(LaneUITestFixtures.track), fresh.likedTracks.contains(where: { $0.trackID == "lane-1" }) else {
                throw LaneAPIError.decoding("Fresh installation did not restore server likes")
            }
            result = "Session checks passed"
        } catch {
            result = "Session checks failed: \(error.localizedDescription)"
        }
    }

    private func checkPlayback() async {
        do {
            try session.removeDownload(LaneUITestFixtures.track)
            session.requestStream(for: LaneUITestFixtures.track)
            for _ in 0..<150 {
                if session.isPlaying && session.playbackPosition > 0.1 { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard session.isPlaying, session.playbackPosition > 0.1,
                  !LaneUITestAudioServer.shared.finishedFullResponse else {
                throw LaneAPIError.decoding("Playback waited for the whole slow HTTP audio file")
            }
            guard session.playbackBufferedDuration > 0, session.playbackDuration > 0 else {
                throw LaneAPIError.decoding("Player did not publish loaded timeline ranges")
            }
            session.pause()
            session.downloadTrack(LaneUITestFixtures.track)
            for _ in 0..<150 {
                if session.isDownloaded(LaneUITestFixtures.track) { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard session.isDownloaded(LaneUITestFixtures.track) else {
                throw LaneAPIError.decoding("Audio download failed: \(session.output)")
            }
            session.stop()
            LaneUITestAudioServer.shared.stop()
            for key in ["lane.history", "lane.cachedTrackMetadata"] { UserDefaults.standard.removeObject(forKey: key) }
            let offline = LaneSession()
            offline.token = ""
            guard offline.downloadedTracks.contains(where: { $0.trackID == "lane-1" }) else {
                throw LaneAPIError.decoding("Downloaded metadata did not survive clearing history and relaunch")
            }
            offline.requestStream(for: offline.downloadedTracks.first!)
            for _ in 0..<60 {
                if offline.isPlaying && offline.playbackPosition > 0.1 { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard offline.isPlaying, URL(string: offline.streamURL)?.isFileURL == true else {
                throw LaneAPIError.decoding("Offline playback attempted to resolve a network stream: \(offline.output)")
            }
            offline.stop()
            result = "Playback checks passed"
        } catch { result = "Playback checks failed: \(error.localizedDescription)" }
    }
}

/// Real, slow loopback HTTP audio: AVPlayer and URLSession perform actual
/// range/download requests, not a mock playback-state assignment.
private final class LaneUITestAudioServer {
    static let shared = LaneUITestAudioServer()
    private let queue = DispatchQueue(label: "lane.ui.audio.fixture")
    private let lock = NSLock()
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private var port: UInt16?
    private var complete = false
    private let audio: Data
    var url: String? { lock.lock(); defer { lock.unlock() }; return port.map { "http://127.0.0.1:\($0)/audio.wav" } }
    var finishedFullResponse: Bool { lock.lock(); defer { lock.unlock() }; return complete }

    private init() {
        let sampleRate: UInt32 = 16000
        let sampleCount = Int(sampleRate) * 24
        var data = Data()
        func word<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        data.append(Data("RIFF".utf8)); word(UInt32(36 + sampleCount * 2))
        data.append(Data("WAVEfmt ".utf8)); word(UInt32(16)); word(UInt16(1)); word(UInt16(1))
        word(sampleRate); word(sampleRate * 2); word(UInt16(2)); word(UInt16(16))
        data.append(Data("data".utf8)); word(UInt32(sampleCount * 2))
        for index in 0..<sampleCount { word(Int16(sin(Double(index) * 2 * .pi * 440 / Double(sampleRate)) * 400)) }
        audio = data
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try! NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let self {
                self.lock.lock(); self.port = self.listener.port?.rawValue; self.lock.unlock()
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.receive(connection, accumulated: Data())
        }
        listener.start(queue: queue)
    }

    func stop() { queue.async { self.listener.cancel(); self.connections.forEach { $0.cancel() }; self.connections = [] } }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] chunk, _, ended, error in
            guard let self, error == nil else { connection.cancel(); return }
            let data = accumulated + (chunk ?? Data())
            guard let text = String(data: data, encoding: .utf8), text.contains("\r\n\r\n") else {
                if !ended { self.receive(connection, accumulated: data) } else { connection.cancel() }
                return
            }
            var start = 0, end = self.audio.count - 1
            let range = text.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("range:") }
            if let range, let value = range.components(separatedBy: "bytes=").last {
                let fields = value.components(separatedBy: "-")
                start = Int(fields[0]) ?? 0
                if fields.count > 1, let upper = Int(fields[1]) { end = min(upper, end) }
            }
            guard start >= 0, start <= end, start < self.audio.count else { connection.cancel(); return }
            let length = end - start + 1
            var headers = "HTTP/1.1 \(range == nil ? "200 OK" : "206 Partial Content")\r\nContent-Type: audio/wav\r\nAccept-Ranges: bytes\r\nContent-Length: \(length)\r\nConnection: close\r\n"
            if range != nil { headers += "Content-Range: bytes \(start)-\(end)/\(self.audio.count)\r\n" }
            connection.send(content: Data((headers + "\r\n").utf8), completion: .contentProcessed { error in
                if error != nil { connection.cancel(); return }
                if text.hasPrefix("HEAD ") { connection.cancel(); return }
                self.send(connection, offset: start, end: end, whole: start == 0 && end == self.audio.count - 1)
            })
        }
    }

    private func send(_ connection: NWConnection, offset: Int, end: Int, whole: Bool) {
        let next = min(offset + 16384, end + 1)
        connection.send(content: audio.subdata(in: offset..<next), completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else { connection.cancel(); return }
            if next > end {
                if whole { self.lock.lock(); self.complete = true; self.lock.unlock() }
                connection.cancel()
            } else {
                self.queue.asyncAfter(deadline: .now() + 0.25) { self.send(connection, offset: next, end: end, whole: whole) }
            }
        })
    }
}

private final class LaneUITestURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var saved: [String: [String]] = [:]
    private static var privacy = LanePrivacySettings()
    private static var notificationRead = false
    private static var invitationAccepted = false
    private static var invitationFailedOnce = false
    private static var profileName = "Lane fixture"
    private static var profileFailedOnce = false

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "lane-ui.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        do {
            let path = url.path
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let data: Data
            var contentType = "application/json"
            var statusCode = 200
            Self.lock.lock()
            defer { Self.lock.unlock() }
            if path == "/panorama" {
                contentType = "image/png"
                data = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 600)).image { context in
                    UIColor.systemOrange.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 2400, height: 600))
                }.pngData()!
            } else if path == "/platforms/artist" {
                data = try JSONEncoder().encode(LaneUITestFixtures.artist)
            } else if path == "/platforms/album" {
                data = try JSONEncoder().encode(LaneUITestFixtures.album)
            } else if path == "/user/tracks" {
                var body = request.httpBody ?? Data()
                if body.isEmpty, let stream = request.httpBodyStream {
                    stream.open()
                    defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }
                        body.append(buffer, count: count)
                    }
                }
                let object = try JSONSerialization.jsonObject(with: body)
                let ids = (object as? [String]) ?? (object as? [String: Any])?["trackIds"] as? [String] ?? []
                data = try JSONSerialization.data(withJSONObject: ids.map { id in
                    ["songId": id.replacingOccurrences(of: "source-", with: "lane-"), "title": "Fixture track \(id.split(separator: "-").last!)",
                     "artistsDisplayedName": "shadowraze", "platform": "spotify"]
                })
            } else if path == "/user/playlist/add-tracks" {
                var body = request.httpBody ?? Data()
                if body.isEmpty, let stream = request.httpBodyStream {
                    stream.open()
                    defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }
                        body.append(buffer, count: count)
                    }
                }
                let ids = try JSONSerialization.jsonObject(with: body) as? [String] ?? []
                let id = query.first { $0.name == "playlistId" }?.value ?? ""
                Self.saved[id] = LaneTrackBatching.unique((Self.saved[id] ?? []) + ids)
                data = Data(#"{"ok":true}"#.utf8)
            } else if path == "/user/playlists" {
                data = try JSONSerialization.data(withJSONObject: [["playlistId": "lane_likes", "playlistTracksIds": Self.saved["lane_likes"] ?? []]])
            } else if path.hasPrefix("/playlist/") {
                let parts = path.split(separator: "/")
                let id = String(parts[1])
                if parts.last == "tracks" {
                    data = try JSONSerialization.data(withJSONObject: ["items": (Self.saved[id] ?? []).map { ["songId": $0, "title": "Fixture track"] }, "totalItems": Self.saved[id]?.count ?? 0, "page": 1, "pageSize": 100, "totalPages": 1])
                } else {
                    data = try JSONSerialization.data(withJSONObject: ["playlistId": id, "playlistTracksIds": Self.saved[id] ?? []])
                }
            } else if path == "/account" {
                let privacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.privacy))
                data = try JSONSerialization.data(withJSONObject: ["laneId": "fixture-user", "displayedName": Self.profileName, "userPlaylists": ["lane_likes"], "privacySettings": privacy])
            } else if path == "/user/edit" {
                if !Self.profileFailedOnce { Self.profileFailedOnce = true; statusCode = 503 }
                else {
                    let value = try JSONSerialization.jsonObject(with: readBody()) as? [String: Any]
                    Self.profileName = value?["name"] as? String ?? ""
                }
                data = Data((statusCode == 200 ? #"{"ok":true}"# : #"{"message":"Retry profile"}"#).utf8)
            } else if path == "/user/settings/privacy" {
                Self.privacy = try JSONDecoder().decode(LanePrivacySettings.self, from: readBody())
                data = Data(#"{"ok":true}"#.utf8)
            } else if path == "/notifications" {
                let items: [[String: Any]] = Self.invitationAccepted ? [] : [["id": "fixture-invite", "type": "PLAYLIST_INVITATION", "invitationId": "invite-1", "playlistId": "shared-1", "playlistName": "Road Trip", "read": Self.notificationRead, "actorInfo": ["laneId": "friend", "displayedName": "Friend"]]]
                data = try JSONSerialization.data(withJSONObject: ["items": items, "totalPages": 1])
            } else if path == "/notifications/unread-count" {
                data = try JSONSerialization.data(withJSONObject: ["unreadCount": Self.notificationRead ? 0 : 1])
            } else if path == "/notifications/read-all" || path == "/notifications/fixture-invite/read" {
                Self.notificationRead = true
                data = Data(#"{"ok":true}"#.utf8)
            } else if path == "/playlist/invite/respond" {
                if !Self.invitationFailedOnce { Self.invitationFailedOnce = true; statusCode = 503 }
                else { Self.invitationAccepted = true }
                data = Data((statusCode == 200 ? #"{"ok":true}"# : #"{"message":"Retry invitation"}"#).utf8)
            } else if path == "/track/stream" || path == "/track/download" {
                guard let url = LaneUITestAudioServer.shared.url else { throw URLError(.cannotConnectToHost) }
                data = try JSONSerialization.data(withJSONObject: ["url": url])
            } else if path == "/track/stats" {
                data = Data(#"{"likesCount":27,"commentsCount":4}"#.utf8)
            } else {
                data = Data("[]".utf8)
            }
            let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func readBody() -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
#endif
