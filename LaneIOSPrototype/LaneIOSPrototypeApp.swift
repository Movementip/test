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
            // Tests start with no display preferences, then deliberately create
            // a fresh client in the same test to verify persistence.
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("lane.playlistOrder.") {
                UserDefaults.standard.removeObject(forKey: key)
            }
            _ = LaneUITestAudioServer.shared
            URLProtocol.registerClass(LaneUITestURLProtocol.self)
            value.backendMode = .custom
            value.baseURL = "https://lane-ui.test"
            value.token = "ui-fixture-token"
            value.serverArtists = [LaneUITestFixtures.artist]
            value.queue = [LaneUITestFixtures.track]
            value.currentIndex = 0
            value.currentTrack = LaneUITestFixtures.track
            if ProcessInfo.processInfo.arguments.contains("--lane-import-fixture") {
                LaneUITestURLProtocol.prepareImportFixture()
                value.serverPlaylists = [LanePlaylist(playlistId: "lane_likes", playlistName: "Favorite tracks",
                    playlistTracksIds: ["lane-1", "lane-2", "lane-3", "lane-4"])]
            }
            if ProcessInfo.processInfo.arguments.contains("--lane-queue-fixture") || ProcessInfo.processInfo.arguments.contains("--lane-rate-fixture") {
                LaneUITestURLProtocol.prepareLikedFixture(rateLimited: ProcessInfo.processInfo.arguments.contains("--lane-rate-fixture"))
                value.queue = [LaneUITestFixtures.track, TrackCandidate(id: "lane-2", title: "Old playlist second", subtitle: "Lane", trackID: "lane-2")]
            }
        }
        #endif
        _session = StateObject(wrappedValue: value)
    }

    var body: some Scene {
        WindowGroup {
            Group {
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
            .modifier(LaneIncomingSharePresenter())
            .environmentObject(session)
            .onOpenURL { url in session.receiveShareURL(url) }
        }
    }
}

// Attached to the app root so links are handled both before and after sign-in.
struct LaneIncomingSharePresenter: ViewModifier {
    @EnvironmentObject private var session: LaneSession
    func body(content: Content) -> some View {
        content.sheet(item: $session.incomingShare) { share in
            LaneIncomingShareScreen(share: share).environmentObject(session)
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
    static let memorialArtist = LaneArtist(name: "Memorial artist", id: "memorial-artist", platform: "lane",
        headerUrl: "https://lane-ui.test/panorama", topTracks: ["source-1", "source-2"],
        custom: LaneArtistCustoms(badges: ["rip"], ripInfo: LaneArtistRIPInfo(startDate: 631152000000,
            endDate: 1700000000000, additionalText: "Remembered through music")))
}

private struct LaneUITestRoot: View {
    @EnvironmentObject private var session: LaneSession
    @State private var showPlayer = false
    @State private var showEdit = false
    @State private var showFullApp = false
    @State private var showImport = false
    @State private var result = ""
    @State private var gestureReport = "Waiting for edge swipe"

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if ProcessInfo.processInfo.arguments.contains("--lane-community-fixture") {
                    NavigationLink("Your badges") { LaneBadgeSelectionScreen() }
                    NavigationLink("Memorial artist") { APKArtistDetailScreen(seed: LaneUITestFixtures.memorialArtist) }
                    Button("Check badge on fresh client") { Task { await checkFreshBadge() } }
                }
                NavigationLink("Recommended artist") { APKArtistDetailScreen(seed: LaneUITestFixtures.artist) }
                NavigationLink("Recommended album") { APKAlbumDetailScreen(seed: LaneUITestFixtures.album) }
                NavigationLink("Privacy settings") { PrivacySettingsScreen() }
                NavigationLink("Notification center") { NotificationsScreen() }
                NavigationLink("Public profile") { LaneUserProfileScreen(laneID: "friend") }
                Button("Open player") { showPlayer = true }
                Button("Run session checks") { Task { await checkSession() } }
                Button("Run playback checks") { Task { await checkPlayback() } }
                Button("Run range transport checks") { Task { await checkPlayback(direct: true) } }
                Button("Run effects checks") { Task { await checkEffects() } }
                Button("Run recovery checks") { Task { await checkPlaybackRecovery() } }
                if ProcessInfo.processInfo.arguments.contains("--lane-background-fixture") {
                    Button("Run background checks") { Task { await checkBackgroundPlayback() } }
                }
                NavigationLink("Track comments") { APKCommentsScreen(track: LaneUITestFixtures.track) }
                Button("Edit profile") { showEdit = true }
                Button("Open full app") { showFullApp = true }
                if ProcessInfo.processInfo.arguments.contains("--lane-import-fixture") {
                    Button("Open import fixture") { showImport = true }
                    Button("Check imported order") { Task { await checkImportedOrder() } }
                    Button("Check imported oldest order") { Task { await checkImportedOrder(oldest: true) } }
                }
                Button("Open shared album") { session.receiveShareURL(URL(string: "lane://share/fixture-album-share")!) }
                Text(result).accessibilityIdentifier("session.result")
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showPlayer) { APKFullPlayerView().environmentObject(session) }
        .sheet(isPresented: $showEdit) { EditProfileSheet().environmentObject(session) }
        .fullScreenCover(isPresented: $showFullApp) { ContentView().environmentObject(session) }
        .fullScreenCover(isPresented: $showImport) {
            ImportTracksScreen(fixture: LanePlaylist(playlistName: "Already saved source", playlistTracksIds: (1...4).map { "source-\($0)" }),
                source: (1...4).reversed().enumerated().map { offset, id in
                    YandexImportTrack(yandexID: "yandex-\(id)", originalIndex: offset,
                        title: "Fixture track \(id)", artists: ["shadowraze"], coverURL: nil)
                })
                .environmentObject(session)
                .overlay(alignment: .bottom) {
                    Button("Leave import fixture") { showImport = false }
                        .padding(12).background(Color.black)
                }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .bottom) {
            Text(gestureReport).font(.system(size: 9)).accessibilityIdentifier("gesture.report")
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LaneEdgeSwipeUIProbe"))) { message in
            if let value = message.object as? String { gestureReport = value }
        }
    }

    private func checkFreshBadge() async {
        do {
            let fresh = LaneSession()
            fresh.backendMode = .custom; fresh.baseURL = "https://lane-ui.test"; fresh.token = "ui-fixture-token"
            let profile = try await fresh.fetchOwnBadgeProfile()
            guard profile.equippedBadgeId == "legend", profile.equippedBadge?.definition.name == "Legend" else {
                throw LaneAPIError.decoding("Badge did not survive a new client")
            }
            LaneUITestURLProtocol.prepareBadgeReadRace()
            let staleRead = Task { try await session.fetchOwnBadgeProfile() }
            for _ in 0..<40 {
                if LaneUITestURLProtocol.badgeResolutionStarted { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            guard LaneUITestURLProtocol.badgeResolutionStarted else { throw LaneAPIError.decoding("Badge race did not start") }
            _ = try await session.equipBadgeConfirmed("legend")
            do { _ = try await staleRead.value; throw LaneAPIError.decoding("An old profile read was not rejected") }
            catch is CancellationError { }
            guard session.publicProfile?.equippedBadgeId == "legend" else {
                throw LaneAPIError.decoding("Delayed profile removed a confirmed badge")
            }
            result = "Server badge restored on fresh client"
        } catch { result = "Badge check failed: " + error.localizedDescription }
    }

    private func checkSession() async {
        do {
            let originals = Bundle.main.urls(forResourcesWithExtension: "png", subdirectory: nil) ?? []
            let undecodable = originals.filter { UIImage(contentsOfFile: $0.path) == nil }.map(\.lastPathComponent)
            guard originals.count >= 38, undecodable.isEmpty,
                  Bundle.main.url(forResource: "amen", withExtension: "gif") != nil else {
                throw LaneAPIError.decoding("APK artwork check: \(originals.count) PNGs; cannot decode \(undecodable.joined(separator: ", "))")
            }
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
            _ = try await session.importTracks(["source-2", "source-3", "source-4"], into: "lane_likes",
                                               resolvingSourceIDs: true, sort: .oldest)
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
            guard fresh.likedTracks.compactMap(\.trackID) == ["lane-4", "lane-3", "lane-2", "lane-1"] else {
                throw LaneAPIError.decoding("Liked songs ignored the saved import order after a fresh installation")
            }
            try await fresh.clearPlaylistTracks(LanePlaylist(playlistId: "lane_likes"))
            await fresh.refreshAfterLogin()
            guard fresh.likedTracks.isEmpty, fresh.favorites.isEmpty else {
                throw LaneAPIError.decoding("Cleared server likes reappeared after refresh")
            }

            // Hold an older library read inside metadata resolution. Commit a
            // new like while it is suspended, then deliver the old response.
            // A pending-state-only fix loses the row after confirmation here.
            LaneUITestURLProtocol.prepareFavoriteReadRace()
            defer { LaneUITestURLProtocol.finishFavoriteReadRace() }
            UserDefaults.standard.removeObject(forKey: "lane.cachedTrackMetadata")
            let racing = LaneSession()
            racing.backendMode = .custom
            racing.baseURL = "https://lane-ui.test"
            racing.token = "ui-fixture-race"
            let refresh = Task { await racing.refreshAfterLogin() }
            for _ in 0..<50 {
                if LaneUITestURLProtocol.favoriteResolutionStarted { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard LaneUITestURLProtocol.favoriteResolutionStarted else {
                throw LaneAPIError.decoding("Favorite race did not reach delayed metadata resolution")
            }
            let added = TrackCandidate(id: "lane-99", title: "New like", subtitle: "Lane fixture", trackID: "lane-99", platform: "spotify")
            racing.toggleFavorite(added)
            for _ in 0..<50 {
                if !racing.isFavoriteSyncPending(added) { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard !racing.isFavoriteSyncPending(added) else { throw LaneAPIError.decoding("Concurrent like was not confirmed") }
            await refresh.value
            guard racing.isFavorite(added), racing.likedTracks.contains(where: { $0.trackID == "lane-99" }) else {
                throw LaneAPIError.decoding("A delayed library read erased a newer confirmed like")
            }
            LaneUITestURLProtocol.finishFavoriteReadRace()

            // A delayed account response must not sign a cleared account back
            // in, nor expose its privacy/profile state after logout.
            LaneUITestURLProtocol.prepareAccountReadRace()
            let privacyRead = Task { try await racing.loadPrivacySettings() }
            for _ in 0..<50 {
                if LaneUITestURLProtocol.accountResolutionStarted { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard LaneUITestURLProtocol.accountResolutionStarted else { throw LaneAPIError.decoding("Account race did not start") }
            racing.clearAccount()
            do {
                _ = try await privacyRead.value
                throw LaneAPIError.decoding("Old account response was accepted after logout")
            } catch is CancellationError { }
            guard racing.account == nil, racing.publicProfile == nil else { throw LaneAPIError.decoding("Old profile reappeared after logout") }
            result = "Session checks passed"
        } catch {
            result = "Session checks failed: \(error.localizedDescription)"
        }
    }

    private func checkImportedOrder(oldest: Bool = false) async {
        do {
            for _ in 0..<100 where session.importingPlaylistIDs.contains("lane_likes") {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            let expected = oldest ? ["lane-1", "lane-2", "lane-3", "lane-4"] : ["lane-4", "lane-3", "lane-2", "lane-1"]
            guard session.likedTracks.compactMap(\.trackID) == expected else {
                throw LaneAPIError.decoding("Visible liked tracks did not adopt confirmed source order")
            }
            LaneUITestURLProtocol.simulateStaleImportOrderReads()
            await session.refreshAfterLogin()
            guard session.likedTracks.compactMap(\.trackID) == expected else {
                throw LaneAPIError.decoding("Library refresh reset the selected import order")
            }
            let fresh = LaneSession()
            fresh.backendMode = .custom; fresh.baseURL = "https://lane-ui.test"; fresh.token = "ui-fixture-token"
            await fresh.refreshAfterLogin()
            guard fresh.likedTracks.compactMap(\.trackID) == expected else {
                throw LaneAPIError.decoding("New client did not read the saved source order")
            }
            fresh.token = "another-ui-fixture-account"
            guard fresh.playlistImportOrderTitle("lane_likes") == nil else {
                throw LaneAPIError.decoding("Import order leaked into another account")
            }
            result = "Background import order passed"
        } catch { result = "Background import order failed: \(error.localizedDescription)" }
    }

    private func checkEffects() async {
        do {
            _ = try await session.loadPrivacySettings()
            try session.removeDownload(LaneUITestFixtures.track)
            session.requestStream(for: LaneUITestFixtures.track)
            for _ in 0..<150 {
                if session.isPlaying && session.playbackPosition > 0.1 { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard session.isPlaying else { throw LaneAPIError.decoding("Original audio did not start") }
            session.pause()
            session.seek(to: 3)
            try await Task.sleep(nanoseconds: 400_000_000)
            await session.selectTrackEffect(.speedUp)
            guard session.currentTrackEffect == .original, !session.trackEffectError.isEmpty else {
                throw LaneAPIError.decoding("Failed effect replaced the original audio")
            }
            for effect in [LaneTrackEffect.speedUp, .slowed, .original] {
                let target = effect.position(from: session.playbackPosition, effect: session.currentTrackEffect)
                await session.selectTrackEffect(effect)
                for _ in 0..<150 {
                    if !session.isBuffering && abs(session.playbackPosition - target) < 0.35 { break }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                guard session.currentTrackEffect == effect, session.trackEffectError.isEmpty,
                      !session.isBuffering, !session.isPlaying,
                      abs(session.playbackPosition - target) < 0.35 else {
                    throw LaneAPIError.decoding("Effect lost position or pause state: \(effect.rawValue), position \(session.playbackPosition), target \(target), \(session.trackEffectError)")
                }
            }
            session.resume()
            for _ in 0..<50 {
                if session.isPlaying { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard session.isPlaying else { throw LaneAPIError.decoding("Original audio did not resume") }
            session.stop()
            result = "Effects checks passed"
        } catch { result = "Effects checks failed: \(error.localizedDescription)" }
    }

    private func checkPlaybackRecovery() async {
        do {
            try session.removeDownload(LaneUITestFixtures.track)
            func waitForAudio(_ id: String) async throws {
                for _ in 0..<150 {
                    if session.currentTrack?.trackID == id, session.isPlaying, session.playbackPosition > 0.1 { return }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                throw LaneAPIError.decoding("Audio did not recover for \(id): \(session.playerError)")
            }
            func waitForFailure() async throws {
                for _ in 0..<80 {
                    if session.playerError.contains("STREAM-500"), !session.isBuffering, !session.isPlaying { return }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                throw LaneAPIError.decoding("500 did not terminate loading cleanly")
            }
            let failed = TrackCandidate(id: "stream-failure", title: "Transient failure", subtitle: "Lane fixture", trackID: "stream-failure", refID: "lane_likes", platform: "spotify")
            let next = TrackCandidate(id: "lane-2", title: "Next song", subtitle: "Lane fixture", trackID: "lane-2", platform: "spotify")
            session.requestStream(for: LaneUITestFixtures.track)
            try await waitForAudio("lane-1")
            session.queue = [failed, next]
            session.requestStream(for: failed)
            try await waitForFailure()
            session.next()
            try await waitForAudio("lane-2")
            guard session.playerError.isEmpty else { throw LaneAPIError.decoding("Previous failure poisoned next track") }
            session.requestStream(for: failed)
            try await waitForFailure()
            LaneUITestURLProtocol.allowFailedStreamRetry()
            session.resume()
            try await waitForAudio("stream-failure")
            let late = TrackCandidate(id: "late-failure", title: "Delayed failure", subtitle: "Lane fixture", trackID: "late-failure", platform: "spotify")
            session.requestStream(for: late)
            try await Task.sleep(nanoseconds: 150_000_000)
            session.requestStream(for: next)
            try await waitForAudio("lane-2")
            try await Task.sleep(nanoseconds: 2_500_000_000)
            guard session.isPlaying, session.currentTrack?.trackID == "lane-2", session.playerError.isEmpty else {
                throw LaneAPIError.decoding("Cancelled old request interrupted the new song")
            }
            // A plain TCP fixture intentionally never completes TLS. Exercise
            // the real no-VPN NWConnection cancellation, not a mocked result.
            guard let httpURL = LaneUITestAudioServer.shared.url,
                  let stalledURL = URL(string: httpURL.replacingOccurrences(of: "http://", with: "https://")) else { throw URLError(.badURL) }
            let stalled = Task { try await AndroidNetworkTransport.data(for: URLRequest(url: stalledURL), timeout: 12) }
            try await Task.sleep(nanoseconds: 200_000_000)
            let cancelledAt = Date()
            stalled.cancel()
            do { _ = try await stalled.value; throw LaneAPIError.decoding("Cancelled TLS unexpectedly succeeded") }
            catch is CancellationError { }
            guard Date().timeIntervalSince(cancelledAt) < 2 else {
                throw LaneAPIError.decoding("Cancelled TLS held the playback task until its timeout")
            }
            let dnsStarted = Date()
            let dnsHost = "lane-dns-\(UUID().uuidString).test"
            let addresses = try await AndroidNetworkTransport.debugResolvedAddresses(host: dnsHost) { request in
                // The other providers are unreachable; the first supplies a
                // duplicate, a second IPv4, and a non-address DNS record.
                try await Task.sleep(nanoseconds: request.url?.host == "1.1.1.1" ? 100_000_000 : 4_000_000_000)
                let data = Data(#"{"Answer":[{"type":1,"data":"192.0.2.1"},{"type":1,"data":"192.0.2.1"},{"type":1,"data":"192.0.2.2"},{"type":5,"data":"alias.test"}]}"#.utf8)
                return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            guard addresses == ["192.0.2.1", "192.0.2.2"], Date().timeIntervalSince(dnsStarted) < 1 else {
                throw LaneAPIError.decoding("Fast DNS waited for unreachable alternatives")
            }
            let cached = try await AndroidNetworkTransport.debugResolvedAddresses(host: dnsHost) { _ in throw URLError(.cannotFindHost) }
            guard cached == addresses else { throw LaneAPIError.decoding("Fast DNS did not cache usable addresses") }
            session.stop()
            result = "Recovery checks passed"
        } catch { result = "Recovery checks failed: \(error.localizedDescription)" }
    }

    private func checkBackgroundPlayback() async {
        do {
            session.debugUseProgressiveTransport = true
            let first = TrackCandidate(id: "background-first", title: "Short first song", subtitle: "Background test", trackID: "background-first")
            let next = TrackCandidate(id: "background-next", title: "Next song in background", subtitle: "Background test", trackID: "background-next")
            session.startPlayback(first, in: [first, next])
            guard session.debugHasPlaybackBackgroundTask else { throw LaneAPIError.decoding("Missing transition execution window") }
            result = "Background check ready"
            var heardFirstInBackground = false
            var heardNextInBackground = false
            let started = Date()
            for _ in 0..<240 {
                if session.isPlaying, session.playbackPosition > 0.1,
                   UIApplication.shared.applicationState == .background {
                    if session.currentTrack?.trackID == first.trackID { heardFirstInBackground = true }
                    if session.currentTrack?.trackID == next.trackID { heardNextInBackground = true }
                }
                if heardFirstInBackground && heardNextInBackground { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard heardFirstInBackground, heardNextInBackground else {
                throw LaneAPIError.decoding("Real audio did not start/advance while backgrounded: \(session.output)")
            }
            guard LaneUITestURLProtocol.streamCount(for: "background-next") == 1 else {
                throw LaneAPIError.decoding("Next did not reuse its in-flight preparation")
            }
            guard !session.debugHasPlaybackBackgroundTask else { throw LaneAPIError.decoding("Playing audio leaked background task") }
            print("LANE_BACKGROUND_AUDIO first-and-next audible while backgrounded; next stream calls=1; elapsed=\(Date().timeIntervalSince(started))")
            session.pause()
            guard !session.debugHasPlaybackBackgroundTask else { throw LaneAPIError.decoding("Pause leaked background task") }
            session.stop()
            result = "Background checks passed"
        } catch {
            session.stop()
            result = "Background checks failed: \(error.localizedDescription)"
        }
    }

    private func checkPlayback(direct: Bool = false) async {
        do {
            session.debugUseProgressiveTransport = direct
            try session.removeDownload(LaneUITestFixtures.track)
            let started = Date()
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
            guard Date().timeIntervalSince(started) < 8 else { throw LaneAPIError.decoding("Loopback audio startup exceeded 8 seconds") }
            print("LANE_STREAM_START transport=\(direct ? "range" : "native") seconds=\(Date().timeIntervalSince(started)); completeFile=false")
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
            result = direct ? "Range transport checks passed" : "Playback checks passed"
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
    private var deliveredRanges: [Range<Int>] = []
    private let audio: Data
    private let shortAudio: Data
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
        var short = Data(data.prefix(44 + Int(sampleRate) * 2 * 3))
        func replaceWord(_ value: UInt32, at offset: Int) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { short.replaceSubrange(offset..<(offset + 4), with: $0) }
        }
        replaceWord(UInt32(short.count - 8), at: 4)
        replaceWord(UInt32(short.count - 44), at: 40)
        shortAudio = short
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
            let payload = text.contains("/short.wav ") ? self.shortAudio : self.audio
            var start = 0, end = payload.count - 1
            let range = text.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("range:") }
            if let range, let value = range.components(separatedBy: "bytes=").last {
                let fields = value.components(separatedBy: "-")
                start = Int(fields[0]) ?? 0
                if fields.count > 1, let upper = Int(fields[1]) { end = min(upper, end) }
            }
            guard start >= 0, start <= end, start < payload.count else { connection.cancel(); return }
            let length = end - start + 1
            var headers = "HTTP/1.1 \(range == nil ? "200 OK" : "206 Partial Content")\r\nContent-Type: audio/wav\r\nAccept-Ranges: bytes\r\nContent-Length: \(length)\r\nConnection: close\r\n"
            if range != nil { headers += "Content-Range: bytes \(start)-\(end)/\(payload.count)\r\n" }
            connection.send(content: Data((headers + "\r\n").utf8), completion: .contentProcessed { error in
                if error != nil { connection.cancel(); return }
                if text.hasPrefix("HEAD ") { connection.cancel(); return }
                self.send(connection, offset: start, end: end, payload: payload)
            })
        }
    }

    private func send(_ connection: NWConnection, offset: Int, end: Int, payload: Data) {
        let next = min(offset + 16384, end + 1)
        connection.send(content: payload.subdata(in: offset..<next), completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else { connection.cancel(); return }
            self.lock.lock()
            var merged: [Range<Int>] = []
            for interval in (self.deliveredRanges + [offset..<next]).sorted(by: { $0.lowerBound < $1.lowerBound }) {
                if let last = merged.last, last.upperBound >= interval.lowerBound {
                    merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, interval.upperBound)
                } else { merged.append(interval) }
            }
            self.deliveredRanges = merged
            self.complete = merged.reduce(0) { $0 + $1.count } >= self.audio.count
            self.lock.unlock()
            if next > end {
                connection.cancel()
            } else {
                self.queue.asyncAfter(deadline: .now() + 0.25) { self.send(connection, offset: next, end: end, payload: payload) }
            }
        })
    }
}

private final class LaneUITestURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var saved: [String: [String]] = ["fixture-playlist": ["lane-1", "lane-2"]]
    private static var rateLimitDeletion = false
    private static var deletionDeadline: Date?
    private static var importFixture = false
    private static var delayImportRead = false
    private static var staleImportOrderReads = false

    static func simulateStaleImportOrderReads() {
        lock.lock(); defer { lock.unlock() }
        staleImportOrderReads = true
    }

    static func prepareImportFixture() {
        lock.lock(); defer { lock.unlock() }
        saved["lane_likes"] = ["lane-1", "lane-2", "lane-3", "lane-4"]
        importFixture = true
        delayImportRead = false
        staleImportOrderReads = false
    }

    static func prepareLikedFixture(rateLimited: Bool) {
        lock.lock(); defer { lock.unlock() }
        saved["lane_likes"] = ["lane-3", "lane-4"]
        rateLimitDeletion = rateLimited
        deletionDeadline = nil
    }
    private static var privacy = LanePrivacySettings()
    private static var notificationRead = false
    private static var invitationAccepted = false
    private static var invitationFailedOnce = false
    private static var profileName = "Lane fixture"
    private static var profileFailedOnce = false
    private static var effectFailedOnce = false
    private static var followingFriend = false
    private static var equippedBadgeID: String?
    private static var badgeFailedOnce = false
    private static var badgeReadRace = false
    private static var badgeReadStarted = false
    static func prepareBadgeReadRace() {
        lock.lock(); defer { lock.unlock() }; badgeReadRace = true; badgeReadStarted = false
    }
    static var badgeResolutionStarted: Bool {
        lock.lock(); defer { lock.unlock() }; return badgeReadStarted
    }
    private static var candleFailedOnce = false
    private static var candleReadFailedOnce = false
    private static var placedCandle: [String: Any]?
    private static let badgeDefinition: [String: Any] = ["badgeId": "legend", "name": "Legend",
        "description": ["en": "An original Lane reward", "ru": "Оригинальная награда Lane", "uk": "Нагорода Lane"],
        "imageUrl": "https://lane-ui.test/panorama", "badgeColor": "#ff8284"]
    private static var followFailedOnce = false
    private static var favoriteReadRace = false
    private static var favoriteReadStarted = false
    private static var accountReadRace = false
    private static var accountReadStarted = false
    private static var failedStreamCanRetry = false
    private static var streamCounts: [String: Int] = [:]
    static func streamCount(for id: String) -> Int {
        lock.lock(); defer { lock.unlock() }; return streamCounts[id] ?? 0
    }
    private static var shareFailedOnce = false
    private var delayedDelivery: DispatchWorkItem?

    static func allowFailedStreamRetry() {
        lock.lock(); defer { lock.unlock() }; failedStreamCanRetry = true
    }

    static func prepareFavoriteReadRace() {
        lock.lock(); defer { lock.unlock() }
        saved["lane_likes"] = ["lane-1"]
        favoriteReadRace = true
        favoriteReadStarted = false
    }

    static func finishFavoriteReadRace() {
        lock.lock(); defer { lock.unlock() }
        favoriteReadRace = false
    }

    static var favoriteResolutionStarted: Bool {
        lock.lock(); defer { lock.unlock() }; return favoriteReadStarted
    }

    static func prepareAccountReadRace() {
        lock.lock(); defer { lock.unlock() }
        accountReadRace = true
        accountReadStarted = false
    }

    static var accountResolutionStarted: Bool {
        lock.lock(); defer { lock.unlock() }; return accountReadStarted
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "lane-ui.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() { delayedDelivery?.cancel() }

    override func startLoading() {
        guard let url = request.url else { return }
        do {
            let path = url.path
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let data: Data
            var contentType = "application/json"
            var statusCode = 200
            var delayResponse = false
            var responseDelay: TimeInterval = 2
            let isRaceClient = request.value(forHTTPHeaderField: "Authorization") == "Bearer ui-fixture-race"
            Self.lock.lock()
            defer { Self.lock.unlock() }
            if path == "/panorama" {
                contentType = "image/png"
                data = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 600)).image { context in
                    UIColor.systemOrange.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 2400, height: 600))
                }.pngData()!
            } else if path == "/v1/share/get" {
                guard request.value(forHTTPHeaderField: "Authorization") == nil,
                      query.first(where: { $0.name == "id" })?.value == "fixture-album-share" else { throw URLError(.badURL) }
                if !Self.shareFailedOnce {
                    Self.shareFailedOnce = true; statusCode = 503
                    data = Data(#"{"message":"Retry shared album"}"#.utf8)
                } else {
                    data = try JSONSerialization.data(withJSONObject: ["shareContentType": "album", "shareItemId": "fixture-album", "albumName": "bastards", "artistName": "shadowraze", "shareCoverUrl": "https://lane-ui.test/panorama", "userName": "Friend profile", "userId": "friend", "userAvatarUrl": ""])
                }
            } else if path == "/platforms/artist" {
                let memorial = query.first { $0.name == "artistId" }?.value == "memorial-artist"
                data = try JSONEncoder().encode(memorial ? LaneUITestFixtures.memorialArtist : LaneUITestFixtures.artist)
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
                if Self.importFixture, ids == ["source-1", "source-2", "source-3", "source-4"] {
                    Self.delayImportRead = true
                }
                if isRaceClient, Self.favoriteReadRace, !Self.favoriteReadStarted, ids == ["lane-1"] {
                    Self.favoriteReadStarted = true
                    delayResponse = true
                }
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
                data = try JSONSerialization.data(withJSONObject: [
                    ["playlistId": "lane_likes", "playlistTracksIds": Self.saved["lane_likes"] ?? []],
                    ["playlistId": "fixture-playlist", "playlistName": "Fixture playlist", "playlistTracksIds": Self.saved["fixture-playlist"] ?? [], "tracksCount": 0, "creatorLid": "fixture-user"]
                ])
            } else if path == "/playlist/reorder" {
                let value = try JSONSerialization.jsonObject(with: readBody()) as? [String: Any]
                let id = value?["playlistId"] as? String ?? ""
                let ids = value?["newOrder"] as? [String] ?? []
                guard Set(ids) == Set(Self.saved[id] ?? []) else { throw URLError(.badServerResponse) }
                Self.saved[id] = ids
                data = Data(#"{"ok":true}"#.utf8)
            } else if path == "/user/playlist/remove-track" {
                let id = query.first { $0.name == "playlistId" }?.value ?? ""
                let track = query.first { $0.name == "trackId" }?.value ?? ""
                if Self.rateLimitDeletion, id == "lane_likes", Self.deletionDeadline == nil {
                    Self.deletionDeadline = Date().addingTimeInterval(60)
                    statusCode = 429
                    data = Data(#"{"code":"RATE_LIMITED","message":"Retry after 3 seconds."}"#.utf8)
                } else if let deadline = Self.deletionDeadline, Date() < deadline {
                    statusCode = 429
                    data = Data(#"{"code":"EARLY_RETRY","message":"Deletion cooldown has not elapsed."}"#.utf8)
                } else {
                    Self.saved[id]?.removeAll { $0 == track }
                    data = Data(#"{"ok":true}"#.utf8)
                }
            } else if path.hasPrefix("/playlist/"), path != "/playlist/invite/respond" {
                let parts = path.split(separator: "/")
                let id = String(parts[1])
                if parts.last == "tracks" {
                    let ids = isRaceClient && Self.favoriteReadRace && id == "lane_likes" ? [] : (Self.saved[id] ?? [])
                    data = try JSONSerialization.data(withJSONObject: ["items": ids.reversed().map { ["songId": $0, "title": "Fixture track \($0.split(separator: "-").last!)", "platform": "spotify"] }, "totalItems": ids.count, "page": 1, "pageSize": 100, "totalPages": 1])
                } else {
                    if Self.delayImportRead, id == "lane_likes" {
                        Self.delayImportRead = false
                        delayResponse = true
                        responseDelay = 6
                    }
                    var ids = Self.saved[id] ?? []
                    if Self.staleImportOrderReads, id == "lane_likes" { ids = Array(ids.reversed()) }
                    data = try JSONSerialization.data(withJSONObject: ["playlistId": id, "playlistTracksIds": ids, "tracksCount": ids.count])
                }
            } else if path == "/account" {
                if isRaceClient, Self.accountReadRace {
                    Self.accountReadRace = false
                    Self.accountReadStarted = true
                    delayResponse = true
                }
                let privacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.privacy))
                data = try JSONSerialization.data(withJSONObject: ["laneId": "fixture-user", "displayedName": Self.profileName, "userPlaylists": ["lane_likes"], "privacySettings": privacy,
                                                                 "premiumExpiresIn": Int64(Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000)])
            } else if path == "/user/edit" {
                if !Self.profileFailedOnce { Self.profileFailedOnce = true; statusCode = 503 }
                else {
                    let value = try JSONSerialization.jsonObject(with: readBody()) as? [String: Any]
                    Self.profileName = value?["name"] as? String ?? ""
                }
                data = Data((statusCode == 200 ? #"{"ok":true}"# : #"{"message":"Retry profile"}"#).utf8)
            } else if path == "/user-info" {
                let id = query.first { $0.name == "laneId" }?.value ?? "friend"
                let equipped: Any
                if id == "fixture-user", Self.badgeReadRace {
                    Self.badgeReadRace = false; Self.badgeReadStarted = true; delayResponse = true
                    equipped = NSNull()
                } else if id == "fixture-user" { equipped = Self.equippedBadgeID as Any? ?? NSNull() }
                else { equipped = "legend" }
                data = try JSONSerialization.data(withJSONObject: ["laneId": id, "displayedName": id == "friend" ? "Friend profile" : "Second friend", "userName": id,
                    "headerUrl": "https://lane-ui.test/panorama", "followersCount": Self.followingFriend ? 6 : 5, "followingCount": 2,
                    "isFollowing": id == "friend" && Self.followingFriend,
                    "privacySettings": ["showPlaylists": id != "second", "showFollowers": id != "second", "showFollowing": id != "second"],
                    "equippedBadgeId": equipped,
                    "badges": ProcessInfo.processInfo.arguments.contains("--lane-community-fixture") ? [["definition": Self.badgeDefinition, "earnedAt": Int64(1700000000000)]] : [],
                    "publicPlaylists": [["playlistId": "fixture-playlist", "playlistName": "Fixture playlist", "playlistTracksIds": ["lane-1", "lane-2"]]]])
            } else if path == "/user/badge/equip" {
                let json = try JSONSerialization.jsonObject(with: readBody()) as? [String: Any]
                guard request.httpMethod == "POST", let json, Set(json.keys) == ["badgeId"],
                      json["badgeId"] is NSNull || json["badgeId"] as? String == "legend" else { throw URLError(.badURL) }
                if !Self.badgeFailedOnce { Self.badgeFailedOnce = true; statusCode = 503 }
                else { Self.equippedBadgeID = json["badgeId"] as? String }
                data = Data((statusCode == 200 ? #"{"ok":true}"# : #"{"message":"Retry badge selection"}"#).utf8)
            } else if path == "/platforms/artist/rip/candles-count" {
                guard query.first(where: { $0.name == "artistId" })?.value == "memorial-artist" else { throw URLError(.badURL) }
                data = Data((Self.placedCandle == nil ? "2" : "3").utf8)
            } else if path == "/artist/memorial-artist/candles" {
                let page = Int(query.first { $0.name == "page" }?.value ?? "0") ?? 0
                guard page > 0, query.first(where: { $0.name == "pageSize" })?.value == "20" else { throw URLError(.badURL) }
                if !Self.candleReadFailedOnce {
                    Self.candleReadFailedOnce = true; statusCode = 503
                    data = Data(#"{"message":"Retry candle list"}"#.utf8)
                } else {
                    let value: [String: Any] = ["id": "candle-\(page)", "text": page == 1 ? "First memory" : "Second memory",
                        "timestamp": Int64(1700000000000), "author": ["laneId": "friend", "displayedName": "Friend profile"]]
                    let items = page == 1 ? [Self.placedCandle, value].compactMap { $0 } : [value]
                    data = try JSONSerialization.data(withJSONObject: ["items": items, "page": page, "pageSize": 20, "totalPages": 2,
                        "totalItems": Self.placedCandle == nil ? 2 : 3])
                }
            } else if path == "/artist/memorial-artist/candle" {
                let json = try JSONSerialization.jsonObject(with: readBody()) as? [String: Any]
                guard request.httpMethod == "POST", let text = json?["text"] as? String,
                      Set(json!.keys) == ["text"], LaneCandleText.isValid(text) else { throw URLError(.badURL) }
                if !Self.candleFailedOnce {
                    Self.candleFailedOnce = true; statusCode = 503
                    data = Data(#"{"message":"Retry candle message"}"#.utf8)
                } else {
                    guard Self.placedCandle == nil else { throw URLError(.badURL) }
                    let value: [String: Any] = ["id": "candle-own", "text": text, "timestamp": Int64(1700000000000),
                        "author": ["laneId": "fixture-user", "displayedName": "Lane fixture"]]
                    Self.placedCandle = value
                    data = try JSONSerialization.data(withJSONObject: value)
                }
            } else if path == "/user/follow/friend" {
                if !Self.followFailedOnce { Self.followFailedOnce = true; statusCode = 503 }
                else { Self.followingFriend = true }
                data = Data((statusCode == 200 ? #"{"ok":true}"# : #"{"message":"Retry follow"}"#).utf8)
            } else if path == "/user/unfollow/friend" {
                Self.followingFriend = false; data = Data(#"{"ok":true}"#.utf8)
            } else if path == "/user/followers" || path == "/user/following" {
                let page = Int(query.first { $0.name == "page" }?.value ?? "0") ?? 0
                let users: [[String: Any]] = [["laneId": page == 0 ? "friend" : "second", "displayedName": page == 0 ? "Friend profile" : "Second friend", "userName": page == 0 ? "friend" : "second"]]
                data = try JSONSerialization.data(withJSONObject: ["items": users, "page": page, "pageSize": 30, "totalPages": 2])
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
            } else if path == "/track/effect" {
                let effect = query.first { $0.name == "effect" }?.value
                guard query.first(where: { $0.name == "trackId" })?.value == "lane-1",
                      effect == "speedup" || effect == "slowed_reverb" else { throw URLError(.badURL) }
                if !Self.effectFailedOnce {
                    Self.effectFailedOnce = true; statusCode = 503
                    data = Data(#"{"message":"Retry effect"}"#.utf8)
                } else {
                    guard let url = LaneUITestAudioServer.shared.url else { throw URLError(.cannotConnectToHost) }
                    data = try JSONSerialization.data(withJSONObject: ["url": url, "trackId": "lane-1"])
                }
            } else if path == "/track/stream" || path == "/track/download" {
                let id = query.first { $0.name == "trackId" }?.value ?? ""
                if path == "/track/stream" { Self.streamCounts[id, default: 0] += 1 }
                if id == "stream-failure" && !Self.failedStreamCanRetry || id == "late-failure" {
                    statusCode = 500; delayResponse = id == "late-failure"
                    data = Data(#"{"message":"Transient stream failure"}"#.utf8)
                } else {
                    guard let url = LaneUITestAudioServer.shared.url else { throw URLError(.cannotConnectToHost) }
                    let selectedURL = id == "background-first" ? url.replacingOccurrences(of: "/audio.wav", with: "/short.wav") : url
                    if id.hasPrefix("background-") { delayResponse = true; responseDelay = 4 }
                    data = try JSONSerialization.data(withJSONObject: ["url": selectedURL, "trackId": id, "ttl": 90])
                }
            } else if path == "/track/lane-1/comments" {
                data = Data(#"{"items":[{"id":"comment-1","userId":"friend","userName":"Friend profile","text":"Parent comment","repliesCount":1},{"id":"anonymous","userName":"Deleted user","text":"No profile"}],"hasNext":false}"#.utf8)
            } else if path == "/comment/comment-1/replies" {
                data = Data(#"{"items":[{"id":"reply-1","userId":"second","userName":"Second friend","text":"Reply comment","replyToUserId":"friend","replyToUserName":"Friend profile"}],"hasNext":false}"#.utf8)
            } else if path == "/track/stats" {
                data = Data(#"{"likesCount":27,"commentsCount":4}"#.utf8)
            } else {
                data = Data("[]".utf8)
            }
            let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: statusCode == 429 ? ["Content-Type": contentType, "Retry-After": "3"] : ["Content-Type": contentType])!
            if delayResponse {
                let delivery = DispatchWorkItem { [self] in
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: data)
                    client?.urlProtocolDidFinishLoading(self)
                }
                delayedDelivery = delivery
                DispatchQueue.global().asyncAfter(deadline: .now() + responseDelay, execute: delivery)
            } else {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            }
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
