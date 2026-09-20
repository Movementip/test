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
    @Published var homeSections: [LaneHomeSection] = []
    @Published var homeTracks: [TrackCandidate] = []
    @Published var searchTracks: [TrackCandidate] = []
    @Published var searchArtists: [LaneArtist] = []
    @Published var searchAlbums: [LaneAlbum] = []
    @Published var searchPlaylists: [LanePlaylist] = []
    @Published var searchResultItems: [LaneSearchResultItem] = []
    @Published var searchToken: String?

    private func makeSearchRefID(query: String, results: [LaneSearchResultItem]) -> String {
        // Kotlin/Java List.hashCode() is deterministic. The original objects use
        // data-class hashCode(); for interoperability Lane only needs the same
        // context shape and a stable list discriminator.
        var listHash: Int32 = 1

        for result in results {
            var elementHash: Int32 = 17
            elementHash = elementHash &* 31 &+ javaStringHash(result.type ?? "")
            elementHash = elementHash &* 31 &+ javaStringHash(result.track?.songId ?? "")
            elementHash = elementHash &* 31 &+ javaStringHash(result.artist?.id ?? "")
            elementHash = elementHash &* 31 &+ javaStringHash(result.album?.id ?? "")
            elementHash = elementHash &* 31 &+ javaStringHash(result.playlist?.playlistId ?? "")
            listHash = listHash &* 31 &+ elementHash
        }

        return "search:\(query)\(listHash)"
    }

    private func javaStringHash(_ value: String) -> Int32 {
        var hash: Int32 = 0
        for scalar in value.utf16 {
            hash = hash &* 31 &+ Int32(scalar)
        }
        return hash
    }

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

    private func applyingRefID(_ refID: String?, to tracks: [TrackCandidate]) -> [TrackCandidate] {
        guard let refID, !refID.isEmpty else { return tracks }

        return tracks.map { track in
            TrackCandidate(
                id: track.id,
                title: track.title,
                subtitle: track.subtitle,
                trackID: track.trackID,
                refID: refID,
                platform: track.platform,
                coverURL: track.coverURL,
                duration: track.duration,
                genre: track.genre,
                artistAvatars: track.artistAvatars
            )
        }
    }

    func resolveTracksByIDs(
        _ ids: [String],
        prefetch: Bool = false,
        refID: String? = nil
    ) async -> [TrackCandidate] {
        let clean = ids.filter { !$0.isEmpty }
        guard !clean.isEmpty, !isGuest else { return [] }

        do {
            await configureAPI()
            let tracks = try await LaneAPI.shared.tracksByIds(
                token: token,
                ids: clean,
                prefetch: prefetch
            )
            return applyingRefID(refID, to: tracks.map { TrackCandidate($0) })
        } catch {
            output = "Track resolve error: \(error.localizedDescription)"

            // Preserve whatever is already present locally instead of showing
            // an empty detail page if the network resolver is unavailable.
            let local = history + searchTracks + queue + homeTracks + recentTracks
            var seen = Set<String>()
            let fallback = clean.compactMap { id in
                local.first(where: { $0.trackID == id })
            }.filter { seen.insert($0.id).inserted }

            return applyingRefID(refID, to: fallback)
        }
    }

    func fetchAlbumTracks(_ album: LaneAlbum) async -> [TrackCandidate] {
        let detail = await fetchAlbumDetail(album)
        let context = detail.id.map { "album:\($0)" }
        return await resolveTracksByIDs(detail.tracks ?? [], prefetch: false, refID: context)
    }

    func fetchArtistTopTracks(_ artist: LaneArtist) async -> [TrackCandidate] {
        let detail = await fetchArtistDetail(artist)
        let context = detail.id.map { "artist:\($0)" }
        return await resolveTracksByIDs(detail.topTracks ?? [], prefetch: false, refID: context)
    }

    func fetchArtistRecentTracks(_ artist: LaneArtist) async -> [TrackCandidate] {
        let detail = await fetchArtistDetail(artist)
        let context = detail.id.map { "artist:\($0)" }
        return await resolveTracksByIDs(detail.recentTracks ?? [], prefetch: false, refID: context)
    }

    // MARK: Social
    @Published var friends: [UserInfoDTO] = []
    @Published var userSearchResults: [UserInfoDTO] = []
    @Published var comments: [LaneTrackCommentDTO] = []
    @Published var commentReplies: [String: [LaneTrackCommentDTO]] = [:]
    @Published var loadingReplyIDs: Set<String> = []
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
    @Published var currentLyrics: LaneTrackLyrics?
    @Published var lyricsError = ""
    @Published var shuffleEnabled = false
    @Published var repeatMode = 0 // 0 = off, 1 = all, 2 = one

    private var player: AVPlayer?
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var playerTimeControlObserver: NSKeyValueObservation?
    private var periodicTimeObserver: Any?
    private var playerRetriedWithCompatibilityHeaders = false
    private var playerRetriedWithLocalDownload = false
    private var playerRetriedWithDownloadEndpoint = false
    private var playbackRequestID = UUID()
    private var streamResolveTask: Task<Void, Never>?

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
        homeSections = []
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
            homeSections = JSONProbe.homeSections(result.json)
            homeTracks = JSONProbe.tracks(result.json)

            if !homeSections.isEmpty {
                output = "Loaded \(homeSections.count) Lane home sections."
            }
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
            searchResultItems = []
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
                searchResultItems = response.results

                // Android Lane 1.4.7 does not pass searchToken as stream refId.
                // SearchViewModel.kt builds:
                // "search:" + query + searchResultList.hashCode()
                let searchRefID = makeSearchRefID(query: query, results: response.results)
                searchTracks = response.results.compactMap { $0.track }.map {
                    TrackCandidate($0, refID: searchRefID)
                }
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
                        let fallbackRef = "search:\(query)\(javaStringHash(query))"
                        searchTracks = tracks.map { track in
                            TrackCandidate(
                                id: track.id,
                                title: track.title,
                                subtitle: track.subtitle,
                                trackID: track.trackID,
                                refID: track.refID ?? fallbackRef,
                                platform: track.platform,
                                coverURL: track.coverURL,
                                duration: track.duration,
                                genre: track.genre,
                                artistAvatars: track.artistAvatars
                            )
                        }
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
            searchResultItems = []
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
            let context = "history:\(UUID().uuidString)"
            recentTracks = JSONProbe.tracks(recent.json).map { track in
                TrackCandidate(
                    id: track.id,
                    title: track.title,
                    subtitle: track.subtitle,
                    trackID: track.trackID,
                    refID: track.refID ?? context,
                    platform: track.platform,
                    coverURL: track.coverURL,
                    duration: track.duration,
                    genre: track.genre,
                    artistAvatars: track.artistAvatars
                )
            }
        }
    }

    func loadPlaylistTracks(_ playlist: LanePlaylist, completion: @escaping ([TrackCandidate]) -> Void) {
        guard let id = playlist.playlistId else {
            let fallback: [TrackCandidate] = playlist.playlistTracks?.map {
                TrackCandidate($0, refID: nil)
            } ?? []
            completion(fallback)
            return
        }

        Task { @MainActor in
            do {
                await configureAPI()
                let result: PaginatedResult<TrackData> = try await LaneAPI.shared.playlistTracks(
                    token: token,
                    playlistId: id
                )
                let tracks: [TrackCandidate] = result.items.map {
                    TrackCandidate($0, refID: id)
                }
                completion(tracks)
            } catch {
                output = error.localizedDescription
                let fallback: [TrackCandidate] = playlist.playlistTracks?.map {
                    TrackCandidate($0, refID: id)
                } ?? []
                completion(fallback)
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

    func loadReplies(for comment: LaneTrackCommentDTO) {
        guard !loadingReplyIDs.contains(comment.id) else { return }
        loadingReplyIDs.insert(comment.id)

        Task {
            defer { loadingReplyIDs.remove(comment.id) }
            do {
                await configureAPI()
                let page = try await LaneAPI.shared.replies(
                    token: token,
                    commentId: comment.id,
                    page: 0,
                    pageSize: 30
                )
                commentReplies[comment.id] = page.items
            } catch {
                output = "Replies error: \(error.localizedDescription)"
            }
        }
    }

    func sendReply(
        _ text: String,
        to comment: LaneTrackCommentDTO,
        replyTo user: LaneTrackCommentDTO? = nil
    ) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        Task {
            do {
                await configureAPI()
                _ = try await LaneAPI.shared.createReply(
                    token: token,
                    commentId: comment.id,
                    text: clean,
                    attachment: "",
                    replyToUserId: user?.userId ?? comment.userId ?? ""
                )
                loadReplies(for: comment)
            } catch {
                output = "Reply error: \(error.localizedDescription)"
            }
        }
    }

    func toggleReplyLike(_ reply: LaneTrackCommentDTO, parentComment: LaneTrackCommentDTO) {
        Task {
            do {
                await configureAPI()
                if reply.isLiked == true {
                    _ = try await LaneAPI.shared.unlikeComment(token: token, commentId: reply.id)
                } else {
                    _ = try await LaneAPI.shared.likeComment(token: token, commentId: reply.id)
                }
                loadReplies(for: parentComment)
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

        currentLyrics = nil
        lyricsError = ""

        Task {
            do {
                await configureAPI()
                currentLyrics = try await LaneAPI.shared.trackLyricsTyped(
                    token: token,
                    trackId: id
                )
                output = "Lyrics loaded"
            } catch {
                currentLyrics = nil
                lyricsError = error.localizedDescription
                output = "Lyrics error: \(error.localizedDescription)"
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
        // Every tap gets its own generation. Older resolver/download tasks are
        // ignored so a slow previous request can never start a different song.
        streamResolveTask?.cancel()
        let requestID = UUID()
        playbackRequestID = requestID

        player?.pause()
        teardownPlayerObservers()

        currentTrack = track
        playerError = ""
        playbackPosition = 0
        playbackDuration = parseDuration(track.duration) ?? 0
        trackStats = nil
        currentLyrics = nil
        lyricsError = ""
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
        playerRetriedWithCompatibilityHeaders = false
        playerRetriedWithLocalDownload = false
        playerRetriedWithDownloadEndpoint = false

        streamResolveTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.playbackRequestID == requestID {
                    self.busy = false
                }
            }

            do {
                await self.configureAPI()
                try Task.checkCancellation()
                guard self.playbackRequestID == requestID,
                      self.currentTrack?.id == track.id else { return }

                let result: TrackStreamingResult
                do {
                    result = try await LaneAPI.shared.stream(
                        token: self.token,
                        trackId: trackID,
                        refId: track.refID,
                        quality: self.streamQuality
                    )
                } catch {
                    try Task.checkCancellation()
                    guard self.playbackRequestID == requestID,
                          self.currentTrack?.id == track.id else { return }

                    if track.refID != nil {
                        result = try await LaneAPI.shared.stream(
                            token: self.token,
                            trackId: trackID,
                            refId: nil,
                            quality: self.streamQuality
                        )
                    } else {
                        throw error
                    }
                }

                try Task.checkCancellation()
                guard self.playbackRequestID == requestID,
                      self.currentTrack?.id == track.id else { return }

                self.streamURL = result.url
                try self.play(
                    urlString: result.url,
                    useCompatibilityHeaders: false,
                    requestID: requestID,
                    track: track
                )
            } catch is CancellationError {
                return
            } catch {
                guard self.playbackRequestID == requestID,
                      self.currentTrack?.id == track.id else { return }

                self.isBuffering = false
                self.isPlaying = false
                self.playerError = error.localizedDescription
                self.output = "Playback error: \(error.localizedDescription)"
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

    private func play(urlString: String, useCompatibilityHeaders: Bool) throws {
        guard let url = normalizedStreamURL(urlString) else {
            throw NSError(
                domain: "LanePlayer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Lane returned an invalid stream URL"]
            )
        }

        teardownPlayerObservers()

        // .allowBluetoothA2DP is implicit for AVAudioSession.Category.playback on
        // current iOS. Passing category-incompatible options can throw OSStatus -50
        // before AVPlayer even receives the Lane stream URL.
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .default, options: [])
        try audioSession.setActive(true)

        // Android Lane's Media3 data source is a plain
        // DefaultHttpDataSource.Factory. Start with an ordinary URL request.
        // A compatibility header pass is used only if AVFoundation rejects it.
        let asset: AVURLAsset
        if useCompatibilityHeaders {
            let headers = [
                "User-Agent": "LaneMusic/1.0 (Android; Mobile)",
                "Accept": "*/*",
                "Accept-Language": Locale.current.language.languageCode?.identifier ?? "en"
            ]
            asset = AVURLAsset(
                url: url,
                options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
            )
        } else {
            asset = AVURLAsset(url: url)
        }
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
                    let detail = item.error?.localizedDescription ?? "Unable to play this stream"

                    if !useCompatibilityHeaders,
                       !self.playerRetriedWithCompatibilityHeaders,
                       !self.streamURL.isEmpty {
                        self.playerRetriedWithCompatibilityHeaders = true
                        do {
                            try self.play(
                                urlString: self.streamURL,
                                useCompatibilityHeaders: true
                            )
                            return
                        } catch {
                            self.playerError = error.localizedDescription
                        }
                    }

                    if useCompatibilityHeaders,
                       !self.playerRetriedWithLocalDownload,
                       !self.streamURL.isEmpty {
                        self.playerRetriedWithLocalDownload = true
                        self.downloadStreamAndPlayLocally(self.streamURL)
                        return
                    }

                    self.isBuffering = false
                    self.isPlaying = false
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

        // AVPlayer can remain in waitingToPlayAtSpecifiedRate indefinitely for
        // some signed CDN URLs without ever transitioning to .failed. Android
        // Media3 retries the source; mirror that behavior here.
        Task { [weak self, weak newPlayer] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, let newPlayer, self.player === newPlayer else { return }
            guard self.isBuffering, self.playbackPosition < 0.25, !self.streamURL.isEmpty else { return }

            if !useCompatibilityHeaders && !self.playerRetriedWithCompatibilityHeaders {
                self.playerRetriedWithCompatibilityHeaders = true
                try? self.play(urlString: self.streamURL, useCompatibilityHeaders: true)
            } else if useCompatibilityHeaders && !self.playerRetriedWithLocalDownload {
                self.playerRetriedWithLocalDownload = true
                self.downloadStreamAndPlayLocally(self.streamURL)
            }
        }

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

    private func downloadStreamAndPlayLocally(_ urlString: String) {
        guard let url = normalizedStreamURL(urlString) else { return }

        // HLS playlists need AVPlayer's segment loader and cannot be converted
        // into a single local audio file by this fallback.
        if url.pathExtension.lowercased() == "m3u8" {
            isBuffering = false
            isPlaying = false
            playerError = "The HLS stream could not be opened by AVPlayer."
            output = "Playback error: \(playerError)"
            return
        }

        isBuffering = true
        output = "Lane is preparing the audio stream…"

        Task {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 30
                request.setValue("LaneMusic/1.0 (Android; Mobile)", forHTTPHeaderField: "User-Agent")
                request.setValue("*/*", forHTTPHeaderField: "Accept")
                request.setValue(
                    Locale.current.language.languageCode?.identifier ?? "en",
                    forHTTPHeaderField: "Accept-Language"
                )

                let (temporaryURL, response) = try await URLSession.shared.download(for: request)

                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    throw NSError(
                        domain: "LanePlayer",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Audio CDN returned HTTP \(http.statusCode)"]
                    )
                }

                // Android Lane's DownloadWorker writes every non-HLS
                // resolved audio response to <trackId>.m4a, regardless of the
                // CDN URL extension or Content-Type. Match that behavior because
                // AVFoundation relies more heavily on the local UTI/extension.
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("lane_stream_\(UUID().uuidString)")
                    .appendingPathExtension("m4a")

                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporaryURL, to: destination)

                teardownPlayerObservers()

                let item = AVPlayerItem(url: destination)
                let localPlayer = AVPlayer(playerItem: item)
                localPlayer.automaticallyWaitsToMinimizeStalling = false
                player = localPlayer

                playerItemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                    Task { @MainActor in
                        guard let self else { return }
                        switch item.status {
                        case .readyToPlay:
                            self.playerError = ""
                            self.isBuffering = false
                            if item.duration.seconds.isFinite && item.duration.seconds > 0 {
                                self.playbackDuration = item.duration.seconds
                            }
                            self.player?.play()
                        case .failed:
                            let detail = item.error?.localizedDescription ?? "Unable to decode Lane audio"

                            if !self.playerRetriedWithDownloadEndpoint {
                                self.playerRetriedWithDownloadEndpoint = true
                                self.resolveDownloadEndpointAndPlay()
                                return
                            }

                            self.isBuffering = false
                            self.isPlaying = false
                            self.playerError = detail
                            self.output = "Playback error: \(detail)"
                        case .unknown:
                            self.isBuffering = true
                        @unknown default:
                            break
                        }
                    }
                }

                playerTimeControlObserver = localPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
                    Task { @MainActor in
                        guard let self else { return }
                        self.isPlaying = player.timeControlStatus == .playing
                        self.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                        self.updatePlaybackState(self.isPlaying)
                    }
                }

                periodicTimeObserver = localPlayer.addPeriodicTimeObserver(
                    forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                    queue: .main
                ) { [weak self] time in
                    Task { @MainActor in
                        guard let self else { return }
                        if time.seconds.isFinite {
                            self.playbackPosition = max(0, time.seconds)
                        }
                    }
                }

                localPlayer.play()
            } catch {
                isBuffering = false
                isPlaying = false
                playerError = error.localizedDescription
                output = "Playback error: \(error.localizedDescription)"
            }
        }
    }


    private func resolveDownloadEndpointAndPlay() {
        guard let track = currentTrack,
              let trackID = track.trackID,
              !trackID.isEmpty else {
            isBuffering = false
            isPlaying = false
            playerError = "Lane track ID is unavailable for compatibility playback."
            output = "Playback error: \(playerError)"
            return
        }

        isBuffering = true
        output = "Trying Lane download-compatible audio…"

        Task {
            do {
                await configureAPI()

                let resolved = try await LaneAPI.shared.downloadURL(
                    token: token,
                    trackId: trackID,
                    quality: streamQuality
                )

                let raw = resolved.url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else {
                    throw NSError(
                        domain: "LanePlayer",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Lane download endpoint returned an empty URL"]
                    )
                }

                // DownloadWorker in Android treats .m3u8 specially. For online
                // playback AVPlayer can consume HLS directly, so try it as-is.
                if raw.lowercased().contains(".m3u8") {
                    try play(urlString: raw, useCompatibilityHeaders: true)
                    return
                }

                downloadCompatibilityAudio(raw)
            } catch {
                isBuffering = false
                isPlaying = false
                playerError = error.localizedDescription
                output = "Playback error: \(error.localizedDescription)"
            }
        }
    }

    private func downloadCompatibilityAudio(_ urlString: String) {
        guard let url = normalizedStreamURL(urlString) else {
            isBuffering = false
            playerError = "Lane returned an invalid compatibility audio URL."
            return
        }

        Task {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 45
                request.setValue("LaneMusic/1.0 (Android; Mobile)", forHTTPHeaderField: "User-Agent")
                request.setValue("*/*", forHTTPHeaderField: "Accept")
                request.setValue(
                    Locale.current.language.languageCode?.identifier ?? "en",
                    forHTTPHeaderField: "Accept-Language"
                )

                let (temporaryURL, response) = try await URLSession.shared.download(for: request)

                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    throw NSError(
                        domain: "LanePlayer",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Lane audio CDN returned HTTP \(http.statusCode)"]
                    )
                }

                let signature = Self.mediaSignature(at: temporaryURL)
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("lane_download_\(UUID().uuidString)")
                    .appendingPathExtension(Self.localAudioExtension(for: signature))

                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporaryURL, to: destination)

                try playLocalCompatibilityFile(
                    destination,
                    sourceDescription: signature.description
                )
            } catch {
                isBuffering = false
                isPlaying = false
                playerError = error.localizedDescription
                output = "Playback error: \(error.localizedDescription)"
            }
        }
    }

    private func playLocalCompatibilityFile(
        _ url: URL,
        sourceDescription: String
    ) throws {
        teardownPlayerObservers()

        let item = AVPlayerItem(url: url)
        let localPlayer = AVPlayer(playerItem: item)
        localPlayer.automaticallyWaitsToMinimizeStalling = false
        player = localPlayer

        playerItemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }

                switch item.status {
                case .readyToPlay:
                    self.playerError = ""
                    self.output = "Playing Lane audio (\(sourceDescription))."
                    self.isBuffering = false

                    let duration = item.duration.seconds
                    if duration.isFinite && duration > 0 {
                        self.playbackDuration = duration
                    }

                    self.player?.play()

                case .failed:
                    self.isBuffering = false
                    self.isPlaying = false
                    let avError = item.error as NSError?
                    let detail = avError?.localizedDescription ?? "Cannot Open"
                    let code = avError.map { "\($0.domain) \($0.code)" } ?? "unknown AVFoundation error"

                    self.playerError = "\(detail) · \(sourceDescription) · \(code)"
                    self.output = "Playback error: \(self.playerError)"

                case .unknown:
                    self.isBuffering = true

                @unknown default:
                    break
                }
            }
        }

        playerTimeControlObserver = localPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = player.timeControlStatus == .playing
                self.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self.updatePlaybackState(self.isPlaying)
            }
        }

        periodicTimeObserver = localPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                if time.seconds.isFinite {
                    self.playbackPosition = max(0, time.seconds)
                }
            }
        }

        localPlayer.play()
    }

    private enum LaneMediaSignature {
        case mp4
        case mp3
        case hls
        case ogg
        case webm
        case unknown(String)

        var description: String {
            switch self {
            case .mp4: return "M4A/MP4"
            case .mp3: return "MP3"
            case .hls: return "HLS"
            case .ogg: return "Ogg/Opus"
            case .webm: return "WebM"
            case .unknown(let hex): return "unknown format \(hex)"
            }
        }
    }

    nonisolated private static func mediaSignature(at url: URL) -> LaneMediaSignature {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return .unknown("unreadable")
        }
        defer { try? handle.close() }

        let data = (try? handle.read(upToCount: 32)) ?? Data()
        let bytes = [UInt8](data)

        if data.starts(with: Data("#EXTM3U".utf8)) {
            return .hls
        }
        if data.starts(with: Data("OggS".utf8)) {
            return .ogg
        }
        if bytes.count >= 4,
           bytes[0] == 0x1A,
           bytes[1] == 0x45,
           bytes[2] == 0xDF,
           bytes[3] == 0xA3 {
            return .webm
        }
        if data.starts(with: Data("ID3".utf8)) {
            return .mp3
        }
        if bytes.count >= 8,
           String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp" {
            return .mp4
        }
        if bytes.count >= 2,
           bytes[0] == 0xFF,
           (bytes[1] & 0xE0) == 0xE0 {
            return .mp3
        }

        return .unknown(data.prefix(8).map { String(format: "%02x", $0) }.joined())
    }

    nonisolated private static func localAudioExtension(for signature: LaneMediaSignature) -> String {
        switch signature {
        case .mp4:
            return "m4a"
        case .mp3:
            return "mp3"
        case .hls:
            return "m3u8"
        case .ogg:
            return "ogg"
        case .webm:
            return "webm"
        case .unknown:
            // Android Lane uses .m4a for all non-HLS downloads.
            return "m4a"
        }
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
        if let player {
            player.play()
            isBuffering = player.timeControlStatus != .playing
        } else if let currentTrack {
            requestStream(for: currentTrack)
        }
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
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
