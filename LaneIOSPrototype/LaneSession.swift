import Foundation
import AVFoundation
import MediaPlayer

@MainActor
final class LaneSession: ObservableObject {
    // MARK: Account / API
    @Published var token = KeychainStore.load(account: "bearer") ?? ""
    @Published var baseURL = UserDefaults.standard.string(forKey: "lane.base") ?? "https://laneapi.com"
    @Published var streamQuality = UserDefaults.standard.string(forKey: "lane.quality") ?? AudioQualityChoice.high.rawValue
    @Published var backendMode = LaneBackendMode(rawValue: UserDefaults.standard.string(forKey: "lane.backendMode") ?? "official") ?? .official
    @Published var apiKeyHeader = UserDefaults.standard.string(forKey: "lane.apiKeyHeader") ?? "X-API-Key"
    @Published var apiKey = KeychainStore.load(account: "lane.customApiKey") ?? ""
    @Published var account: UserAccountDTO?
    @Published var publicProfile: UserInfoDTO?
    @Published var output = "Ready"
    @Published var status = 0
    @Published var busy = false

    // MARK: Catalog
    @Published var homeTracks: [TrackCandidate] = []
    @Published var searchTracks: [TrackCandidate] = []
    @Published var searchArtists: [LaneArtist] = []
    @Published var searchAlbums: [LaneAlbum] = []
    @Published var searchPlaylists: [LanePlaylist] = []
    @Published var searchToken: String?

    // MARK: Library
    @Published var serverPlaylists: [LanePlaylist] = []
    @Published var serverAlbums: [LaneAlbum] = []
    @Published var serverArtists: [LaneArtist] = []
    @Published var recentTracks: [TrackCandidate] = []
    @Published var favorites: Set<String> = []
    @Published var localPlaylists: [LocalPlaylist] = []
    @Published var history: [TrackCandidate] = []
    @Published var downloadedTrackIDs: Set<String> = []

    func fetchArtistDetail(_ artist: LaneArtist) async -> LaneArtist {
        guard let id = artist.id, !id.isEmpty else { return artist }
        do {
            await configureAPI()
            return try await LaneAPI.shared.artistDetail(token: token, artistId: id)
        } catch {
            output = error.localizedDescription
            return artist
        }
    }

    func fetchAlbumDetail(_ album: LaneAlbum) async -> LaneAlbum {
        guard let id = album.id, !id.isEmpty else { return album }
        do {
            await configureAPI()
            return try await LaneAPI.shared.albumDetail(token: token, albumId: id)
        } catch {
            output = error.localizedDescription
            return album
        }
    }

    // MARK: Social
    @Published var friends: [UserInfoDTO] = []
    @Published var userSearchResults: [UserInfoDTO] = []
    @Published var comments: [LaneTrackCommentDTO] = []
    @Published var notificationCards: [LaneCardItem] = []

    // MARK: Player
    @Published var currentTrack: TrackCandidate?
    @Published var queue: [TrackCandidate] = []
    @Published var currentIndex: Int?
    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var streamURL = ""
    @Published var playbackPosition: Double = 0
    @Published var playbackDuration: Double = 0
    @Published var playerError = ""
    @Published var trackStats: TrackStatsDTO?
    @Published var shuffleEnabled = false
    @Published var repeatMode = 0 // 0 = off, 1 = all, 2 = one

    private var player: AVPlayer?
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var playerTimeControlObserver: NSKeyValueObservation?
    private var periodicTimeObserver: Any?

    var isGuest: Bool {
        token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        // Migrate tokens created by earlier iOS prototype builds.
        if token.isEmpty, let legacy = KeychainStore.load(account: "lane.token"), !legacy.isEmpty {
            token = legacy
            KeychainStore.save(legacy, account: "bearer")
        }
        loadLocalState()
        configureRemoteCommands()
    }

    // MARK: Persistence

    func persist() {
        if token.isEmpty {
            KeychainStore.delete(account: "bearer")
        } else {
            KeychainStore.save(token, account: "bearer")
        }
        UserDefaults.standard.set(baseURL, forKey: "lane.base")
        UserDefaults.standard.set(streamQuality, forKey: "lane.quality")
        UserDefaults.standard.set(backendMode.rawValue, forKey: "lane.backendMode")
        UserDefaults.standard.set(apiKeyHeader, forKey: "lane.apiKeyHeader")

        if apiKey.isEmpty {
            KeychainStore.delete(account: "lane.customApiKey")
        } else {
            KeychainStore.save(apiKey, account: "lane.customApiKey")
        }
    }

    func acceptLaneToken(_ value: String, serverBaseURL: String? = nil) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        if let serverBaseURL, !serverBaseURL.isEmpty {
            baseURL = serverBaseURL
        }

        token = clean
        persist()
        output = "Telegram authorization completed."

        Task {
            await refreshAfterLogin()
        }
    }

    func clearAccount() {
        token = ""
        KeychainStore.delete(account: "bearer")
        account = nil
        publicProfile = nil
        serverPlaylists = []
        serverAlbums = []
        serverArtists = []
        friends = []
        comments = []
        output = "Signed out"
    }

    func persistentTelegramAuthID() -> String {
        // Android Settings.Secure.ANDROID_ID is a 64-bit value normally represented
        // as 16 lowercase hexadecimal characters. Reproduce that shape on iOS.
        if let existing = KeychainStore.load(account: "telegramAuthId"),
           existing.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil {
            return existing
        }

        let hex = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        let generated = String(hex.prefix(16))
        KeychainStore.save(generated, account: "telegramAuthId")
        return generated
    }

    @discardableResult
    func setTelegramAuthID(_ value: String) -> Bool {
        let clean = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard clean.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil else {
            output = "Android ID must contain exactly 16 hexadecimal characters."
            return false
        }

        KeychainStore.save(clean, account: "telegramAuthId")
        output = "Authentication ID updated."
        return true
    }

    func generateNewTelegramAuthID() -> String {
        let generated = String(
            UUID().uuidString
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
                .prefix(16)
        )
        KeychainStore.save(generated, account: "telegramAuthId")
        return generated
    }

    func refreshAfterLogin() async {
        await configureAPI()
        await loadAccount()
        await loadHome()
        await loadLibrary()
        await loadFriends()
    }

    private func configureAPI() async {
        persist()
        await LaneAPI.shared.setBase(baseURL)
        await LaneAPI.shared.setServiceLDI(persistentTelegramAuthID())
        await LaneAPI.shared.setSigningConfiguration(
            LaneSigningConfiguration(
                mode: backendMode,
                apiKeyHeader: apiKeyHeader,
                apiKey: apiKey
            )
        )
    }

    func prepareAPI() async {
        await configureAPI()
    }

    func fetchBackendConfig() async throws -> LaneBackendConfig {
        await configureAPI()
        return try await LaneAPI.shared.backendConfig()
    }

    // MARK: Generic request / diagnostics

    func rawCall(path: String, method: String = "GET", query: [URLQueryItem] = [], body: Any? = nil) {
        busy = true
        output = "Requesting \(path)…"
        Task {
            defer { busy = false }
            do {
                await configureAPI()
                let result = try await LaneAPI.shared.request(path: path, method: method, token: token, query: query, json: body)
                status = result.status
                output = result.pretty
            } catch {
                status = 0
                output = error.localizedDescription
            }
        }
    }

    // MARK: Home

    func homeFeed() {
        busy = true
        Task {
            defer { busy = false }
            await loadHome()
        }
    }

    private func loadHome() async {
        guard !isGuest else { return }
        do {
            await configureAPI()
            let result = try await LaneAPI.shared.home(token: token)
            status = result.status
            output = result.pretty
            homeTracks = JSONProbe.tracks(result.json)
        } catch {
            output = error.localizedDescription
        }
    }

    // MARK: Account / profile

    func refreshAccount() {
        busy = true
        Task {
            defer { busy = false }
            await loadAccount()
        }
    }

    private func loadAccount() async {
        guard !isGuest else { return }
        do {
            await configureAPI()
            let language = Locale.current.language.languageCode?.identifier ?? "en"
            let accountValue = try await LaneAPI.shared.account(token: token, deviceLanguage: language)
            account = accountValue

            if let laneId = accountValue.laneId, !laneId.isEmpty {
                publicProfile = try? await LaneAPI.shared.userInfo(token: token, laneId: laneId)
            }
            status = 200
        } catch {
            output = error.localizedDescription
        }
    }

    func saveProfile(name: String, username: String, statusText: String) {
        guard !isGuest else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                await configureAPI()
                let result = try await LaneAPI.shared.editProfile(
                    token: token,
                    name: name,
                    username: username,
                    avatarURL: account?.avatarUrl ?? "",
                    headerURL: account?.headerUrl ?? "",
                    statusText: statusText
                )
                status = result.status
                output = result.pretty
                await loadAccount()
            } catch {
                output = error.localizedDescription
            }
        }
    }

    // MARK: Search

    func search(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        guard !isGuest else {
            status = 401
            output = "Sign in with Telegram before searching Lane."
            searchTracks = []
            searchArtists = []
            searchAlbums = []
            searchPlaylists = []
            return
        }

        busy = true
        output = "Searching Lane…"

        Task {
            defer { busy = false }
            await configureAPI()

            // Exact Android Lane 1.4.7 contract recovered from TrackRepositoryImpl:
            // platform=all and ver=1.0.
            if let response = try? await LaneAPI.shared.search(token: token, query: query) {
                searchToken = response.searchToken
                searchTracks = response.results.compactMap { $0.track }.map { TrackCandidate($0, refID: response.searchToken) }
                searchArtists = response.results.compactMap { $0.artist }
                searchAlbums = response.results.compactMap { $0.album }
                searchPlaylists = response.results.compactMap { $0.playlist }

                if !searchTracks.isEmpty || !searchArtists.isEmpty || !searchAlbums.isEmpty || !searchPlaylists.isEmpty {
                    status = 200
                    output = "Found \(response.results.count) results"
                    return
                }
            }

            // Compatibility probing for the API version value. This is deliberately
            // limited to known/probable client values and finally omits `ver`.
            let versions: [String?] = ["1.0", "1.4.7", "2", nil]
            var lastMessage = "No results returned by Lane."

            for version in versions {
                do {
                    let raw = try await LaneAPI.shared.searchRaw(token: token, query: query, version: version)
                    status = raw.status
                    lastMessage = "HTTP \(raw.status) · ver=\(version ?? "<omitted>")\n\(raw.pretty)"

                    guard (200..<300).contains(raw.status) else { continue }

                    let tracks = JSONProbe.tracks(raw.json)
                    if !tracks.isEmpty {
                        searchTracks = tracks
                        output = "Found \(tracks.count) tracks · ver=\(version ?? "<omitted>")"
                        return
                    }
                } catch {
                    lastMessage = error.localizedDescription
                }
            }

            searchTracks = []
            searchArtists = []
            searchAlbums = []
            searchPlaylists = []
            output = lastMessage
        }
    }

    // MARK: Library

    func refreshLibrary() {
        busy = true
        Task {
            defer { busy = false }
            await loadLibrary()
        }
    }

    private func loadLibrary() async {
        guard !isGuest else { return }

        do {
            await configureAPI()
            serverPlaylists = try await LaneAPI.shared.userPlaylists(token: token)
        } catch {
            output = error.localizedDescription
        }

        if let albums = try? await LaneAPI.shared.userAlbums(token: token) {
            serverAlbums = albums
        }

        if let artists = try? await LaneAPI.shared.userArtists(token: token) {
            serverArtists = artists
        }

        if let recent = try? await LaneAPI.shared.recentRaw(token: token) {
            recentTracks = JSONProbe.tracks(recent.json)
        }
    }

    func loadPlaylistTracks(_ playlist: LanePlaylist, completion: @escaping ([TrackCandidate]) -> Void) {
        guard let id = playlist.playlistId else {
            completion(playlist.playlistTracks?.map { TrackCandidate($0, refID: playlist.playlistId) } ?? [])
            return
        }

        Task {
            do {
                await configureAPI()
                let result = try await LaneAPI.shared.playlistTracks(token: token, playlistId: id)
                completion(result.items.map { TrackCandidate($0, refID: id) })
            } catch {
                output = error.localizedDescription
                completion(playlist.playlistTracks?.map(TrackCandidate.init) ?? [])
            }
        }
    }

    func createServerPlaylist(name: String, description: String = "", trackIDs: [String] = []) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isGuest else { return }

        busy = true
        Task {
            defer { busy = false }
            do {
                if account == nil {
                    await loadAccount()
                }
                guard let creator = account?.laneId, !creator.isEmpty else {
                    output = "Lane account ID is unavailable"
                    return
                }
                await configureAPI()
                let result = try await LaneAPI.shared.createPlaylist(
                    token: token,
                    imageURL: "",
                    name: clean,
                    description: description,
                    tracks: trackIDs,
                    creatorLid: creator
                )
                status = result.status
                output = result.pretty
                await loadLibrary()
            } catch {
                output = error.localizedDescription
            }
        }
    }

    func deleteServerPlaylist(_ playlist: LanePlaylist) {
        guard let id = playlist.playlistId else { return }
        Task {
            do {
                await configureAPI()
                let result = try await LaneAPI.shared.deletePlaylist(token: token, playlistId: id)
                status = result.status
                output = result.pretty
                await loadLibrary()
            } catch {
                output = error.localizedDescription
            }
        }
    }

    func addTrack(_ track: TrackCandidate, to playlist: LanePlaylist) {
        guard let playlistID = playlist.playlistId, let trackID = track.trackID else { return }
        Task {
            do {
                await configureAPI()
                let result = try await LaneAPI.shared.addTracks(token: token, playlistId: playlistID, trackIds: [trackID])
                status = result.status
                output = result.pretty
            } catch {
                output = error.localizedDescription
            }
        }
    }

    // MARK: Social

    func refreshFriends() {
        busy = true
        Task {
            defer { busy = false }
            await loadFriends()
        }
    }

    private func loadFriends() async {
        guard !isGuest else { return }
        do {
            await configureAPI()
            friends = try await LaneAPI.shared.friends(token: token).items
        } catch {
            output = error.localizedDescription
        }
    }

    func searchUsers(_ query: String) {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        busy = true
        Task {
            defer { busy = false }
            do {
                await configureAPI()
                userSearchResults = try await LaneAPI.shared.userSearch(token: token, query: clean)
            } catch {
                output = error.localizedDescription
            }
        }
    }

    func setFollowing(_ user: UserInfoDTO, follow: Bool) {
        guard let id = user.laneId else { return }

        Task {
            do {
                await configureAPI()
                if follow {
                    _ = try await LaneAPI.shared.follow(token: token, userId: id)
                } else {
                    _ = try await LaneAPI.shared.unfollow(token: token, userId: id)
                }
                await loadFriends()
            } catch {
                output = error.localizedDescription
            }
        }
    }

    func refreshNotifications() {
        busy = true
        Task {
            defer { busy = false }
            do {
                await configureAPI()
                let result = try await LaneAPI.shared.notifications(token: token)
                status = result.status
                output = result.pretty
                notificationCards = JSONProbe.cards(result.json, preferredKind: "notification")
            } catch {
                output = error.localizedDescription
            }
        }
    }

    // MARK: Comments

    func loadComments(for track: TrackCandidate) {
        guard let id = track.trackID else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                await configureAPI()
                comments = try await LaneAPI.shared.comments(
                    token: token,
                    trackId: id,
                    page: 0,
                    pageSize: 30,
                    sortBy: "Relevance"
                ).items
                output = comments.isEmpty ? "No comments on this track yet." : "Loaded \(comments.count) comments."
            } catch {
                comments = []
                output = "Comments error: \(error.localizedDescription)"
            }
        }
    }

    func sendComment(_ text: String, for track: TrackCandidate) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let id = track.trackID else { return }

        Task {
            do {
                await configureAPI()
                _ = try await LaneAPI.shared.createTrackComment(token: token, trackId: id, text: clean)
                loadComments(for: track)
            } catch {
                output = error.localizedDescription
            }
        }
    }

    func toggleCommentLike(_ comment: LaneTrackCommentDTO, for track: TrackCandidate) {
        Task {
            do {
                await configureAPI()
                if comment.isLiked == true {
                    _ = try await LaneAPI.shared.unlikeComment(token: token, commentId: comment.id)
                } else {
                    _ = try await LaneAPI.shared.likeComment(token: token, commentId: comment.id)
                }
                loadComments(for: track)
            } catch {
                output = error.localizedDescription
            }
        }
    }

    // MARK: Track metadata

    func loadTrackStats(_ track: TrackCandidate) {
        guard let id = track.trackID else { return }
        Task {
            do {
                await configureAPI()
                let stats = try await LaneAPI.shared.trackStats(token: token, trackId: id)
                trackStats = stats
                output = "Likes: \(stats.likesCount)\nComments: \(stats.commentsCount)"
            } catch {
                output = error.localizedDescription
            }
        }
    }

    func loadLyrics(_ track: TrackCandidate) {
        guard let id = track.trackID else { return }
        Task {
            do {
                await configureAPI()
                let result = try await LaneAPI.shared.trackLyrics(token: token, trackId: id)
                output = result.pretty
            } catch {
                output = error.localizedDescription
            }
        }
    }

    func loadRecommendations(_ track: TrackCandidate) {
        guard let id = track.trackID else { return }
        Task {
            do {
                await configureAPI()
                let result = try await LaneAPI.shared.recommendations(
                    token: token,
                    trackId: id,
                    platform: track.platform.isEmpty ? "all" : track.platform
                )
                let recommended = JSONProbe.tracks(result.json)
                if !recommended.isEmpty {
                    queue = recommended
                    currentIndex = nil
                }
                output = result.pretty
            } catch {
                output = error.localizedDescription
            }
        }
    }

    // MARK: Player

    func requestStream(for track: TrackCandidate) {
        currentTrack = track
        playerError = ""
        playbackPosition = 0
        playbackDuration = parseDuration(track.duration) ?? 0
        trackStats = nil
        loadTrackStats(track)

        if let index = queue.firstIndex(of: track) {
            currentIndex = index
        } else {
            if queue.isEmpty {
                queue = searchTracks
            }
            currentIndex = queue.firstIndex(of: track)
        }

        guard let trackID = track.trackID, !trackID.isEmpty else {
            playerError = "Track has no songId"
            output = playerError
            isPlaying = false
            return
        }

        busy = true
        isBuffering = true

        Task {
            defer { busy = false }
            do {
                await configureAPI()
                let result = try await LaneAPI.shared.stream(
                    token: token,
                    trackId: trackID,
                    refId: track.refID,
                    quality: streamQuality
                )

                streamURL = result.url
                try play(urlString: result.url)
            } catch {
                isBuffering = false
                isPlaying = false
                playerError = error.localizedDescription
                output = "Playback error: \(error.localizedDescription)"
            }
        }
    }

    private func normalizedStreamURL(_ raw: String) -> URL? {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let direct = URL(string: clean), direct.scheme != nil {
            return direct
        }

        if clean.hasPrefix("//") {
            return URL(string: "https:" + clean)
        }

        if let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded),
           url.scheme != nil {
            return url
        }

        return nil
    }

    private func teardownPlayerObservers() {
        playerItemStatusObserver?.invalidate()
        playerItemStatusObserver = nil

        playerTimeControlObserver?.invalidate()
        playerTimeControlObserver = nil

        if let periodicTimeObserver, let player {
            player.removeTimeObserver(periodicTimeObserver)
        }
        periodicTimeObserver = nil
    }

    private func play(urlString: String) throws {
        guard let url = normalizedStreamURL(urlString) else {
            throw NSError(
                domain: "LanePlayer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Lane returned an invalid stream URL"]
            )
        }

        teardownPlayerObservers()

        try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: [.allowAirPlay, .allowBluetoothA2DP]
        )
        try AVAudioSession.sharedInstance().setActive(true)

        // Android Lane resolves the URL and hands it to Media3. Supplying the
        // same client identity helps CDN endpoints which check the media client.
        let headers = [
            "User-Agent": "LaneMusic/1.0 (Android; Mobile)",
            "Accept": "*/*",
            "Accept-Language": Locale.current.language.languageCode?.identifier ?? "en"
        ]

        let asset = AVURLAsset(
            url: url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
        )
        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        player = newPlayer

        playerItemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }

                switch item.status {
                case .readyToPlay:
                    self.playerError = ""
                    self.isBuffering = false

                    let seconds = item.duration.seconds
                    if seconds.isFinite && seconds > 0 {
                        self.playbackDuration = seconds
                    }

                    self.player?.play()

                case .failed:
                    self.isBuffering = false
                    self.isPlaying = false
                    let detail = item.error?.localizedDescription ?? "Unable to play this stream"
                    self.playerError = detail
                    self.output = "Playback error: \(detail)"

                case .unknown:
                    self.isBuffering = true

                @unknown default:
                    break
                }
            }
        }

        playerTimeControlObserver = newPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }

                switch player.timeControlStatus {
                case .playing:
                    self.isPlaying = true
                    self.isBuffering = false
                case .waitingToPlayAtSpecifiedRate:
                    self.isPlaying = false
                    self.isBuffering = true
                case .paused:
                    self.isPlaying = false
                @unknown default:
                    self.isPlaying = false
                }

                self.updatePlaybackState(self.isPlaying)
            }
        }

        periodicTimeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite {
                    self.playbackPosition = max(0, seconds)
                }

                if let duration = self.player?.currentItem?.duration.seconds,
                   duration.isFinite,
                   duration > 0 {
                    self.playbackDuration = duration
                }
            }
        }

        newPlayer.play()

        if let currentTrack {
            history.removeAll { $0.id == currentTrack.id }
            history.insert(currentTrack, at: 0)
            if history.count > 100 {
                history = Array(history.prefix(100))
            }
            saveHistory()
        }

        updateNowPlaying()
    }

    func seek(to seconds: Double) {
        guard let player, seconds.isFinite else { return }

        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        playbackPosition = max(0, seconds)
    }

    private func parseDuration(_ raw: String?) -> Double? {
        guard let raw, !raw.isEmpty else { return nil }

        if let direct = Double(raw), direct > 0 {
            // Backends sometimes return milliseconds and sometimes seconds.
            return direct > 20_000 ? direct / 1000.0 : direct
        }

        let parts = raw.split(separator: ":").compactMap { Double($0) }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }

        return nil
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updatePlaybackState(false)
    }

    func resume() {
        player?.play()
        isPlaying = true
        updatePlaybackState(true)
    }

    func togglePlayback() {
        isPlaying ? pause() : resume()
    }

    func stop() {
        player?.pause()
        teardownPlayerObservers()
        player = nil
        isPlaying = false
        isBuffering = false
        playbackPosition = 0
        playbackDuration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func next() {
        guard !queue.isEmpty else { return }

        if repeatMode == 2, let currentTrack {
            requestStream(for: currentTrack)
            return
        }

        let current = currentIndex ?? -1
        var nextIndex = current + 1

        if nextIndex >= queue.count {
            guard repeatMode == 1 else { return }
            nextIndex = 0
        }

        guard nextIndex >= 0, nextIndex < queue.count else { return }
        currentIndex = nextIndex
        requestStream(for: queue[nextIndex])
    }

    func previous() {
        guard !queue.isEmpty else { return }
        let previousIndex = max((currentIndex ?? 1) - 1, 0)
        guard previousIndex != currentIndex else { return }
        currentIndex = previousIndex
        requestStream(for: queue[previousIndex])
    }

    func toggleShuffle() {
        shuffleEnabled.toggle()
        if shuffleEnabled, !queue.isEmpty {
            let current = currentTrack
            queue.shuffle()
            if let current, let index = queue.firstIndex(of: current) {
                currentIndex = index
            }
        }
    }

    func cycleRepeatMode() {
        repeatMode = (repeatMode + 1) % 3
    }

    func addToQueue(_ track: TrackCandidate) {
        if !queue.contains(track) {
            queue.append(track)
        }
    }

    func playNext(_ track: TrackCandidate) {
        let index = (currentIndex ?? -1) + 1
        if index >= 0 && index <= queue.count {
            queue.insert(track, at: index)
        } else {
            queue.append(track)
        }
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = currentTrack?.title ?? "Lane"
        info[MPMediaItemPropertyArtist] = currentTrack?.subtitle ?? ""
        info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updatePlaybackState(_ playing: Bool) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()

        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }

        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }

        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }

        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
    }

    // MARK: Favorites / local playlists

    private func favoriteKey(_ track: TrackCandidate) -> String {
        track.trackID ?? track.id
    }

    func isFavorite(_ track: TrackCandidate) -> Bool {
        favorites.contains(favoriteKey(track))
    }

    func toggleFavorite(_ track: TrackCandidate) {
        let key = favoriteKey(track)
        if favorites.contains(key) {
            favorites.remove(key)
        } else {
            favorites.insert(key)
        }
        UserDefaults.standard.set(Array(favorites), forKey: "lane.favorites")
    }

    func toggleFavoriteCurrent() {
        if let currentTrack {
            toggleFavorite(currentTrack)
        }
    }

    func createLocalPlaylist(name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        localPlaylists.append(LocalPlaylist(name: clean))
        saveLocalPlaylists()
    }

    func deleteLocalPlaylist(at offsets: IndexSet) {
        localPlaylists.remove(atOffsets: offsets)
        saveLocalPlaylists()
    }

    func add(_ track: TrackCandidate, to localPlaylistID: UUID) {
        guard let index = localPlaylists.firstIndex(where: { $0.id == localPlaylistID }) else { return }
        let key = favoriteKey(track)
        if !localPlaylists[index].trackKeys.contains(key) {
            localPlaylists[index].trackKeys.append(key)
            saveLocalPlaylists()
        }
    }

    func tracks(in playlist: LocalPlaylist) -> [TrackCandidate] {
        let all = history + searchTracks + queue + homeTracks + recentTracks
        return playlist.trackKeys.compactMap { key in
            all.first { favoriteKey($0) == key }
        }
    }

    // MARK: Downloads

    func downloadTrack(_ track: TrackCandidate) {
        guard let trackID = track.trackID else { return }

        busy = true
        Task {
            defer { busy = false }
            do {
                await configureAPI()
                let stream = try await LaneAPI.shared.downloadURL(token: token, trackId: trackID, quality: streamQuality)
                guard let remoteURL = URL(string: stream.url) else {
                    throw LaneAPIError.invalidURL
                }

                let (temporary, _) = try await URLSession.shared.download(from: remoteURL)
                let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("LaneDownloads", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

                let safeID = trackID.replacingOccurrences(of: "/", with: "_")
                let ext = remoteURL.pathExtension.isEmpty ? "m4a" : remoteURL.pathExtension
                let destination = directory.appendingPathComponent("\(safeID).\(ext)")

                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporary, to: destination)

                downloadedTrackIDs.insert(trackID)
                UserDefaults.standard.set(Array(downloadedTrackIDs), forKey: "lane.downloads")
                output = "Downloaded \(track.title)"
            } catch {
                output = error.localizedDescription
            }
        }
    }

    func isDownloaded(_ track: TrackCandidate) -> Bool {
        guard let id = track.trackID else { return false }
        return downloadedTrackIDs.contains(id)
    }

    // MARK: Local storage

    private func loadLocalState() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: "lane.favorites") ?? [])
        downloadedTrackIDs = Set(UserDefaults.standard.stringArray(forKey: "lane.downloads") ?? [])

        if let data = UserDefaults.standard.data(forKey: "lane.localPlaylists"),
           let decoded = try? JSONDecoder().decode([LocalPlaylist].self, from: data) {
            localPlaylists = decoded
        }

        if let data = UserDefaults.standard.data(forKey: "lane.history"),
           let decoded = try? JSONDecoder().decode([TrackCandidate].self, from: data) {
            history = decoded
        }
    }

    private func saveLocalPlaylists() {
        if let data = try? JSONEncoder().encode(localPlaylists) {
            UserDefaults.standard.set(data, forKey: "lane.localPlaylists")
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "lane.history")
        }
    }
}
