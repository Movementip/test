import SwiftUI
import UIKit

@main
struct LaneIOSPrototypeApp: App {
    @StateObject private var session: LaneSession

    init() {
        let value = LaneSession()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--lane-ui-test") {
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
    @State private var result = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                NavigationLink("Recommended artist") { APKArtistDetailScreen(seed: LaneUITestFixtures.artist) }
                NavigationLink("Recommended album") { APKAlbumDetailScreen(seed: LaneUITestFixtures.album) }
                Button("Open player") { showPlayer = true }
                Button("Run session checks") { Task { await checkSession() } }
                Text(result).accessibilityIdentifier("session.result")
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showPlayer) { APKFullPlayerView().environmentObject(session) }
        .preferredColorScheme(.dark)
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
}

private final class LaneUITestURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var saved: [String: [String]] = [:]

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
                data = Data(#"{"laneId":"fixture-user","userPlaylists":["lane_likes"]}"#.utf8)
            } else if path == "/track/stats" {
                data = Data(#"{"likesCount":27,"commentsCount":4}"#.utf8)
            } else {
                data = Data("[]".utf8)
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
#endif
