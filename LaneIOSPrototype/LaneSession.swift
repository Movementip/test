import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import CryptoKit

private struct YandexPlaylistEnvelope: Decodable {
    let result: YandexPlaylistPayload
}

private struct YandexPlaylistPayload: Decodable {
    let tracks: [YandexPlaylistEntry]
}

private struct YandexPlaylistEntry: Decodable {
    let id: String?
    let originalIndex: Int?
    let track: YandexTrackPayload?

    private enum CodingKeys: String, CodingKey {
        case id, originalIndex, track
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? values.decode(String.self, forKey: .id))
            ?? (try? values.decode(Int64.self, forKey: .id)).map(String.init)
        originalIndex = try values.decodeIfPresent(Int.self, forKey: .originalIndex)
        track = try values.decodeIfPresent(YandexTrackPayload.self, forKey: .track)
    }
}

private struct YandexTrackPayload: Decodable {
    let id: String?
    let title: String?
    let artists: [YandexArtistPayload]?
    let coverUri: String?
    let available: Bool?
}

private struct YandexArtistPayload: Decodable {
    let name: String?
}

struct LanePlaylistDownloadState: Equatable {
    let completed: Int
    let total: Int
    let failed: Int
    let isRunning: Bool
}

@MainActor
final class LaneSession: ObservableObject {
    // MARK: Account / API
    @Published var token = KeychainStore.load(account: "bearer") ?? ""
    @Published var baseURL = UserDefaults.standard.string(forKey: "lane.base") ?? "https://laneapi.com"
    // Keep the selected tier across launches and request exactly that tier.
    @Published var streamQuality = UserDefaults.standard.string(forKey: "lane.quality") ?? AudioQualityChoice.basic.rawValue {
        didSet {
            if AudioQualityChoice(rawValue: streamQuality) == nil {
                streamQuality = AudioQualityChoice.basic.rawValue
                return
            }
            UserDefaults.standard.set(streamQuality, forKey: "lane.quality")
        }
    }
    @Published private(set) var activeStreamQuality: String?
    @Published var backendMode = LaneBackendMode(rawValue: UserDefaults.standard.string(forKey: "lane.backendMode") ?? "official") ?? .official
    @Published var apiKeyHeader = UserDefaults.standard.string(forKey: "lane.apiKeyHeader") ?? "X-API-Key"
    @Published var apiKey = KeychainStore.load(account: "lane.customApiKey") ?? ""
    @Published var account: UserAccountDTO?
    @Published var publicProfile: UserInfoDTO?
    @Published var output = "Ready"
    @Published var status = 0
    @Published var busy = false

    // MARK: Runtime diagnostics
    @Published var diagnosticHostMode = UserDefaults.standard.string(forKey: "lane.diag.host") ?? "auto" {
        didSet { UserDefaults.standard.set(diagnosticHostMode, forKey: "lane.diag.host") }
    }
    @Published var diagnosticTransportMode = UserDefaults.standard.string(forKey: "lane.diag.transport") ?? "system" {
        didSet { UserDefaults.standard.set(diagnosticTransportMode, forKey: "lane.diag.transport") }
    }
    @Published var diagnosticTrackBodyMode = UserDefaults.standard.string(forKey: "lane.diag.trackBody") ?? "auto" {
        didSet { UserDefaults.standard.set(diagnosticTrackBodyMode, forKey: "lane.diag.trackBody") }
    }
    @Published var diagnosticAddBodyMode = UserDefaults.standard.string(forKey: "lane.diag.addBody") ?? "auto" {
        didSet { UserDefaults.standard.set(diagnosticAddBodyMode, forKey: "lane.diag.addBody") }
    }
    @Published var diagnosticMediaRoute = UserDefaults.standard.string(forKey: "lane.diag.mediaRoute") ?? "original" {
        didSet { UserDefaults.standard.set(diagnosticMediaRoute, forKey: "lane.diag.mediaRoute") }
    }
    @Published var diagnosticsRunning = false
    @Published var mutationDiagnosticsRunning = false
    @Published var diagnosticReport = ""
    @Published var diagnosticTraceText = ""

    // MARK: Catalog
    @Published var homeSections: [LaneHomeSection] = []
    @Published var homeTracks: [TrackCandidate] = []
    @Published var searchTracks: [TrackCandidate] = []
    @Published var searchArtists: [LaneArtist] = []
    @Published var searchAlbums: [LaneAlbum] = []
    @Published var searchPlaylists: [LanePlaylist] = []
    @Published var searchResultItems: [LaneSearchResultItem] = []
    @Published var searchHistoryItems: [LaneSearchHistoryItem] = []
    @Published var searchHistoryIsLoading = false
    @Published var searchHistoryMessage = ""
    @Published var searchToken: String?
    @Published var searchMessage = ""
    @Published var searchIsLoading = false
    @Published var wavePlaylist: LanePlaylist?
    @Published var waveIsLoading = false
    @Published var waveError: String?
    @Published var waveSourceCoverURL: String?
    private var waveTask: Task<Void, Never>?
    private var waveRequestID = UUID()
    @Published var trackResolveMessage = ""
    private var resolvedTrackCache: [String: TrackCandidate] = [:]
    private var searchTask: Task<Void, Never>?

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
    @Published var playlistLoadMessages: [String: String] = [:]
    private var playlistTrackCache: [String: [TrackCandidate]] = [:]
    private var playlistContentGenerations: [String: UUID] = [:]
    @Published var incomingShare: LaneIncomingShare?

    func receiveShareURL(_ url: URL) {
        guard let share = LaneIncomingShare(url: url) else { return }
        incomingShare = share
    }

    func resolveShare(_ share: LaneIncomingShare) async throws -> LaneOpenShareItem {
        await configureAPI()
        return try await LaneAPI.shared.openShare(id: share.id)
    }
    @Published private(set) var clearingPlaylistIDs: Set<String> = []
    @Published private(set) var playlistClearStages: [String: String] = [:]
    private var cancelledPlaylistClears: Set<String> = []
    @Published private(set) var importingPlaylistIDs: Set<String> = []
    @Published private(set) var playlistImportStages: [String: String] = [:]
    @Published private(set) var playlistImportErrors: [String: String] = [:]
    @Published var serverAlbums: [LaneAlbum] = []
    private var cachedAlbumDetails: [String: LaneAlbum] = [:]
    @Published var serverArtists: [LaneArtist] = []
    private var cachedArtistDetails: [String: LaneArtist] = [:]
    @Published var recentTracks: [TrackCandidate] = []
    @Published var favorites: Set<String> = []
    @Published var likedTracks: [TrackCandidate] = []
    private var favoriteMutationsInFlight: Set<String> = []
    @Published private var pendingFavoriteStates: [String: Bool] = [:]
    private let pendingFavoriteStatesKey = "lane.pendingFavoriteStates"
    private var pendingSavedPlaylists: [String: LanePlaylist] = [:]
    private var pendingRemovedPlaylistIDs: Set<String> = []
    private var libraryLoadGeneration = UUID()
    private var profileMutationGeneration = UUID()
    private var favoriteMigrationInProgress = false
    private let favoriteMigrationKey = "lane.favorites.serverMigrationCompleted"
    @Published var localPlaylists: [LocalPlaylist] = []
    @Published var history: [TrackCandidate] = []
    @Published var downloadedTrackIDs: Set<String> = []
    @Published private var downloadedTrackRecords: [String: LaneDownloadedTrack] = [:]
    @Published var playlistDownloads: [String: LanePlaylistDownloadState] = [:]
    private var playlistDownloadTasks: [String: Task<Void, Never>] = [:]
    private var localTrackStore: [String: TrackCandidate] = [:]

    func fetchArtistDetail(_ artist: LaneArtist) async -> LaneArtist {
        guard let id = artist.id, !id.isEmpty else { return artist }
        do {
            await configureAPI()
            let detail = try await LaneAPI.shared.artistDetail(token: token, artistId: id)
            cachedArtistDetails[id] = detail
            if let data = try? JSONEncoder().encode(cachedArtistDetails) {
                UserDefaults.standard.set(data, forKey: "lane.cachedArtistDetails")
            }
            return detail
        } catch {
            output = error.localizedDescription
            return cachedArtistDetails[id] ?? artist
        }
    }

    /// TrackData in the Android app exposes platform artist IDs through its
    /// Spotify/SoundCloud payload. Prefer those IDs; older cached iOS tracks do
    /// not have them, so fall back to Lane search by the displayed artist name.
    func resolveArtist(for track: TrackCandidate) async -> LaneArtist? {
        let displayedName = track.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayedName.isEmpty,
              displayedName.localizedCaseInsensitiveCompare("Unknown artist") != .orderedSame else {
            return nil
        }

        let knownArtists = serverArtists + searchArtists + Array(cachedArtistDetails.values)
        if let artistID = track.artistIDs?.first, !artistID.isEmpty {
            if let existing = knownArtists.first(where: { $0.id == artistID }) {
                return existing
            }
            return LaneArtist(
                name: displayedName,
                id: artistID,
                platform: track.platform,
                avatarUrl: track.artistAvatars?.first
            )
        }

        let normalized = displayedName.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        if let existing = knownArtists.first(where: {
            $0.name?.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ) == normalized
        }) {
            return existing
        }

        do {
            await configureAPI()
            let response = try await LaneAPI.shared.search(token: token, query: displayedName)
            let artists = response.results.compactMap(\.artist)
            let match = artists.first(where: {
                $0.name?.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                ) == normalized
            }) ?? artists.first
            if let match {
                if !searchArtists.contains(where: { $0.id == match.id }) {
                    searchArtists.append(match)
                }
                return match
            }
        } catch {
            output = "Artist lookup error: \(error.localizedDescription)"
        }

        return LaneArtist(
            name: displayedName,
            platform: track.platform,
            avatarUrl: track.artistAvatars?.first
        )
    }

    func cachedArtistDetail(for artist: LaneArtist) -> LaneArtist? {
        guard let id = artist.id, !id.isEmpty else { return nil }
        return cachedArtistDetails[id]
    }

    private func mergedAlbumDetail(_ preferred: LaneAlbum, fallback: LaneAlbum) -> LaneAlbum {
        let preferredTracks = preferred.tracks ?? []
        let fallbackTracks = fallback.tracks ?? []
        let tracks = preferredTracks.count >= fallbackTracks.count ? preferredTracks : fallbackTracks

        return LaneAlbum(
            name: preferred.name ?? fallback.name,
            id: preferred.id ?? fallback.id,
            platform: preferred.platform ?? fallback.platform,
            type: preferred.type ?? fallback.type,
            coverUrl: preferred.coverUrl ?? fallback.coverUrl,
            year: preferred.year ?? fallback.year,
            artists: preferred.artists ?? fallback.artists,
            artistsDisplayedName: preferred.artistsDisplayedName ?? fallback.artistsDisplayedName,
            tracks: tracks,
            lastUpdated: max(preferred.lastUpdated ?? 0, fallback.lastUpdated ?? 0)
        )
    }

    func fetchAlbumDetailStrict(_ album: LaneAlbum) async throws -> LaneAlbum {
        guard let id = album.id, !id.isEmpty else {
            throw LaneAPIError.decoding("Album ID is missing")
        }
        await configureAPI()
        let detail = try await LaneAPI.shared.albumDetail(token: token, albumId: id)
        let fallback =
            cachedAlbumDetails[id] ??
            serverAlbums.first(where: { $0.id == id }) ??
            searchAlbums.first(where: { $0.id == id }) ??
            album
        let merged = mergedAlbumDetail(detail, fallback: fallback)

        if let ids = merged.tracks, !ids.isEmpty {
            cachedAlbumDetails[id] = merged
            if let data = try? JSONEncoder().encode(cachedAlbumDetails) {
                UserDefaults.standard.set(data, forKey: "lane.cachedAlbumDetails")
            }
        }
        return merged
    }

    func cachedAlbumDetail(for album: LaneAlbum) -> LaneAlbum? {
        guard let id = album.id, !id.isEmpty else { return nil }
        return cachedAlbumDetails[id]
            ?? serverAlbums.first(where: { $0.id == id && !($0.tracks ?? []).isEmpty })
            ?? searchAlbums.first(where: { $0.id == id && !($0.tracks ?? []).isEmpty })
    }

    func fetchAlbumDetail(_ album: LaneAlbum) async -> LaneAlbum {
        do {
            return try await fetchAlbumDetailStrict(album)
        } catch {
            output = error.localizedDescription
            return cachedAlbumDetail(for: album) ?? album
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
                artistAvatars: track.artistAvatars,
                artistIDs: track.artistIDs
            )
        }
    }

    func cachedTracksForIDs(_ ids: [String], refID: String? = nil) -> [TrackCandidate] {
        applyingRefID(refID, to: ids.compactMap { resolvedTrackCache[$0] })
    }

    private func rememberResolvedTracks(_ tracks: [TrackCandidate]) {
        guard !tracks.isEmpty else { return }
        for track in tracks {
            guard let id = track.trackID, !id.isEmpty else { continue }
            if let existing = resolvedTrackCache[id],
               (existing.coverURL != nil && track.coverURL == nil ||
                existing.title != "Unknown track" && track.title == "Unknown track") {
                continue
            }
            resolvedTrackCache[id] = TrackCandidate(
                id: track.id,
                title: track.title,
                subtitle: track.subtitle,
                trackID: id,
                platform: track.platform,
                coverURL: track.coverURL,
                duration: track.duration,
                genre: track.genre,
                artistAvatars: track.artistAvatars,
                artistIDs: track.artistIDs
            )
        }
        if let data = try? JSONEncoder().encode(resolvedTrackCache) {
            UserDefaults.standard.set(data, forKey: "lane.cachedTrackMetadata")
        }
    }

    private func resolveTrackDataResilient(
        _ ids: [String],
        prefetch: Bool
    ) async throws -> [TrackData] {
        guard !ids.isEmpty else { return [] }

        do {
            return try await LaneAPI.shared.tracksByIds(
                token: token,
                ids: ids,
                prefetch: prefetch
            )
        } catch {
            let text = error.localizedDescription
            if text.localizedCaseInsensitiveContains("INVALID_TRACK_IDS_BODY") {
                // This is a serializer/body-contract rejection, not evidence
                // that one particular track is bad. LaneAPI already tried the
                // compatible body shapes in auto mode; bisecting the same body
                // only multiplies requests and made albums/imports painfully slow.
                throw error
            }

            guard case let LaneAPIError.http(status, _) = error,
                  status == 400,
                  ids.count > 1 else {
                throw error
            }

            // For other 400s only, isolate a genuinely stale/unsupported ID
            // without discarding valid tracks from the album/playlist.
            let middle = ids.count / 2
            var recovered: [TrackData] = []
            var failedHalves = 0

            do {
                recovered += try await resolveTrackDataResilient(
                    Array(ids[..<middle]),
                    prefetch: prefetch
                )
            } catch {
                failedHalves += 1
            }
            do {
                recovered += try await resolveTrackDataResilient(
                    Array(ids[middle...]),
                    prefetch: prefetch
                )
            } catch {
                failedHalves += 1
            }

            // A stale platform ID must not hide every other valid album track.
            // Preserve the original server error only when neither half could
            // be recovered at all.
            if failedHalves == 2 { throw error }
            return recovered
        }
    }

    func resolveTracksByIDs(
        _ ids: [String],
        prefetch: Bool = false,
        refID: String? = nil
    ) async -> [TrackCandidate] {
        let clean = ids.filter { !$0.isEmpty }
        guard !clean.isEmpty, !isGuest else { return [] }
        let cached = cachedTracksForIDs(clean, refID: refID)
        if !prefetch && cached.count == clean.count {
            trackResolveMessage = ""
            return cached
        }

        do {
            await configureAPI()
            trackResolveMessage = ""
            var tracks: [TrackData] = []

            // Android resolves large collections in pages. Keeping each
            // read-only /user/tracks body small also avoids carrier/proxy body
            // limits that are common when the phone is used without a VPN.
            for start in stride(from: 0, to: clean.count, by: 15) {
                let end = min(start + 15, clean.count)
                let batch = try await resolveTrackDataResilient(
                    Array(clean[start..<end]),
                    prefetch: prefetch
                )
                tracks.append(contentsOf: batch)
            }
            let candidates = tracks.map { TrackCandidate($0) }
            rememberResolvedTracks(candidates)
            let ordered = LaneTrackBatching.ordered(candidates + cached, sourceIDs: clean)
            if ordered.isEmpty && trackResolveMessage.isEmpty {
                trackResolveMessage = "Lane returned no track details for \(clean.count) listed IDs. Try again."
            }
            return applyingRefID(refID, to: ordered)
        } catch {
            output = "Track resolve error: \(error.localizedDescription)"
            if case let LaneAPIError.http(status, _) = error {
                trackResolveMessage = "Lane could not load these tracks (HTTP \(status)). Try again."
            } else {
                trackResolveMessage = "Tracks are temporarily unavailable. Try again."
            }

            // Preserve whatever is already present locally instead of showing
            // an empty detail page if the network resolver is unavailable.
            var local = cached
            local.append(contentsOf: history)
            local.append(contentsOf: searchTracks)
            local.append(contentsOf: queue)
            local.append(contentsOf: homeTracks)
            local.append(contentsOf: recentTracks)
            let fallback = clean.compactMap { id in
                local.first(where: { $0.trackID == id })
            }

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
    @Published var notifications: [LaneNotification] = []
    @Published var unreadNotificationCount = 0
    @Published var notificationsLoading = false
    @Published var notificationsHaveMore = false
    @Published var notificationsError: String?
    @Published var notificationMutations: Set<String> = []
    private var nextNotificationPage = 0

    // MARK: Player
    @Published var currentTrack: TrackCandidate?
    @Published var queue: [TrackCandidate] = []
    @Published var currentIndex: Int?
    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var streamURL = ""
    @Published var playbackPosition: Double = 0
    @Published var playbackDuration: Double = 0
    @Published var playbackBufferedDuration: Double = 0
    @Published private(set) var currentTrackEffect: LaneTrackEffect = .original
    @Published private(set) var trackEffectIsLoading = false
    @Published var trackEffectError = ""
    private var trackEffects: [String: LaneTrackEffect] = [:]
    private var effectRequestID = UUID()
    private var playbackShouldPlay = true
    private var pendingStartPosition: Double?
    private var seekingInitialPosition = false
    @Published var playerError = ""
    @Published var trackStats: TrackStatsDTO?
    @Published var currentLyrics: LaneTrackLyrics?
    @Published var lyricsError = ""
    @Published var shuffleEnabled = false
    @Published var repeatMode = 0 // 0 = off, 1 = all, 2 = one
    @Published private(set) var equalizerEnabled = UserDefaults.standard.bool(forKey: "lane.equalizer.enabled")
    @Published private(set) var equalizerValues: [Double] = {
        let values = UserDefaults.standard.array(forKey: "lane.equalizer.values") as? [Double]
        return values?.count == 6 ? values!.map { min(1, max(0, $0.isFinite ? $0 : 0.5)) } : Array(repeating: 0.5, count: 6)
    }()
    @Published private(set) var equalizerStatus = "Equalizer is off"
    private var equalizerProcessor: LaneEqualizerProcessor?
    private var equalizerTask: Task<Void, Never>?

    func setEqualizer(enabled: Bool) {
        equalizerEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "lane.equalizer.enabled")
        equalizerProcessor?.configure(values: equalizerValues, enabled: enabled)
        if enabled, equalizerProcessor == nil, let item = player?.currentItem { attachEqualizer(to: item) }
        refreshEqualizerStatus()
    }
    func setEqualizer(band: Int, value: Double) {
        guard equalizerValues.indices.contains(band) else { return }
        equalizerValues[band] = min(1, max(0, value.isFinite ? value : 0.5))
        UserDefaults.standard.set(equalizerValues, forKey: "lane.equalizer.values")
        equalizerProcessor?.configure(values: equalizerValues, enabled: equalizerEnabled)
    }
    func applyEqualizerPreset(_ preset: LaneEqualizerPresets.Preset) {
        guard LaneEqualizerPresets.all.contains(where: { $0.name == preset.name && $0.values == preset.values }) else { return }
        equalizerValues = preset.values
        UserDefaults.standard.set(equalizerValues, forKey: "lane.equalizer.values")
        setEqualizer(enabled: preset.name != "Default")
    }
    func resetEqualizer() {
        equalizerValues = Array(repeating: 0.5, count: 6)
        UserDefaults.standard.set(equalizerValues, forKey: "lane.equalizer.values")
        equalizerProcessor?.configure(values: equalizerValues, enabled: equalizerEnabled)
    }
    func refreshEqualizerStatus() {
        if !equalizerEnabled { equalizerStatus = "Equalizer is off" }
        else if let processor = equalizerProcessor, processor.processedFrames > 0, processor.supportsFormat { equalizerStatus = "Equalizer is processing audio" }
        else { equalizerStatus = "Waiting for compatible audio. If this adaptive stream does not support iOS filters, it plays unchanged." }
    }
    private func attachEqualizer(to item: AVPlayerItem) {
        equalizerTask?.cancel(); equalizerProcessor = nil
        guard equalizerEnabled else { return }
        let processor = LaneEqualizerProcessor()
        processor.configure(values: equalizerValues, enabled: true)
        equalizerTask = Task { [weak self, weak item] in
            guard let item else { return }
            do {
                let mix = try await processor.audioMix(for: item.asset)
                guard let self, self.player?.currentItem === item, !Task.isCancelled, let mix else { return }
                processor.configure(values: self.equalizerValues, enabled: self.equalizerEnabled)
                self.equalizerProcessor = processor; item.audioMix = mix
                self.refreshEqualizerStatus()
            } catch { self?.refreshEqualizerStatus() }
        }
    }
    #if DEBUG
    var debugEqualizerFrames: Int64 { equalizerProcessor?.processedFrames ?? 0 }
    #endif

    private var player: AVPlayer?
    private var nowPlayingArtworkTask: Task<Void, Never>?
    private var nowPlayingArtworkKey: String?
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var offlineStoreObserver: NSObjectProtocol?
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var playerLoadedTimeRangesObserver: NSKeyValueObservation?
    private var playerTimeControlObserver: NSKeyValueObservation?
    private var periodicTimeObserver: Any?
    private var playbackEndObserver: NSObjectProtocol?
    private var playbackStallObserver: NSObjectProtocol?
    private var playerRetriedWithCompatibilityHeaders = false
    private var playerRetriedWithLocalDownload = false
    private var playerRetriedWithProgressiveTransport = false
    private var progressiveAudioLoader: LaneProgressiveAudioLoader?
    #if DEBUG
    var debugUseProgressiveTransport = false
    #endif
    private var playbackRequestID = UUID()
    private var streamResolveTask: Task<Void, Never>?
    private var playbackWatchdogTask: Task<Void, Never>?
    private var trackStatsTask: Task<Void, Never>?
    private var trackStatsCache: [String: TrackStatsDTO] = [:]
    private var streamResolutionCache: [String: (result: TrackStreamingResult, expiresAt: Date)] = [:]
    private var nextStreamTask: Task<TrackStreamingResult, Error>?
    private var nextStreamKey: String?
    private var nextStreamOperation = UUID()
    private var prefetchedPlaybackRequestID: UUID?
    private var progressiveMediaHosts: Set<String> = []
    private var playbackBackgroundLease: LaneAudioBackgroundLease?
    private var playbackBackgroundRequestID: UUID?
    private var audioLifecycleObservers: [NSObjectProtocol] = []
    private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
    private var audioInterrupted = false
    private var interruptionResumeRequested = false
    @Published private(set) var friendActivity: [LaneFriendPresence] = []
    private var presenceSyncTask: Task<Void, Never>?
    private var clientEventsTask: Task<Void, Never>?
    private var clientEventsGeneration = UUID()
    #if DEBUG
    var debugHasPlaybackBackgroundTask: Bool { playbackBackgroundLease?.isActive == true }
    var debugAudioState: String {
        "intent=\(playbackShouldPlay), interrupted=\(audioInterrupted), nativeState=\(player?.timeControlStatus.rawValue ?? -1), rate=\(player?.rate ?? -1), itemState=\(player?.currentItem?.status.rawValue ?? -1), duration=\(player?.currentItem?.duration.seconds ?? -1)"
    }
    func debugExpirePlaybackLease() {
        playbackBackgroundLease?.expireForTesting { [weak self] generation in
            self?.playbackTransitionExpired(generation: generation)
        }
    }
    func debugBeginPlaybackLease() { beginPlaybackTransition(requestID: playbackRequestID) }
    #endif
    private var didConfigureAPIBase = false
    private var didPrepareRegionalHost = false
    private var didAutoTuneNetwork = false
    private var didAutoTuneMediaRoute = false
    private var configuredBackendMode: LaneBackendMode?

    var isGuest: Bool {
        token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasPremiumAccess: Bool {
        if account?.isAutoRenewalActive == true {
            return true
        }
        guard let expiresAt = account?.premiumExpiresIn, expiresAt > 0 else {
            return false
        }
        // Lane currently serializes premiumExpiresIn as an epoch timestamp.
        // Accept both milliseconds and seconds so account payload revisions do
        // not incorrectly lock Premium import/audio features.
        let expirySeconds = expiresAt > 10_000_000_000
            ? Double(expiresAt) / 1000.0
            : Double(expiresAt)
        return expirySeconds > Date().timeIntervalSince1970
    }

    init() {
        // Migrate tokens created by earlier iOS prototype builds.
        if token.isEmpty, let legacy = KeychainStore.load(account: "lane.token"), !legacy.isEmpty {
            token = legacy
            KeychainStore.save(legacy, account: "bearer")
        }
        loadLocalState()
        if let data = UserDefaults.standard.data(forKey: "lane.cachedTrackMetadata"),
           let cache = try? JSONDecoder().decode([String: TrackCandidate].self, from: data) {
            resolvedTrackCache = cache
        }
        restorePendingFavoriteTracks()
        if let data = UserDefaults.standard.data(forKey: "lane.cachedPlaylistTracks"),
           let cache = try? JSONDecoder().decode([String: [TrackCandidate]].self, from: data) {
            playlistTrackCache = cache
        }
        if let data = UserDefaults.standard.data(forKey: "lane.cachedAlbumDetails"),
           let cache = try? JSONDecoder().decode([String: LaneAlbum].self, from: data) {
            cachedAlbumDetails = cache
        }
        if let data = UserDefaults.standard.data(forKey: "lane.cachedArtistDetails"),
           let cache = try? JSONDecoder().decode([String: LaneArtist].self, from: data) {
            cachedArtistDetails = cache
        }
        if let data = UserDefaults.standard.data(forKey: "lane.cachedTrackStats"),
           let cache = try? JSONDecoder().decode([String: TrackStatsDTO].self, from: data) {
            trackStatsCache = cache
        }
        configureRemoteCommands()
        configureAudioLifecycle()
        refreshHLSDownloads()
        offlineStoreObserver = NotificationCenter.default.addObserver(forName: LaneHLSOfflineStore.changed, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshHLSDownloads() }
        }
    }

    deinit {
        nowPlayingArtworkTask?.cancel()
        if let offlineStoreObserver { NotificationCenter.default.removeObserver(offlineStoreObserver) }
        equalizerTask?.cancel()
        for observer in audioLifecycleObservers { NotificationCenter.default.removeObserver(observer) }
        for (command, target) in remoteCommandTargets { command.removeTarget(target) }
        playbackBackgroundLease?.end()
    }

    // MARK: Persistence

    func persist() {
        if token.isEmpty {
            KeychainStore.delete(account: "bearer")
        } else {
            KeychainStore.save(token, account: "bearer")
        }
        // In official mode LaneAPI owns this value after probing/failover.
        // Do not replace a known-working regional host with stale UI state.
        if backendMode == .custom || !didPrepareRegionalHost {
            UserDefaults.standard.set(baseURL, forKey: "lane.base")
        } else if let resolved = UserDefaults.standard.string(forKey: "lane.base") {
            baseURL = resolved
        }
        UserDefaults.standard.set(streamQuality, forKey: "lane.quality")
        UserDefaults.standard.set(backendMode.rawValue, forKey: "lane.backendMode")
        UserDefaults.standard.set(apiKeyHeader, forKey: "lane.apiKeyHeader")

        if apiKey.isEmpty {
            KeychainStore.delete(account: "lane.customApiKey")
        } else {
            KeychainStore.save(apiKey, account: "lane.customApiKey")
        }
    }

    func persistStreamQualitySelection() {
        if AudioQualityChoice(rawValue: streamQuality) == nil {
            streamQuality = AudioQualityChoice.basic.rawValue
        }
        persist()
    }

    @discardableResult
    func selectStreamQuality(_ quality: AudioQualityChoice) -> Bool {
        if quality != .basic && !hasPremiumAccess {
            output = "Lane Premium is required for \(quality.title) audio quality."
            return false
        }
        streamQuality = quality.rawValue
        return true
    }

    private func selectedPlaybackQuality() -> String {
        AudioQualityChoice(rawValue: streamQuality)?.rawValue ?? AudioQualityChoice.basic.rawValue
    }

    func acceptLaneToken(_ value: String, serverBaseURL: String? = nil) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        if let serverBaseURL, !serverBaseURL.isEmpty {
            baseURL = serverBaseURL
        }

        if token != clean {
            stop()
            playlistImportStages = [:]
            playlistImportErrors = [:]
            favorites = []
            likedTracks = []
            favoriteMutationsInFlight = []
            pendingFavoriteStates = [:]
            pendingSavedPlaylists = [:]
            pendingRemovedPlaylistIDs = []
            streamResolutionCache = [:]
            cancelPreparedStream()
            favoriteMigrationInProgress = false
            UserDefaults.standard.removeObject(forKey: "lane.favorites")
            UserDefaults.standard.removeObject(forKey: pendingFavoriteStatesKey)
            UserDefaults.standard.removeObject(forKey: favoriteMigrationKey)
        }
        token = clean
        persist()
        output = "Telegram authorization completed."

        Task {
            await refreshAfterLogin()
        }
    }

    func clearAccount() {
        stop()
        presenceSyncTask?.cancel()
        setClientEventsActive(false)
        friendActivity = []
        waveTask?.cancel()
        waveRequestID = UUID()
        wavePlaylist = nil
        waveIsLoading = false
        waveError = nil
        token = ""
        KeychainStore.delete(account: "bearer")
        account = nil
        publicProfile = nil
        serverPlaylists = []
        playlistImportStages = [:]
        playlistImportErrors = [:]
        favorites = []
        likedTracks = []
        favoriteMutationsInFlight = []
        pendingFavoriteStates = [:]
        pendingSavedPlaylists = [:]
        pendingRemovedPlaylistIDs = []
        favoriteMigrationInProgress = false
        UserDefaults.standard.removeObject(forKey: "lane.favorites")
        UserDefaults.standard.removeObject(forKey: pendingFavoriteStatesKey)
        UserDefaults.standard.removeObject(forKey: favoriteMigrationKey)
        resolvedTrackCache = [:]
        UserDefaults.standard.removeObject(forKey: "lane.cachedTrackMetadata")
        playlistTrackCache = [:]
        playlistLoadMessages = [:]
        UserDefaults.standard.removeObject(forKey: "lane.cachedPlaylistTracks")
        serverAlbums = []
        cachedAlbumDetails = [:]
        UserDefaults.standard.removeObject(forKey: "lane.cachedAlbumDetails")
        serverArtists = []
        cachedArtistDetails = [:]
        UserDefaults.standard.removeObject(forKey: "lane.cachedArtistDetails")
        trackStatsTask?.cancel()
        trackStatsCache = [:]
        trackStats = nil
        UserDefaults.standard.removeObject(forKey: "lane.cachedTrackStats")
        streamResolutionCache = [:]
        cancelPreparedStream()
        activeStreamQuality = nil
        homeSections = []
        friends = []
        notifications = []
        unreadNotificationCount = 0
        nextNotificationPage = 0
        notificationsHaveMore = false
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
        async let accountLoad: Void = loadAccount()
        async let homeLoad: Void = loadHome()
        async let libraryLoad: Void = loadLibrary()
        async let friendsLoad: Void = loadFriends()
        _ = await (accountLoad, homeLoad, libraryLoad, friendsLoad)

        if backendMode == .official {
            baseURL = await LaneAPI.shared.currentBaseURL()
        }
    }

    private func configureAPI() async {
        let modeChanged = configuredBackendMode != backendMode
        if !didConfigureAPIBase || modeChanged || backendMode == .custom {
            await LaneAPI.shared.setBase(baseURL)
            didConfigureAPIBase = true
        }

        if modeChanged {
            didAutoTuneNetwork = false
            configuredBackendMode = backendMode
        }

        await LaneAPI.shared.setServiceLDI(persistentTelegramAuthID())
        await LaneAPI.shared.setSigningConfiguration(
            LaneSigningConfiguration(
                mode: backendMode,
                apiKeyHeader: apiKeyHeader,
                apiKey: apiKey
            )
        )

        // Test the real network once per app session before the first signed
        // request. This chooses system vs direct transport and global vs RU
        // Lane host without requiring another IPA reinstall.
        if backendMode == .official, !didAutoTuneNetwork {
            didAutoTuneNetwork = true
            let publicProfile = await LaneAPI.shared.autoTuneNetworkProfile()

            var authenticatedProfile = "guest"
            if !token.isEmpty {
                let language = Locale.current.language.languageCode?.identifier ?? "en"
                authenticatedProfile = await LaneAPI.shared.autoTuneAuthenticatedProfile(
                    token: token,
                    deviceLanguage: language
                )
            }

            diagnosticHostMode = UserDefaults.standard.string(forKey: "lane.diag.host") ?? "auto"
            diagnosticTransportMode = UserDefaults.standard.string(forKey: "lane.diag.transport") ?? "system"
            baseURL = await LaneAPI.shared.currentBaseURL()
            diagnosticReport = "Auto-selected network: \(publicProfile)\nAuthenticated route: \(authenticatedProfile)"
        }
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


    func resetDiagnosticProfileToStable() {
        diagnosticHostMode = "auto"
        diagnosticTransportMode = "system"
        diagnosticTrackBodyMode = "auto"
        diagnosticAddBodyMode = "auto"
        diagnosticMediaRoute = "original"
        diagnosticReport = "Compatibility profile restored: Auto host, System transport, original media URLs, automatic track-body detection."
    }

    func clearDiagnosticTrace() {
        Task {
            await LaneAPI.shared.clearDiagnosticTrace()
            diagnosticTraceText = ""
        }
    }

    func refreshDiagnosticTrace() {
        Task {
            let lines = await LaneAPI.shared.diagnosticTrace()
            diagnosticTraceText = lines.joined(separator: "\n")
        }
    }

    func autoTuneLaneNetwork() {
        guard !diagnosticsRunning else { return }
        diagnosticsRunning = true
        diagnosticReport = "Testing Lane network profiles…"

        Task { @MainActor in
            defer {
                diagnosticsRunning = false
                refreshDiagnosticTrace()
            }

            await configureAPI()
            let language = Locale.current.language.languageCode?.identifier ?? "en"
            let candidates: [(host: String, transport: String)] = [
                ("auto", "system"),
                ("global", "system"),
                ("ru", "system"),
                ("global", "direct"),
                ("ru", "direct"),
                ("auto", "auto")
            ]

            var report: [String] = ["Lane auto-tune"]
            var best: (host: String, transport: String, ms: Int)?

            for candidate in candidates {
                diagnosticHostMode = candidate.host
                diagnosticTransportMode = candidate.transport
                let started = Date()

                do {
                    if token.isEmpty {
                        let result = try await LaneAPI.shared.request(path: "/time")
                        try result.requireSuccess()
                    } else {
                        _ = try await LaneAPI.shared.account(
                            token: token,
                            deviceLanguage: language
                        )
                    }

                    let ms = Int(Date().timeIntervalSince(started) * 1000)
                    report.append("\(candidate.host)/\(candidate.transport): PASS \(ms)ms")
                    if best == nil || ms < best!.ms {
                        best = (candidate.host, candidate.transport, ms)
                    }
                } catch {
                    let ms = Int(Date().timeIntervalSince(started) * 1000)
                    report.append("\(candidate.host)/\(candidate.transport): FAIL \(ms)ms \(error.localizedDescription)")
                }
            }

            if let best {
                diagnosticHostMode = best.host
                diagnosticTransportMode = best.transport
                report.append("selected network=\(best.host)/\(best.transport) \(best.ms)ms")
            } else {
                diagnosticHostMode = "auto"
                diagnosticTransportMode = "system"
                report.append("No authenticated API profile succeeded.")
            }

            guard !token.isEmpty else {
                diagnosticReport = report.joined(separator: "\n")
                return
            }

            let sampleTrackID =
                currentTrack?.trackID ??
                recentTracks.first?.trackID ??
                history.first?.trackID ??
                homeTracks.first?.trackID ??
                searchTracks.first?.trackID

            if let sampleTrackID, !sampleTrackID.isEmpty {
                var selectedTrackBody: String?
                for mode in ["object", "raw"] {
                    diagnosticTrackBodyMode = mode
                    do {
                        let tracks = try await LaneAPI.shared.tracksByIds(
                            token: token,
                            ids: [sampleTrackID],
                            prefetch: false
                        )
                        if !tracks.isEmpty {
                            selectedTrackBody = mode
                            report.append("/user/tracks \(mode): PASS")
                            break
                        }
                        report.append("/user/tracks \(mode): empty")
                    } catch {
                        report.append("/user/tracks \(mode): FAIL \(error.localizedDescription)")
                    }
                }
                diagnosticTrackBodyMode = selectedTrackBody ?? "object"
                report.append("selected track body=\(diagnosticTrackBodyMode)")
            } else {
                report.append("track body auto-detect: SKIP no local track")
            }

            var selectedAddBody: String?
            for mode in ["raw", "object"] {
                diagnosticAddBodyMode = mode
                do {
                    let result = try await LaneAPI.shared.addTracks(
                        token: token,
                        playlistId: "__lane_diagnostics_missing_playlist__",
                        trackIds: ["__lane_diagnostics_missing_track__"]
                    )
                    let bodyRejected =
                        result.status == 400 &&
                        result.pretty.localizedCaseInsensitiveContains("INVALID_PLAYLIST_TRACKS_BODY")
                    if bodyRejected {
                        report.append("add-tracks \(mode): body rejected")
                    } else {
                        report.append("add-tracks \(mode): body accepted (HTTP \(result.status))")
                        selectedAddBody = mode
                        break
                    }
                } catch {
                    report.append("add-tracks \(mode): transport FAIL \(error.localizedDescription)")
                }
            }
            diagnosticAddBodyMode = selectedAddBody ?? "raw"
            report.append("selected add body=\(diagnosticAddBodyMode)")
            report.append("media route kept=\(diagnosticMediaRoute)")
            diagnosticReport = report.joined(separator: "\n")
        }
    }

    func runLaneMutationDiagnostics() {
        guard !mutationDiagnosticsRunning else { return }
        mutationDiagnosticsRunning = true

        Task { @MainActor in
            defer {
                mutationDiagnosticsRunning = false
                refreshDiagnosticTrace()
            }

            await configureAPI()
            var report: [String] = ["Lane write self-test"]

            guard !token.isEmpty else {
                diagnosticReport = "Lane write self-test\nFAIL: account is not authenticated."
                return
            }

            if account == nil {
                await loadAccount()
            }
            guard let creator = account?.laneId, !creator.isEmpty else {
                diagnosticReport = "Lane write self-test\nFAIL: Lane account ID is unavailable."
                return
            }

            let sampleTrackID =
                currentTrack?.trackID ??
                recentTracks.first?.trackID ??
                history.first?.trackID ??
                homeTracks.first?.trackID ??
                searchTracks.first?.trackID

            guard let sampleTrackID, !sampleTrackID.isEmpty else {
                diagnosticReport = "Lane write self-test\nFAIL: play or open at least one track first so the test has a real Lane track ID."
                return
            }

            let marker = String(UUID().uuidString.prefix(8)).lowercased()
            let diagnosticName = "Lane iOS diagnostic \(marker)"
            var createdPlaylistID: String?

            do {
                let create = try await LaneAPI.shared.createPlaylist(
                    token: token,
                    imageURL: "",
                    name: diagnosticName,
                    description: "Temporary automatic API self-test. Safe to delete.",
                    tracks: [],
                    creatorLid: creator
                )
                try create.requireSuccess()
                report.append("create playlist: PASS HTTP \(create.status)")

                for attempt in 0..<5 {
                    let playlists = try await LaneAPI.shared.userPlaylists(token: token)
                    if let match = playlists.first(where: { $0.playlistName == diagnosticName }),
                       let id = match.playlistId,
                       !id.isEmpty {
                        createdPlaylistID = id
                        break
                    }
                    if attempt < 4 {
                        try await Task.sleep(nanoseconds: 500_000_000)
                    }
                }

                guard let playlistID = createdPlaylistID else {
                    throw LaneAPIError.decoding("Created diagnostic playlist did not appear in /user/playlists.")
                }
                report.append("playlist visibility: PASS")

                let add = try await LaneAPI.shared.addTracks(
                    token: token,
                    playlistId: playlistID,
                    trackIds: [sampleTrackID]
                )
                try add.requireSuccess()
                report.append("add-tracks: PASS HTTP \(add.status) bodyMode=\(diagnosticAddBodyMode)")

                var verified = false
                for attempt in 0..<4 {
                    if let detail = try? await LaneAPI.shared.playlist(
                        token: token,
                        playlistId: playlistID
                    ) {
                        let ids = detail.playlistTracksIds ??
                            detail.playlistTracks?.compactMap(\.songId) ??
                            []
                        if ids.contains(sampleTrackID) {
                            verified = true
                            break
                        }
                    }

                    if let page = try? await LaneAPI.shared.playlistTracks(
                        token: token,
                        playlistId: playlistID,
                        page: 0,
                        pageSize: 20
                    ),
                    page.items.contains(where: { $0.songId == sampleTrackID }) {
                        verified = true
                        break
                    }

                    if attempt < 3 {
                        try await Task.sleep(nanoseconds: 500_000_000)
                    }
                }

                report.append(verified
                    ? "verify persisted track: PASS"
                    : "verify persisted track: FAIL (server did not expose added track)")
            } catch {
                report.append("write path: FAIL \(error.localizedDescription)")
            }

            if let createdPlaylistID {
                do {
                    let cleanup = try await LaneAPI.shared.deletePlaylist(
                        token: token,
                        playlistId: createdPlaylistID
                    )
                    try cleanup.requireSuccess()
                    report.append("cleanup diagnostic playlist: PASS")
                } catch {
                    report.append("cleanup diagnostic playlist: FAIL \(error.localizedDescription)")
                }
            }

            diagnosticReport = report.joined(separator: "\n")
            await loadLibrary()
        }
    }

    func runLaneDiagnostics() {
        guard !diagnosticsRunning else { return }
        diagnosticsRunning = true
        diagnosticReport = "Running Lane diagnostics…"

        Task { @MainActor in
            defer {
                diagnosticsRunning = false
                refreshDiagnosticTrace()
            }

            await configureAPI()
            var report: [String] = []
            report.append("Lane diagnostics")
            report.append("hostMode=\(diagnosticHostMode) transport=\(diagnosticTransportMode)")
            report.append("trackBody=\(diagnosticTrackBodyMode) addBody=\(diagnosticAddBodyMode)")
            report.append("base=\(await LaneAPI.shared.currentBaseURL())")
            report.append("token=\(token.isEmpty ? "missing" : "present")")

            async let globalProbe = LaneAPI.shared.diagnosticTimeProbe(baseURL: "https://laneapi.com")
            async let ruProbe = LaneAPI.shared.diagnosticTimeProbe(baseURL: "https://ru.laneapi.com")
            let (global, ru) = await (globalProbe, ruProbe)
            report.append("laneapi.com: \(global)")
            report.append("ru.laneapi.com: \(ru)")

            guard !token.isEmpty else {
                diagnosticReport = report.joined(separator: "\n")
                return
            }

            func timed<T>(_ name: String, _ operation: () async throws -> T) async -> T? {
                let started = Date()
                do {
                    let value = try await operation()
                    let ms = Int(Date().timeIntervalSince(started) * 1000)
                    report.append("\(name): PASS \(ms)ms")
                    return value
                } catch {
                    let ms = Int(Date().timeIntervalSince(started) * 1000)
                    report.append("\(name): FAIL \(ms)ms \(error.localizedDescription)")
                    return nil
                }
            }

            let language = Locale.current.language.languageCode?.identifier ?? "en"
            let accountResult: UserAccountDTO? = await timed("account") {
                try await LaneAPI.shared.account(token: token, deviceLanguage: language)
            }
            let playlistsResult: [LanePlaylist]? = await timed("playlists") {
                try await LaneAPI.shared.userPlaylists(token: token)
            }
            _ = await timed("albums") {
                try await LaneAPI.shared.userAlbums(token: token)
            } as [LaneAlbum]?
            _ = await timed("artists") {
                try await LaneAPI.shared.userArtists(token: token)
            } as [LaneArtist]?

            let sampleTrackID =
                currentTrack?.trackID ??
                recentTracks.first?.trackID ??
                history.first?.trackID ??
                homeTracks.first?.trackID ??
                searchTracks.first?.trackID

            if let sampleTrackID, !sampleTrackID.isEmpty {
                let resolved: [TrackData]? = await timed("user/tracks sample") {
                    try await LaneAPI.shared.tracksByIds(
                        token: token,
                        ids: [sampleTrackID],
                        prefetch: false
                    )
                }
                if let resolved {
                    report.append("user/tracks returned=\(resolved.count)")
                }
            } else {
                report.append("user/tracks sample: SKIP no local track ID")
            }

            let samplePlaylist =
                playlistsResult?.first(where: { $0.playlistId != "lane_likes" }) ??
                playlistsResult?.first

            if let playlistID = samplePlaylist?.playlistId, !playlistID.isEmpty {
                let detail: LanePlaylist? = await timed("playlist detail") {
                    try await LaneAPI.shared.playlist(token: token, playlistId: playlistID)
                }
                if let detail {
                    let count = detail.playlistTracksIds?.count ??
                        detail.playlistTracks?.count ??
                        detail.tracksCount ?? 0
                    report.append("playlist detail tracks=\(count)")
                }
            } else {
                report.append("playlist detail: SKIP no playlist")
            }

            if let laneId = accountResult?.laneId, !laneId.isEmpty {
                _ = await timed("user-info") {
                    try await LaneAPI.shared.userInfo(token: token, laneId: laneId)
                } as UserInfoDTO?
            }

            diagnosticReport = report.joined(separator: "\n")
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
            rememberResolvedTracks(homeTracks)

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
        let requestToken = token
        let generation = profileMutationGeneration
        do {
            await configureAPI()
            let language = Locale.current.language.languageCode?.identifier ?? "en"
            let accountValue = try await LaneAPI.shared.account(token: requestToken, deviceLanguage: language)
            guard token == requestToken, profileMutationGeneration == generation else { return }
            account = accountValue

            if let laneId = accountValue.laneId, !laneId.isEmpty {
                let profile = try? await LaneAPI.shared.userInfo(token: requestToken, laneId: laneId)
                guard token == requestToken, profileMutationGeneration == generation else { return }
                publicProfile = profile
            }
            status = 200
        } catch {
            guard token == requestToken, profileMutationGeneration == generation else { return }
            output = error.localizedDescription
        }
    }

    func saveProfile(name: String, username: String, statusText: String, avatarURL: String, headerURL: String) async throws {
        guard !isGuest else { throw LaneAPIError.decoding("Sign in to edit your profile.") }
        profileMutationGeneration = UUID()
        let generation = profileMutationGeneration
        let requestToken = token
        await configureAPI()
        guard token == requestToken, profileMutationGeneration == generation else { throw CancellationError() }
        let result = try await LaneAPI.shared.editProfile(token: requestToken, name: name, username: username,
                                                          avatarURL: avatarURL, headerURL: headerURL, statusText: statusText)
        try result.requireSuccess()
        let value = try await LaneAPI.shared.account(token: requestToken, deviceLanguage: Locale.current.language.languageCode?.identifier ?? "en")
        guard token == requestToken, profileMutationGeneration == generation else { throw CancellationError() }
        account = value
        if let id = value.laneId {
            let profile = try? await LaneAPI.shared.userInfo(token: requestToken, laneId: id)
            guard token == requestToken, profileMutationGeneration == generation else { throw CancellationError() }
            publicProfile = profile
        }
    }

    func uploadProfileImage(_ data: Data, target: String, isGIF: Bool) async throws -> String {
        let requestToken = token
        await configureAPI()
        guard token == requestToken, !Task.isCancelled else { throw CancellationError() }
        let url = try await LaneAPI.shared.uploadProfileImage(token: requestToken, data: data, target: target, isGIF: isGIF)
        guard token == requestToken, !Task.isCancelled else { throw CancellationError() }
        return url
    }

    func loadPrivacySettings() async throws -> LanePrivacySettings {
        guard !isGuest else { throw LaneAPIError.decoding("Sign in to change privacy settings.") }
        let requestToken = token
        await configureAPI()
        let value = try await LaneAPI.shared.account(token: requestToken, deviceLanguage: Locale.current.language.languageCode?.identifier ?? "en")
        guard token == requestToken else { throw CancellationError() }
        account = value
        return value.privacySettings ?? LanePrivacySettings()
    }

    func savePrivacySettings(_ settings: LanePrivacySettings) async throws {
        guard !isGuest else { throw LaneAPIError.decoding("Sign in to change privacy settings.") }
        let requestToken = token
        await configureAPI()
        guard token == requestToken else { throw CancellationError() }
        let result = try await LaneAPI.shared.updatePrivacy(token: requestToken, settings: settings)
        try result.requireSuccess()
        for attempt in 0..<4 {
            guard token == requestToken else { throw CancellationError() }
            if try await loadPrivacySettings() == settings { return }
            if attempt < 3 { try await Task.sleep(nanoseconds: 350_000_000) }
        }
        throw LaneAPIError.decoding("Lane accepted the settings, but server confirmation is pending. Please refresh.")
    }

    // MARK: Search

    func loadSearchHistory() async {
        guard !isGuest else { return }
        searchHistoryIsLoading = true
        defer { searchHistoryIsLoading = false }

        do {
            await configureAPI()
            let result = try await LaneAPI.shared.searchHistory(token: token)
            guard let entries = result.json as? [[String: Any]] else {
                throw LaneAPIError.decoding("Invalid search history response")
            }

            let decoder = JSONDecoder()
            searchHistoryItems = entries.compactMap { entry in
                guard let payload = entry["data"] as? [String: Any],
                      let data = try? JSONSerialization.data(withJSONObject: payload) else {
                    return nil
                }

                let type = (entry["type"] as? String ?? "").lowercased()
                if type.contains("track") || payload["songId"] != nil {
                    guard let track = try? decoder.decode(TrackData.self, from: data),
                          let id = track.songId, !id.isEmpty else { return nil }
                    return LaneSearchHistoryItem(id: "track:\(id)", track: track, artist: nil, album: nil)
                }
                if type.contains("album") || payload["tracks"] != nil {
                    guard let album = try? decoder.decode(LaneAlbum.self, from: data),
                          let id = album.id, !id.isEmpty else { return nil }
                    return LaneSearchHistoryItem(id: "album:\(id)", track: nil, artist: nil, album: album)
                }
                guard let artist = try? decoder.decode(LaneArtist.self, from: data),
                      let id = artist.id, !id.isEmpty else { return nil }
                return LaneSearchHistoryItem(id: "artist:\(id)", track: nil, artist: artist, album: nil)
            }
            searchHistoryMessage = ""
        } catch {
            searchHistoryMessage = "Recent searches are unavailable. Try again."
            output = error.localizedDescription
        }
    }

    func bumpSearchHistoryItem(_ item: LaneSearchHistoryItem) async {
        do {
            await configureAPI()
            _ = try await LaneAPI.shared.bumpSearchHistoryItem(token: token, key: item.id)
        } catch {
            output = error.localizedDescription
        }
    }

    func deleteSearchHistoryItem(_ item: LaneSearchHistoryItem) async {
        let original = searchHistoryItems
        searchHistoryItems.removeAll { $0.id == item.id }
        do {
            await configureAPI()
            _ = try await LaneAPI.shared.deleteSearchHistoryItem(token: token, key: item.id)
        } catch {
            searchHistoryItems = original
            searchHistoryMessage = "Could not remove this search. Try again."
            output = error.localizedDescription
        }
    }

    private func clearSearchResults() {
        searchToken = nil
        searchResultItems = []
        searchTracks = []
        searchArtists = []
        searchAlbums = []
        searchPlaylists = []
    }

    func search(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()

        guard !query.isEmpty else {
            searchTask = nil
            searchIsLoading = false
            searchMessage = ""
            clearSearchResults()
            return
        }

        guard !isGuest else {
            searchTask = nil
            searchIsLoading = false
            searchMessage = "Sign in with Telegram to search."
            clearSearchResults()
            return
        }

        searchIsLoading = true
        searchMessage = ""

        // The APK debounces text input and uses one cancellable
        // /platforms/search?q=...&platform=all&ver=1.0 request. Avoid stale
        // responses and the old multi-version probing loop.
        searchTask = Task {
            defer {
                if !Task.isCancelled { searchIsLoading = false }
            }
            do {
                await configureAPI()
                let response = try await LaneAPI.shared.search(token: token, query: query)
                guard !Task.isCancelled else { return }

                searchToken = response.searchToken
                searchResultItems = response.results
                let searchRefID = makeSearchRefID(query: query, results: response.results)
                searchTracks = response.results.compactMap { $0.track }.map {
                    TrackCandidate($0, refID: searchRefID)
                }
                rememberResolvedTracks(searchTracks)
                searchArtists = response.results.compactMap { $0.artist }
                searchAlbums = response.results.compactMap { $0.album }
                searchPlaylists = response.results.compactMap { $0.playlist }
                status = 200
                searchMessage = response.results.isEmpty ? "Try another query." : ""
            } catch {
                guard !Task.isCancelled else { return }
                clearSearchResults()
                output = error.localizedDescription
                searchMessage = "Search is temporarily unavailable. Please try again."
            }
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

    /// Lane playlist paging has existed behind both zero-based and one-based
    /// edge implementations. Probe page 0 and page 1 (safe GETs), deduplicate,
    /// then continue from page 2. This keeps library/profile/artist-linked
    /// playlists working regardless of which regional edge is active.
    private func loadPlaylistTrackCollection(
        token requestToken: String,
        playlistId: String,
        pageSize: Int = 50
    ) async -> [TrackData]? {
        async let zeroRequest = try? LaneAPI.shared.playlistTracks(
            token: requestToken,
            playlistId: playlistId,
            page: 0,
            pageSize: pageSize
        )
        async let oneRequest = try? LaneAPI.shared.playlistTracks(
            token: requestToken,
            playlistId: playlistId,
            page: 1,
            pageSize: pageSize
        )

        let (zero, one) = await (zeroRequest, oneRequest)
        guard zero != nil || one != nil else { return nil }

        var output: [TrackData] = []
        var seen = Set<String>()

        func key(for track: TrackData) -> String {
            track.songId ?? "\(track.title ?? "")|\(track.artistsDisplayedName ?? "")|\(track.duration ?? "")"
        }

        func appendUnique(_ tracks: [TrackData]) {
            for track in tracks {
                if seen.insert(key(for: track)).inserted {
                    output.append(track)
                }
            }
        }

        if let zero, !zero.items.isEmpty {
            appendUnique(zero.items)
        }
        if let one, !one.items.isEmpty {
            appendUnique(one.items)
        }

        let expectedTotal = [zero?.totalItems, one?.totalItems]
            .compactMap { $0 }
            .max()

        if output.isEmpty {
            if expectedTotal == 0 { return [] }
            return nil
        }

        if let expectedTotal, Int64(output.count) >= expectedTotal {
            return output
        }

        var pageNumber = 2
        while pageNumber < 200 {
            guard token == requestToken else { return nil }
            guard let next = try? await LaneAPI.shared.playlistTracks(
                token: requestToken,
                playlistId: playlistId,
                page: pageNumber,
                pageSize: pageSize
            ) else {
                break
            }

            if next.items.isEmpty { break }
            let before = output.count
            appendUnique(next.items)
            if output.count == before { break }

            if let expectedTotal, Int64(output.count) >= expectedTotal { break }
            if expectedTotal == nil && next.items.count < pageSize { break }
            pageNumber += 1
        }

        return output
    }

    private func mergedPlaylist(
        summary: LanePlaylist,
        detail: LanePlaylist?,
        loadedTracks: [TrackData]?
    ) -> LanePlaylist {
        let detailTrackIDs = detail?.playlistTracksIds
        let detailTracks = detail?.playlistTracks
        let loadedTrackIDs = loadedTracks?.compactMap(\.songId)
        let resolvedIDs = [loadedTrackIDs, detailTrackIDs, summary.playlistTracksIds]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        let resolvedTracks = [loadedTracks, detailTracks, summary.playlistTracks]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        let resolvedCount = [
            summary.effectiveTrackCount,
            detail?.effectiveTrackCount ?? 0,
            loadedTracks?.count ?? 0,
            resolvedIDs?.count ?? 0,
            resolvedTracks?.count ?? 0
        ].max() ?? 0

        return LanePlaylist(
            playlistId: detail?.playlistId ?? summary.playlistId,
            playlistImageUrl: detail?.playlistImageUrl ?? summary.playlistImageUrl,
            playlistName: detail?.playlistName ?? summary.playlistName,
            playlistDescription: detail?.playlistDescription ?? summary.playlistDescription,
            playlistTracksIds: resolvedIDs,
            playlistTracks: resolvedTracks,
            creatorLid: detail?.creatorLid ?? summary.creatorLid,
            platform: detail?.platform ?? summary.platform,
            tracksCount: resolvedCount,
            visibility: detail?.visibility ?? summary.visibility,
            collaboratorIds: detail?.collaboratorIds ?? summary.collaboratorIds
        )
    }

    /// `/user/playlists` is a summary endpoint and some regional deployments
    /// currently serialize every `tracksCount` as zero. Hydrate only those
    /// suspicious summaries from the same detail/paging APIs used by the
    /// playlist screen, in parallel, then publish the corrected counts.
    private func hydrateLibraryPlaylistMetadata(
        _ playlists: [LanePlaylist],
        token requestToken: String
    ) async -> [String: LanePlaylist] {
        let targets = playlists.filter {
            $0.playlistId != "lane_likes" && $0.effectiveTrackCount == 0
        }
        guard !targets.isEmpty else { return [:] }

        return await withTaskGroup(
            of: (String, LanePlaylist)?.self,
            returning: [String: LanePlaylist].self
        ) { group in
            for summary in targets {
                guard let playlistID = summary.playlistId, !playlistID.isEmpty else { continue }
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    async let detailRequest = try? LaneAPI.shared.playlist(
                        token: requestToken,
                        playlistId: playlistID,
                        platform: summary.platform
                    )
                    async let tracksRequest = self.loadPlaylistTrackCollection(
                        token: requestToken,
                        playlistId: playlistID,
                        pageSize: 100
                    )
                    let (detail, tracks) = await (detailRequest, tracksRequest)
                    return (
                        playlistID,
                        await self.mergedPlaylist(
                            summary: summary,
                            detail: detail,
                            loadedTracks: tracks
                        )
                    )
                }
            }

            var hydrated: [String: LanePlaylist] = [:]
            for await item in group {
                if let (playlistID, playlist) = item {
                    hydrated[playlistID] = playlist
                }
            }
            return hydrated
        }
    }

    private func loadLibrary() async {
        guard !isGuest else { return }

        let requestToken = token
        let loadGeneration = UUID()
        libraryLoadGeneration = loadGeneration
        await configureAPI()
        guard token == requestToken, libraryLoadGeneration == loadGeneration else { return }
        async let playlistsRequest = try? LaneAPI.shared.userPlaylists(token: requestToken)
        async let albumsRequest = try? LaneAPI.shared.userAlbums(token: requestToken)
        async let artistsRequest = try? LaneAPI.shared.userArtists(token: requestToken)
        async let recentRequest = try? LaneAPI.shared.recentRaw(token: requestToken)

        let (playlists, albums, artists, recent) = await (
            playlistsRequest,
            albumsRequest,
            artistsRequest,
            recentRequest
        )
        guard token == requestToken, libraryLoadGeneration == loadGeneration else { return }

        var effectivePlaylists = playlists ?? []
        if effectivePlaylists.isEmpty {
            var libraryAccount = account
            if libraryAccount?.userPlaylists == nil {
                let language = Locale.current.language.languageCode?.identifier ?? "en"
                libraryAccount = try? await LaneAPI.shared.account(
                    token: requestToken,
                    deviceLanguage: language
                )
            }

            if let ids = libraryAccount?.userPlaylists?.filter({ !$0.isEmpty }), !ids.isEmpty {
                let recovered = await withTaskGroup(of: LanePlaylist?.self) { group in
                    for id in ids {
                        group.addTask {
                            try? await LaneAPI.shared.playlist(
                                token: requestToken,
                                playlistId: id
                            )
                        }
                    }

                    var byID: [String: LanePlaylist] = [:]
                    for await item in group {
                        if let item, let id = item.playlistId {
                            byID[id] = item
                        }
                    }
                    return ids.compactMap { byID[$0] }
                }
                guard token == requestToken, libraryLoadGeneration == loadGeneration else { return }
                effectivePlaylists = recovered
            }
        }

        if playlists == nil && effectivePlaylists.isEmpty {
            effectivePlaylists = serverPlaylists
        }

        do {
            let playlists = effectivePlaylists
            let fetchedIDs = Set(playlists.compactMap(\.playlistId))
            let confirmedPendingIDs = pendingSavedPlaylists.keys.filter { fetchedIDs.contains($0) }
            for id in confirmedPendingIDs {
                pendingSavedPlaylists.removeValue(forKey: id)
            }
            let confirmedRemovals = pendingRemovedPlaylistIDs.filter { !fetchedIDs.contains($0) }
            pendingRemovedPlaylistIDs.subtract(confirmedRemovals)

            let pending = pendingSavedPlaylists
                .filter { !fetchedIDs.contains($0.key) && !pendingRemovedPlaylistIDs.contains($0.key) }
                .map { $0.value }
            let visiblePlaylists = playlists.filter {
                guard let id = $0.playlistId else { return true }
                return !pendingRemovedPlaylistIDs.contains(id)
            }
            serverPlaylists = visiblePlaylists + pending

            let hydrated = await hydrateLibraryPlaylistMetadata(
                serverPlaylists,
                token: requestToken
            )
            guard token == requestToken, libraryLoadGeneration == loadGeneration else { return }
            if !hydrated.isEmpty {
                serverPlaylists = serverPlaylists.map { playlist in
                    guard let id = playlist.playlistId,
                          let resolved = hydrated[id],
                          resolved.effectiveTrackCount >= playlist.effectiveTrackCount else {
                        return playlist
                    }
                    return resolved
                }
            }

            let likedPlaylist = serverPlaylists.first(where: { $0.playlistId == "lane_likes" })
            async let directLikedRequest = loadPlaylistTrackCollection(
                token: requestToken,
                playlistId: "lane_likes",
                pageSize: 100
            )
            async let likedDetailRequest = try? LaneAPI.shared.playlist(
                token: requestToken,
                playlistId: "lane_likes"
            )
            let (directLikedData, likedDetail) = await (directLikedRequest, likedDetailRequest)
            guard token == requestToken, libraryLoadGeneration == loadGeneration else { return }

            // A regional paging endpoint may temporarily return an empty page
            // while /user/playlists or /playlist/lane_likes already contains
            // the real IDs (this is also how the APK obtains liked songs).
            // Merge every available representation instead of allowing that
            // empty page or a stale tracksCount=0 to erase server-side likes.
            var likedIDsBuffer: [String] = []
            var likedIDSet = Set<String>()
            func appendLikedIDs(_ ids: [String]?) {
                for id in ids ?? [] where !id.isEmpty && likedIDSet.insert(id).inserted {
                    likedIDsBuffer.append(id)
                }
            }
            // /playlist/reorder stores its order in playlistTracksIds. Paging
            // can still return a creation-date order: use it for missing
            // metadata/membership, not to overwrite the explicit saved order.
            appendLikedIDs(likedDetail?.playlistTracksIds)
            appendLikedIDs(likedDetail?.playlistTracks?.compactMap(\.songId))
            appendLikedIDs(likedPlaylist?.playlistTracksIds)
            appendLikedIDs(likedPlaylist?.playlistTracks?.compactMap(\.songId))
            appendLikedIDs(directLikedData?.compactMap(\.songId))

            let didReadLikedState = directLikedData != nil || likedDetail != nil || likedPlaylist != nil
            let expectedLikedCount = max(
                likedDetail?.effectiveTrackCount ?? 0,
                likedPlaylist?.effectiveTrackCount ?? 0
            )
            let likedIDs: [String]? = expectedLikedCount > likedIDsBuffer.count && likedIDsBuffer.isEmpty
                ? nil
                : (didReadLikedState ? preferredPlaylistOrder(likedIDsBuffer, playlistID: "lane_likes") : nil)

            if let likedIDs {
                let serverIDs = Set(likedIDs)
                let isCompleteLikedRead = expectedLikedCount <= serverIDs.count
                let confirmedPendingIDs = pendingFavoriteStates.compactMap { id, desired in
                    let confirmed = desired ? serverIDs.contains(id) : (isCompleteLikedRead && !serverIDs.contains(id))
                    return confirmed ? id : nil
                }
                for id in confirmedPendingIDs {
                    pendingFavoriteStates.removeValue(forKey: id)
                }
                let needsMigration = !UserDefaults.standard.bool(forKey: favoriteMigrationKey)
                let legacyIDs: Set<String> = needsMigration
                    ? Set(favorites.subtracting(serverIDs).filter {
                        !$0.isEmpty && !$0.contains("|") && $0.count < 200
                    })
                    : []
                let pendingMigration = favoriteMigrationInProgress
                    ? favorites.subtracting(serverIDs)
                    : Set(legacyIDs)
                let readFavorites = isCompleteLikedRead ? serverIDs : serverIDs.union(favorites)
                var reconciledFavorites = readFavorites
                    .subtracting(favoriteMutationsInFlight)
                    .union(favorites.intersection(favoriteMutationsInFlight))
                    .union(pendingMigration)
                for (id, shouldBeLiked) in pendingFavoriteStates {
                    if shouldBeLiked {
                        reconciledFavorites.insert(id)
                    } else {
                        reconciledFavorites.remove(id)
                    }
                }
                favorites = reconciledFavorites

                let previousLikedTracks = likedTracks
                var embeddedLikedData: [TrackData] = []
                var embeddedLikedIDs = Set<String>()
                for track in (directLikedData ?? []) +
                    (likedDetail?.playlistTracks ?? []) +
                    (likedPlaylist?.playlistTracks ?? []) {
                    let key = track.songId ?? "\(track.title ?? "")|\(track.artistsDisplayedName ?? "")"
                    if embeddedLikedIDs.insert(key).inserted {
                        embeddedLikedData.append(track)
                    }
                }

                let missingMetadata = likedIDs.filter { !embeddedLikedIDs.contains($0) }
                let resolved = missingMetadata.isEmpty ? [] : await resolveTracksByIDs(
                        missingMetadata,
                        prefetch: false,
                        refID: "lane_likes"
                    )
                // Resolving metadata suspends this read. A like may already
                // have been committed/confirmed meanwhile, so pending state
                // alone cannot protect the new row from this older snapshot.
                guard token == requestToken, libraryLoadGeneration == loadGeneration else { return }
                let loadedLikedTracks = LaneTrackBatching.ordered(
                    embeddedLikedData.map { TrackCandidate($0, refID: "lane_likes") } + resolved,
                    sourceIDs: likedIDs
                )
                likedTracks = loadedLikedTracks
                rememberResolvedTracks(loadedLikedTracks)
                if !isCompleteLikedRead {
                    let loadedIDs = Set(likedTracks.compactMap(\.trackID))
                    likedTracks.append(contentsOf: previousLikedTracks.filter {
                        $0.trackID.map { favorites.contains($0) && !loadedIDs.contains($0) } ?? false
                    })
                }

                for (id, shouldBeLiked) in pendingFavoriteStates {
                    if shouldBeLiked {
                        guard !likedTracks.contains(where: { $0.trackID == id }),
                              let pendingTrack = previousLikedTracks.first(where: { $0.trackID == id })
                                ?? resolvedTrackCache[id]
                                ?? localTrackStore[id] else {
                            continue
                        }
                        likedTracks.insert(pendingTrack, at: 0)
                    } else {
                        likedTracks.removeAll { $0.trackID == id }
                    }
                }
                // A partial regional response retains missing cached rows.
                // Order the complete visible merge, not just the returned IDs,
                // otherwise retained songs get incorrectly appended at the end.
                likedTracks = LaneTrackBatching.ordered(likedTracks,
                    sourceIDs: preferredPlaylistOrder(likedTracks.compactMap(\.trackID), playlistID: "lane_likes"))

                if needsMigration, !favoriteMigrationInProgress, !legacyIDs.isEmpty {
                    favoriteMigrationInProgress = true
                    Task { @MainActor in
                        await migrateLegacyFavorites(Array(legacyIDs), token: requestToken)
                    }
                } else if needsMigration, legacyIDs.isEmpty, !favoriteMigrationInProgress {
                    UserDefaults.standard.set(true, forKey: favoriteMigrationKey)
                }
                persistFavoriteState()
            }
        }
        guard token == requestToken, libraryLoadGeneration == loadGeneration else { return }
        if let albums { serverAlbums = albums }
        if let artists { serverArtists = artists }

        if let recent {
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
                    artistAvatars: track.artistAvatars,
                    artistIDs: track.artistIDs
                )
            }
            rememberResolvedTracks(recentTracks)
        }

        retryPendingFavoriteMutations(token: requestToken)
    }

    private func rememberPlaylistTracks(_ tracks: [TrackCandidate], playlistID: String) {
        guard !tracks.isEmpty else { return }
        playlistTrackCache[playlistID] = tracks
        rememberResolvedTracks(tracks)
        playlistLoadMessages[playlistID] = nil
        if playlistTrackCache.count > 64, let oldest = playlistTrackCache.keys.first {
            playlistTrackCache.removeValue(forKey: oldest)
        }
        if let data = try? JSONEncoder().encode(playlistTrackCache) {
            UserDefaults.standard.set(data, forKey: "lane.cachedPlaylistTracks")
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

        let cached = playlistTrackCache[id]
        if let cached, !cached.isEmpty {
            completion(LaneTrackBatching.ordered(cached,
                sourceIDs: preferredPlaylistOrder(cached.compactMap(\.trackID), playlistID: id)))
        }

        Task { @MainActor in
            let requestToken = token
            let loadGeneration = playlistContentGenerations[id]
            await configureAPI()

            async let detailsRequest = try? LaneAPI.shared.playlist(
                token: requestToken,
                playlistId: id,
                platform: playlist.platform
            )
            async let tracksRequest = loadPlaylistTrackCollection(
                token: requestToken,
                playlistId: id,
                pageSize: 50
            )

            let pageItems = await tracksRequest
            guard token == requestToken, playlistContentGenerations[id] == loadGeneration,
                  !clearingPlaylistIDs.contains(id) else { return }
            if let pageItems, !pageItems.isEmpty {
                let detail = await detailsRequest
                guard token == requestToken, playlistContentGenerations[id] == loadGeneration,
                      !clearingPlaylistIDs.contains(id) else { return }
                let loaded = LaneTrackBatching.ordered(pageItems.map { TrackCandidate($0, refID: id) },
                    sourceIDs: preferredPlaylistOrder(
                        LaneTrackBatching.unique((detail?.playlistTracksIds ?? []) + pageItems.compactMap(\.songId)), playlistID: id))
                rememberPlaylistTracks(loaded, playlistID: id)
                completion(loaded)
                return
            }

            let details = await detailsRequest
            guard token == requestToken, playlistContentGenerations[id] == loadGeneration,
                  !clearingPlaylistIDs.contains(id) else { return }
            if details?.playlistTracksIds?.isEmpty == true,
               (details?.playlistTracks ?? []).isEmpty,
               details?.tracksCount == 0 || cached?.isEmpty == true {
                playlistTrackCache[id] = []
                playlistLoadMessages[id] = nil
                completion([])
                return
            }
            let libraryCopy = serverPlaylists.first { $0.playlistId == id }
            let embedded = [details?.playlistTracks, libraryCopy?.playlistTracks, playlist.playlistTracks]
                .compactMap { $0 }
                .first { !$0.isEmpty }
            if let embedded {
                let members = LaneTrackBatching.unique((details?.playlistTracksIds ?? []) + embedded.compactMap(\.songId))
                let loaded = LaneTrackBatching.ordered(embedded.map { TrackCandidate($0, refID: id) },
                    sourceIDs: preferredPlaylistOrder(members, playlistID: id))
                rememberPlaylistTracks(loaded, playlistID: id)
                completion(loaded)
                return
            }

            // Match Android's offline/server fallback: resolve the playlist's
            // IDs through the read-only POST /user/tracks in resilient pages.
            let sourceIDs = [details?.playlistTracksIds, libraryCopy?.playlistTracksIds, playlist.playlistTracksIds]
                .compactMap { $0 }
                .first { !$0.isEmpty } ?? []
            let ids = preferredPlaylistOrder(sourceIDs, playlistID: id)
            guard !ids.isEmpty else {
                // A regional page may report zero while the detail metadata
                // knows this playlist has tracks. Keep the existing cache and
                // show a retry state rather than erasing the user's list.
                let counts = [details?.tracksCount, libraryCopy?.tracksCount, playlist.tracksCount]
                    .compactMap { $0 }
                let hasTracksAccordingToMetadata = counts.contains { $0 > 0 }
                let isKnownEmpty = !hasTracksAccordingToMetadata &&
                    (pageItems?.isEmpty == true || counts.contains(0))
                if isKnownEmpty {
                    playlistTrackCache.removeValue(forKey: id)
                    if let data = try? JSONEncoder().encode(playlistTrackCache) {
                        UserDefaults.standard.set(data, forKey: "lane.cachedPlaylistTracks")
                    }
                    playlistLoadMessages[id] = nil
                    completion([])
                } else {
                    playlistLoadMessages[id] = "Tracks could not be loaded. Try again."
                    if cached == nil { completion([]) }
                }
                return
            }

            var loaded: [TrackData] = []
            for start in stride(from: 0, to: ids.count, by: 15) {
                let end = min(start + 15, ids.count)
                if let batch = try? await resolveTrackDataResilient(
                    Array(ids[start..<end]),
                    prefetch: false
                ) {
                    loaded.append(contentsOf: batch)
                }
            }

            let ordered = LaneTrackBatching.ordered(loaded.map { TrackCandidate($0) }, sourceIDs: ids)
            guard token == requestToken, playlistContentGenerations[id] == loadGeneration,
                  !clearingPlaylistIDs.contains(id) else { return }
            if ordered.isEmpty {
                playlistLoadMessages[id] = "Lane could not resolve the tracks in this playlist. Try again."
                if cached == nil { completion([]) }
            } else {
                let tracks = applyingRefID(id, to: ordered)
                rememberPlaylistTracks(tracks, playlistID: id)
                completion(tracks)
            }
        }
    }

    @discardableResult
    func createServerPlaylist(
        name: String,
        description: String = "",
        trackIDs: [String] = []
    ) async throws -> LanePlaylist {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isGuest else { throw LaneAPIError.decoding("Sign in and enter a playlist name") }

        busy = true
        defer { busy = false }
        if account == nil { await loadAccount() }
        guard let creator = account?.laneId, !creator.isEmpty else {
            throw LaneAPIError.decoding("Lane account ID is unavailable")
        }
        await configureAPI()
        let previousIDs = Set(serverPlaylists.compactMap(\.playlistId))
        let result = try await LaneAPI.shared.createPlaylist(
            token: token,
            imageURL: "",
            name: clean,
            description: description,
            tracks: trackIDs,
            creatorLid: creator
        )
        status = result.status
        try result.requireSuccess()

        func playlistID(in value: Any?) -> String? {
            if let dictionary = value as? [String: Any] {
                if let id = dictionary["playlistId"] as? String, !id.isEmpty { return id }
                for child in dictionary.values {
                    if let id = playlistID(in: child) { return id }
                }
            } else if let array = value as? [Any] {
                for child in array {
                    if let id = playlistID(in: child) { return id }
                }
            }
            return nil
        }

        var createdID = playlistID(in: result.json)
        if createdID == nil {
            // Some Lane regions acknowledge the write before returning its ID.
            // Poll the read model briefly, excluding playlists that existed
            // before this mutation so duplicate names remain safe.
            for attempt in 0..<5 {
                if let playlists = try? await LaneAPI.shared.userPlaylists(token: token),
                   let created = playlists.first(where: {
                       $0.playlistName == clean &&
                       $0.creatorLid == creator &&
                       !previousIDs.contains($0.playlistId ?? "")
                   }),
                   let id = created.playlistId,
                   !id.isEmpty {
                    createdID = id
                    break
                }
                if attempt < 4 {
                    try await Task.sleep(nanoseconds: 350_000_000)
                }
            }
        }

        guard let createdID, !createdID.isEmpty else {
            throw LaneAPIError.decoding("Lane created the playlist but did not return its ID")
        }

        let created = LanePlaylist(
            playlistId: createdID,
            playlistImageUrl: nil,
            playlistName: clean,
            playlistDescription: description,
            playlistTracksIds: trackIDs,
            playlistTracks: nil,
            creatorLid: creator,
            platform: "lane",
            tracksCount: trackIDs.count,
            visibility: "public",
            collaboratorIds: []
        )
        pendingSavedPlaylists[createdID] = created
        serverPlaylists.removeAll { $0.playlistId == createdID }
        serverPlaylists.insert(created, at: 0)
        output = "Created playlist \(clean)."
        return created
    }

    func deleteServerPlaylist(_ playlist: LanePlaylist) async throws {
        guard let id = playlist.playlistId else { throw LaneAPIError.invalidURL }
        await configureAPI()
        let result = try await LaneAPI.shared.deletePlaylist(token: token, playlistId: id)
        status = result.status
        try result.requireSuccess()

        pendingSavedPlaylists.removeValue(forKey: id)
        pendingRemovedPlaylistIDs.insert(id)
        serverPlaylists.removeAll { $0.playlistId == id }
        playlistTrackCache.removeValue(forKey: id)
        output = "Removed \(playlist.playlistName ?? "playlist") from Library."

        await loadLibrary()
    }

    func editServerPlaylist(
        _ playlist: LanePlaylist,
        name: String,
        description: String
    ) async throws {
        guard let id = playlist.playlistId else { throw LaneAPIError.invalidURL }
        await configureAPI()
        let result = try await LaneAPI.shared.editPlaylist(
            token: token,
            playlistId: id,
            imageURL: playlist.playlistImageUrl ?? "",
            name: name,
            description: description
        )
        status = result.status
        try result.requireSuccess()
        output = result.pretty
        await loadLibrary()
    }

    func setPlaylistVisibility(_ playlist: LanePlaylist, visibility: String) async throws {
        guard let id = playlist.playlistId else { throw LaneAPIError.invalidURL }
        await configureAPI()
        let result = try await LaneAPI.shared.setPlaylistVisibility(
            token: token,
            playlistId: id,
            visibility: visibility
        )
        status = result.status
        try result.requireSuccess()
        output = result.pretty
        await loadLibrary()
    }

    func savePlaylistToLibrary(_ playlist: LanePlaylist) async throws {
        guard let id = playlist.playlistId, !id.isEmpty else { throw LaneAPIError.invalidURL }

        let previous = serverPlaylists
        pendingRemovedPlaylistIDs.remove(id)
        pendingSavedPlaylists[id] = playlist
        if !serverPlaylists.contains(where: { $0.playlistId == id }) {
            serverPlaylists.append(playlist)
        }

        do {
            await configureAPI()
            // Exact APK contract: GET /user/playlist/add?playlistId=...
            let result = try await LaneAPI.shared.addPlaylistToLibrary(token: token, playlistId: id)
            status = result.status
            try result.requireSuccess()
            output = "Added \(playlist.playlistName ?? "playlist") to Library."

            // The server can be eventually consistent. Keep the optimistic
            // card visible and reconcile asynchronously instead of blocking
            // the save action on a full Library + likes refresh.
            Task { @MainActor in
                await loadLibrary()
            }
        } catch {
            pendingSavedPlaylists.removeValue(forKey: id)
            serverPlaylists = previous
            output = "Could not add playlist to Library: \(error.localizedDescription)"
            throw error
        }
    }

    func isArtistSaved(_ artist: LaneArtist) -> Bool {
        guard let id = artist.id else { return false }
        return serverArtists.contains { $0.id == id }
    }

    func isAlbumSaved(_ album: LaneAlbum) -> Bool {
        guard let id = album.id else { return false }
        return serverAlbums.contains { $0.id == id }
    }

    func setArtistSaved(_ artist: LaneArtist, saved: Bool) async throws {
        guard let id = artist.id, !id.isEmpty else { throw LaneAPIError.invalidURL }
        let previous = serverArtists
        if saved {
            if !serverArtists.contains(where: { $0.id == id }) { serverArtists.append(artist) }
        } else {
            serverArtists.removeAll { $0.id == id }
        }

        do {
            await configureAPI()
            let result = saved
                ? try await LaneAPI.shared.subscribeArtist(token: token, artistId: id)
                : try await LaneAPI.shared.unsubscribeArtist(token: token, artistId: id)
            status = result.status
            try result.requireSuccess()
            output = saved ? "Artist added to Library." : "Artist removed from Library."
        } catch {
            serverArtists = previous
            throw error
        }
    }

    func setAlbumSaved(_ album: LaneAlbum, saved: Bool) async throws {
        guard let id = album.id, !id.isEmpty else { throw LaneAPIError.invalidURL }
        let previous = serverAlbums
        if saved {
            if !serverAlbums.contains(where: { $0.id == id }) { serverAlbums.append(album) }
        } else {
            serverAlbums.removeAll { $0.id == id }
        }

        do {
            await configureAPI()
            let result = saved
                ? try await LaneAPI.shared.subscribeAlbum(token: token, albumId: id)
                : try await LaneAPI.shared.unsubscribeAlbum(token: token, albumId: id)
            status = result.status
            try result.requireSuccess()
            output = saved ? "Album added to Library." : "Album removed from Library."
        } catch {
            serverAlbums = previous
            throw error
        }
    }

    func sharePlaylist(_ playlist: LanePlaylist) async throws -> URL {
        guard let id = playlist.playlistId else { throw LaneAPIError.invalidURL }
        await configureAPI()
        let share = try await LaneAPI.shared.createShareLink(
            token: token,
            elementId: id,
            type: "playlist"
        )
        guard let url = URL(string: "https://music.sk-lane.com/\(share.id)") else {
            throw LaneAPIError.invalidURL
        }
        return url
    }

    func shareTrack(_ track: TrackCandidate) async throws -> URL {
        guard let id = track.trackID, !id.isEmpty else { throw LaneAPIError.invalidURL }
        await configureAPI()
        let share = try await LaneAPI.shared.createShareLink(
            token: token,
            elementId: id,
            type: "track"
        )
        guard let url = URL(string: "https://music.sk-lane.com/\(share.id)") else {
            throw LaneAPIError.invalidURL
        }
        return url
    }

    func setStatusTrack(_ track: TrackCandidate) async throws {
        guard let id = track.trackID, !id.isEmpty else { throw LaneAPIError.invalidURL }
        await configureAPI()
        let result = try await LaneAPI.shared.setStatusTrack(token: token, trackId: id)
        status = result.status
        output = result.pretty
    }

    func searchPlaylistInviteUsers(_ query: String) async throws -> [UserInfoDTO] {
        await configureAPI()
        return try await LaneAPI.shared.userSearch(token: token, query: query)
    }

    func invitePlaylistUsers(_ userIds: [String], to playlist: LanePlaylist) async throws {
        guard let id = playlist.playlistId, !userIds.isEmpty else {
            throw LaneAPIError.invalidURL
        }
        await configureAPI()
        let result = try await LaneAPI.shared.invitePlaylistUsers(
            token: token,
            playlistId: id,
            userIds: userIds
        )
        status = result.status
        output = result.pretty
    }

    func reorderPlaylistTracks(_ tracks: [TrackCandidate], in playlist: LanePlaylist) async throws {
        guard let playlistID = playlist.playlistId, !playlistID.isEmpty else {
            throw LaneAPIError.invalidURL
        }
        let ids = tracks.compactMap(\.trackID)
        guard ids.count == tracks.count else {
            throw LaneAPIError.decoding("One or more tracks have no Lane ID")
        }

        let previous = playlistTrackCache[playlistID]
        playlistContentGenerations[playlistID] = UUID()
        rememberPlaylistTracks(tracks, playlistID: playlistID)

        do {
            await configureAPI()
            let result = try await LaneAPI.shared.reorderPlaylist(
                token: token,
                playlistId: playlistID,
                newOrder: ids
            )
            status = result.status
            try result.requireSuccess()
            UserDefaults.standard.removeObject(forKey: playlistOrderPreferenceKey(playlistID))
            output = "Playlist order updated."
        } catch {
            if let previous {
                rememberPlaylistTracks(previous, playlistID: playlistID)
            }
            throw error
        }
    }

    func clearPlaylistTracks(_ playlist: LanePlaylist,
                             progress: @escaping (Int, Int) -> Void = { _, _ in }) async throws {
        guard let id = playlist.playlistId, !id.isEmpty, !isGuest,
              id == "lane_likes" || (playlist.creatorLid != nil && playlist.creatorLid == account?.laneId) else {
            throw LaneAPIError.decoding("Only your own playlist or liked tracks can be cleared.")
        }
        guard !importingPlaylistIDs.contains(id) else {
            throw LaneAPIError.decoding("Wait for the current import before clearing this playlist.")
        }
        guard clearingPlaylistIDs.insert(id).inserted else { return }
        cancelledPlaylistClears.remove(id)
        defer { clearingPlaylistIDs.remove(id); playlistClearStages.removeValue(forKey: id); cancelledPlaylistClears.remove(id) }
        libraryLoadGeneration = UUID()
        playlistContentGenerations[id] = UUID()
        let requestToken = token
        await configureAPI()
        guard token == requestToken else { throw CancellationError() }
        if id == "lane_likes" {
            // Let existing single-track writes finish before reading the exact
            // deletion set. New writes are blocked for the duration of clearing.
            for _ in 0..<100 where !favoriteMutationsInFlight.isEmpty {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard favoriteMutationsInFlight.isEmpty else {
                throw LaneAPIError.decoding("Likes are still syncing. Try clearing again shortly.")
            }
        }
        do {
            let removed = try await LaneAPI.shared.clearPlaylistTracks(token: requestToken, playlistId: id,
                shouldContinue: { self.token == requestToken && !self.cancelledPlaylistClears.contains(id) },
                stage: { if self.token == requestToken { self.playlistClearStages[id] = $0 } }, progress: progress)
            guard token == requestToken else { throw CancellationError() }
            libraryLoadGeneration = UUID()
            playlistContentGenerations[id] = UUID()
            playlistTrackCache[id] = []
            UserDefaults.standard.removeObject(forKey: playlistOrderPreferenceKey(id))
            if let data = try? JSONEncoder().encode(playlistTrackCache) {
                UserDefaults.standard.set(data, forKey: "lane.cachedPlaylistTracks")
            }
            if let index = serverPlaylists.firstIndex(where: { $0.playlistId == id }) {
                let value = serverPlaylists[index]
                serverPlaylists[index] = LanePlaylist(playlistId: id, playlistImageUrl: value.playlistImageUrl,
                    playlistName: value.playlistName, playlistDescription: value.playlistDescription,
                    playlistTracksIds: [], playlistTracks: [], creatorLid: value.creatorLid,
                    platform: value.platform, tracksCount: 0, visibility: value.visibility, collaboratorIds: value.collaboratorIds)
            }
            if id == "lane_likes" {
                favorites = []; likedTracks = []; pendingFavoriteStates = [:]
                persistFavoriteState()
            }
            playlistLoadMessages[id] = nil
            output = "Removed \(removed) tracks. The playlist itself was kept."
        } catch {
            if token == requestToken {
                libraryLoadGeneration = UUID()
                playlistTrackCache.removeValue(forKey: id)
                await loadLibrary()
            }
            throw error
        }
    }

    func stopClearingPlaylist(_ id: String) { cancelledPlaylistClears.insert(id) }

    func removeTrack(_ track: TrackCandidate, from playlist: LanePlaylist) async throws {
        guard let playlistID = playlist.playlistId,
              let trackID = track.trackID,
              !playlistID.isEmpty,
              !trackID.isEmpty else {
            throw LaneAPIError.invalidURL
        }

        let previous = playlistTrackCache[playlistID]
        if let previous {
            let next = previous.filter { $0.trackID != trackID }
            playlistTrackCache[playlistID] = next
            if let data = try? JSONEncoder().encode(playlistTrackCache) {
                UserDefaults.standard.set(data, forKey: "lane.cachedPlaylistTracks")
            }
        }

        do {
            await configureAPI()
            let result = try await LaneAPI.shared.removeTrack(
                token: token,
                playlistId: playlistID,
                trackId: trackID
            )
            status = result.status
            try result.requireSuccess()
            output = "Track removed from playlist."
        } catch {
            if let previous {
                rememberPlaylistTracks(previous, playlistID: playlistID)
            }
            throw error
        }
    }

    func playlistCollaborators(for playlist: LanePlaylist) async throws -> [UserInfoDTO] {
        guard let playlistID = playlist.playlistId, !playlistID.isEmpty else {
            throw LaneAPIError.invalidURL
        }
        await configureAPI()

        // The detail payload carries the same collaborator IDs used by the
        // Android collaborator screen. Resolve user cards through /user-info so
        // this remains compatible with servers that return IDs rather than full
        // user objects from the collaborators endpoint.
        let detail = try? await LaneAPI.shared.playlist(
            token: token,
            playlistId: playlistID,
            platform: playlist.platform
        )
        let ids = detail?.collaboratorIds ?? playlist.collaboratorIds ?? []
        guard !ids.isEmpty else { return [] }

        return await withTaskGroup(of: UserInfoDTO?.self) { group in
            for id in ids where id != account?.laneId {
                group.addTask {
                    try? await LaneAPI.shared.userInfo(token: self.token, laneId: id)
                }
            }

            var result: [UserInfoDTO] = []
            for await user in group {
                if let user { result.append(user) }
            }
            return result.sorted {
                ($0.displayedName ?? $0.userName ?? "") <
                ($1.displayedName ?? $1.userName ?? "")
            }
        }
    }

    func removePlaylistCollaborator(_ user: UserInfoDTO, from playlist: LanePlaylist) async throws {
        guard let playlistID = playlist.playlistId,
              let userID = user.laneId,
              !playlistID.isEmpty,
              !userID.isEmpty else {
            throw LaneAPIError.invalidURL
        }
        await configureAPI()
        let result = try await LaneAPI.shared.removePlaylistCollaborator(
            token: token,
            playlistId: playlistID,
            userId: userID
        )
        status = result.status
        try result.requireSuccess()
        output = "Collaborator removed."
    }

    private func applyConfirmedTrackIDs(_ ids: [String], to playlistID: String) {
        guard let index = serverPlaylists.firstIndex(where: { $0.playlistId == playlistID }) else { return }

        let value = serverPlaylists[index]
        var seen = Set<String>()
        let combined = ((value.playlistTracksIds ?? []) + ids)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        let updated = LanePlaylist(
            playlistId: value.playlistId,
            playlistImageUrl: value.playlistImageUrl,
            playlistName: value.playlistName,
            playlistDescription: value.playlistDescription,
            playlistTracksIds: combined,
            playlistTracks: value.playlistTracks,
            creatorLid: value.creatorLid,
            platform: value.platform,
            tracksCount: max(value.tracksCount ?? 0, combined.count),
            visibility: value.visibility,
            collaboratorIds: value.collaboratorIds
        )
        serverPlaylists[index] = updated
        if pendingSavedPlaylists[playlistID] != nil {
            pendingSavedPlaylists[playlistID] = updated
        }
    }

    func addTrack(_ track: TrackCandidate, to playlist: LanePlaylist) async throws {
        guard let playlistID = playlist.playlistId,
              let trackID = track.trackID,
              !playlistID.isEmpty,
              !trackID.isEmpty else {
            throw LaneAPIError.invalidURL
        }

        await configureAPI()
        let result = try await LaneAPI.shared.addTracks(
            token: token,
            playlistId: playlistID,
            trackIds: [trackID]
        )
        status = result.status
        try result.requireSuccess()

        applyConfirmedTrackIDs([trackID], to: playlistID)

        var cached = playlistTrackCache[playlistID] ?? []
        if !cached.contains(where: { $0.trackID == trackID }) {
            cached.append(applyingRefID(playlistID, to: [track]).first ?? track)
            rememberPlaylistTracks(cached, playlistID: playlistID)
        }
        output = "Added \(track.title) to \(playlist.playlistName ?? "playlist")."
    }

    // MARK: Music import

    func previewMusicImport(
        platform: String,
        spotifyBearerToken: String? = nil,
        spotifyClientToken: String? = nil,
        spotifyPlaylistID: String? = nil,
        soundCloudPlaylistID: String? = nil,
        yandexPlaylistID: String? = nil,
        soundCloudProfileURL: String? = nil
    ) async throws -> LanePlaylist {
        await configureAPI()
        // Match the APK's preview endpoint and avoid repeated source-link
        // variants. Track resolution is a separate, bounded 15-item pipeline.
        return try await LaneAPI.shared.importPreview(
            token: token,
            platform: platform,
            spotifyBearerToken: spotifyBearerToken,
            spotifyClientToken: spotifyClientToken,
            spotifyPlaylistId: spotifyPlaylistID,
            soundcloudPlaylistId: soundCloudPlaylistID,
            yandexPlaylistId: yandexPlaylistID?.trimmingCharacters(in: .whitespacesAndNewlines),
            soundcloudProfileUrl: soundCloudProfileURL
        )
    }

    func beginTelegramMusicImport() async throws -> String {
        await configureAPI()
        return try await LaneAPI.shared.telegramImportStart(token: token).code
    }

    func finishTelegramMusicImport() async throws -> LanePlaylist {
        await configureAPI()
        return try await LaneAPI.shared.telegramImportFinish(token: token)
    }

    func tracksForImportPreview(_ playlist: LanePlaylist) async throws -> [TrackCandidate] {
        // Show the first page quickly. Resolve the remaining pages during
        // import, not before enabling the button for a 1,151-track playlist.
        let unique = Array(playlist.importSourceIDs.prefix(LaneTrackBatching.batchSize))
        guard !unique.isEmpty else { return [] }

        await configureAPI()
        let tracks = try await LaneAPI.shared.tracksByIds(
            token: token,
            ids: unique,
            prefetch: false,
            useCurrentHostOnly: false
        )
        let resolved = tracks.map { TrackCandidate($0, refID: playlist.playlistId) }
        rememberResolvedTracks(resolved)
        return resolved
    }

    func tracksForLocalImport(_ playlist: LanePlaylist) async -> [TrackCandidate] {
        let ids = playlist.importSourceIDs
        guard !ids.isEmpty else {
            return (playlist.playlistTracks ?? []).map {
                TrackCandidate($0, refID: playlist.playlistId)
            }
        }

        await configureAPI()
        var loaded: [TrackData] = []

        // Resolve independently so one temporarily bad page does not discard
        // hundreds of already loaded tracks. Failed pages get one complete
        // regional retry before the partial result is returned for a resumable
        // local save.
        for start in stride(from: 0, to: ids.count, by: 15) {
            let end = min(start + 15, ids.count)
            let page = Array(ids[start..<end])
            var resolvedPage: [TrackData]?

            for attempt in 0..<2 {
                do {
                    resolvedPage = try await resolveTrackDataResilient(
                        page,
                        prefetch: false
                    )
                    break
                } catch {
                    output = "Local import page error: \(error.localizedDescription)"
                    if attempt == 0 {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                    }
                }
            }

            if let resolvedPage {
                loaded.append(contentsOf: resolvedPage)
            }
        }

        let embedded = playlist.playlistTracks ?? []
        let candidates = loaded + embedded
        let ordered = LaneTrackBatching.ordered(candidates.map { TrackCandidate($0) }, sourceIDs: ids)
        rememberResolvedTracks(ordered)
        return applyingRefID(playlist.playlistId, to: ordered)
    }

    func yandexPlaylistTracks(from source: String) async throws -> [YandexImportTrack] {
        let normalizedSource = YandexPlaylistSource.normalize(source)
        guard let pageURL = URL(string: normalizedSource) else {
            throw LaneAPIError.decoding("Invalid Yandex Music playlist link")
        }

        var pageRequest = URLRequest(url: pageURL)
        pageRequest.timeoutInterval = 25
        pageRequest.setValue(
            "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/126 Mobile Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        let (pageData, pageResponse) = try await URLSession.shared.data(for: pageRequest)
        guard let pageHTTP = pageResponse as? HTTPURLResponse,
              (200..<300).contains(pageHTTP.statusCode),
              let rawHTML = String(data: pageData, encoding: .utf8) else {
            throw LaneAPIError.decoding("Yandex Music did not return the public playlist page")
        }

        let html = rawHTML.replacingOccurrences(of: "\\\"", with: "\"")
        let resolvedURL = pageHTTP.url ?? pageURL
        let components = resolvedURL.pathComponents.filter { $0 != "/" }
        var ownerAndKind: (String, String)? = {
            guard let usersIndex = components.firstIndex(of: "users"),
                  let playlistsIndex = components.firstIndex(of: "playlists"),
                  components.indices.contains(usersIndex + 1),
                  components.indices.contains(playlistsIndex + 1) else { return nil }
            return (components[usersIndex + 1], components[playlistsIndex + 1])
        }()

        let playlistUUID: String? = {
            guard let index = components.firstIndex(of: "playlists"),
                  components.indices.contains(index + 1) else { return nil }
            return components[index + 1]
        }()
        let expression = try NSRegularExpression(pattern: #"\"uid\":([0-9]+),\"kind\":([0-9]+)"#)

        if ownerAndKind == nil, let playlistUUID, !playlistUUID.isEmpty {
            let marker = "\"playlistUuid\":\"\(playlistUUID)\""
            var cursor = html.startIndex
            while cursor < html.endIndex,
                  let markerRange = html.range(of: marker, range: cursor..<html.endIndex) {
                let windowEnd = html.index(
                    markerRange.upperBound,
                    offsetBy: 2_000,
                    limitedBy: html.endIndex
                ) ?? html.endIndex
                let window = String(html[markerRange.lowerBound..<windowEnd])
                let fullRange = NSRange(window.startIndex..<window.endIndex, in: window)
                if let match = expression.firstMatch(in: window, range: fullRange),
                   let uidRange = Range(match.range(at: 1), in: window),
                   let kindRange = Range(match.range(at: 2), in: window) {
                    ownerAndKind = (String(window[uidRange]), String(window[kindRange]))
                    break
                }
                cursor = markerRange.upperBound
            }
        }

        guard let (uid, kind) = ownerAndKind,
              let apiURL = URL(string: "https://api.music.yandex.net/users/\(uid)/playlists/\(kind)") else {
            throw LaneAPIError.decoding("Could not resolve the public Yandex Music playlist")
        }

        var apiRequest = URLRequest(url: apiURL)
        apiRequest.timeoutInterval = 45
        apiRequest.setValue("Yandex-Music-API", forHTTPHeaderField: "User-Agent")
        apiRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        let (apiData, apiResponse) = try await URLSession.shared.data(for: apiRequest)
        guard let apiHTTP = apiResponse as? HTTPURLResponse,
              (200..<300).contains(apiHTTP.statusCode) else {
            throw LaneAPIError.http(
                (apiResponse as? HTTPURLResponse)?.statusCode ?? 0,
                "Yandex Music playlist metadata is unavailable"
            )
        }

        let payload = try JSONDecoder().decode(YandexPlaylistEnvelope.self, from: apiData).result
        return payload.tracks.enumerated().compactMap { offset, entry in
            guard let track = entry.track,
                  track.available != false,
                  let id = track.id ?? entry.id,
                  let title = track.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty,
                  !title.isEmpty else { return nil }
            let cover = track.coverUri.map {
                let value = $0.replacingOccurrences(of: "%%", with: "200x200")
                return value.hasPrefix("http") ? value : "https://\(value)"
            }
            return YandexImportTrack(
                yandexID: id,
                originalIndex: entry.originalIndex ?? offset,
                title: title,
                artists: (track.artists ?? []).compactMap(\.name),
                coverURL: cover
            )
        }
    }

    @discardableResult
    func importTracks(
        _ trackIDs: [String],
        into playlistID: String,
        resolvingSourceIDs: Bool = false,
        sort: LaneMusicImportSort = .original,
        orderReference: [YandexImportTrack] = [],
        progress: @escaping (_ completed: Int, _ total: Int, _ stage: String) -> Void = { _, _, _ in },
        importedBatch: @escaping ([String]) -> Void = { _ in }
    ) async throws -> Int {
        var sourceSeen = Set<String>()
        let clean = trackIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && sourceSeen.insert($0).inserted }
        guard !clean.isEmpty else { throw LaneAPIError.emptyResponse }
        guard !playlistID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LaneAPIError.invalidURL
        }
        let requestToken = token
        guard !clearingPlaylistIDs.contains(playlistID), importingPlaylistIDs.insert(playlistID).inserted else {
            throw LaneAPIError.decoding("This playlist already has an import or deletion in progress.")
        }
        playlistImportErrors.removeValue(forKey: playlistID)
        defer { importingPlaylistIDs.remove(playlistID); playlistImportStages.removeValue(forKey: playlistID) }

        await configureAPI()
        try Task.checkCancellation()
        guard token == requestToken else { throw CancellationError() }
        playlistContentGenerations[playlistID] = UUID()
        progress(0, clean.count, "Adding \(clean.count) tracks to Lane…")
        var currentStage = "Adding \(clean.count) tracks to Lane…"
        playlistImportStages[playlistID] = currentStage
        var completed = 0
        var selectedOrderApplied = false

        let imported: Int
        do {
            imported = try await LaneAPI.shared.importTrackBatches(
                token: requestToken,
                playlistId: playlistID,
                sourceIDs: clean,
                resolveSourceIDs: resolvingSourceIDs,
                sort: sort,
                orderReference: orderReference,
                shouldContinue: { self.token == requestToken },
                stage: { stage in
                    guard self.token == requestToken else { return }
                    currentStage = stage
                    self.playlistImportStages[playlistID] = stage
                    progress(completed, clean.count, stage)
                },
                selectedOrder: { ids, metadata in
                    guard self.token == requestToken else { return }
                    self.applyPlaylistDisplayOrder(ids, metadata: metadata, playlistID: playlistID, sort: sort, serverConfirmed: false)
                    selectedOrderApplied = true
                },
                confirmedOrder: { ids, metadata in
                    guard self.token == requestToken else { return }
                    self.applyPlaylistDisplayOrder(ids, metadata: metadata, playlistID: playlistID, sort: sort, serverConfirmed: true)
                },
                progress: { processed, total, savedIDs, resolved in
                    guard self.token == requestToken else { return }
                    completed = processed
                    self.rememberResolvedTracks(resolved.map { TrackCandidate($0, refID: playlistID) })
                    self.applyConfirmedTrackIDs(savedIDs, to: playlistID)
                    importedBatch(savedIDs)
                    progress(processed, total, currentStage)
                })
        } catch {
            if token == requestToken {
                playlistImportErrors[playlistID] = error.localizedDescription
                if selectedOrderApplied, let confirmation = error as? LaneImportConfirmationError,
                   case let .order(saved, _) = confirmation,
                   let preference = playlistOrderPreference(playlistID), !preference.isServerConfirmed {
                    playlistImportErrors[playlistID] = "All \(saved) tracks are saved on Lane. Your selected order is saved on this iPhone. Lane has not confirmed this order for other devices yet. Retry the import to check synchronization; saved songs will not be added again."
                }
                playlistTrackCache.removeValue(forKey: playlistID)
                playlistContentGenerations[playlistID] = UUID()
                // An ordering failure must not hide tracks whose membership
                // the server has already confirmed (especially lane_likes).
                Task { @MainActor in await self.loadLibrary() }
            }
            throw error
        }
        guard token == requestToken else { throw CancellationError() }
        progress(clean.count, clean.count, "")
        output = "Lane confirmed \(imported) imported tracks in the playlist."
        playlistContentGenerations[playlistID] = UUID()

        // Membership has been read back by the batch coordinator. Refresh the
        // rest of Library without delaying the confirmed result.
        Task { @MainActor in
            await loadLibrary()
        }
        return imported
    }

    /// Membership has been read back in full before either callback. Selected
    /// display order and confirmed server order are deliberately separate.
    private func applyPlaylistDisplayOrder(_ ids: [String], metadata: [TrackData], playlistID: String, sort: LaneMusicImportSort, serverConfirmed: Bool) {
        let preference = LanePlaylistOrderPreference(trackIDs: ids, sort: sort, serverConfirmed: serverConfirmed)
        if let data = try? JSONEncoder().encode(preference) {
            UserDefaults.standard.set(data, forKey: playlistOrderPreferenceKey(playlistID))
        }
        libraryLoadGeneration = UUID()
        playlistContentGenerations[playlistID] = UUID()
        let candidates = metadata.map { TrackCandidate($0, refID: playlistID) } +
            (playlistTrackCache[playlistID] ?? []) + cachedTracksForIDs(ids) +
            (playlistID == "lane_likes" ? likedTracks : [])
        let memberIDs = Set(ids)
        let ordered = LaneTrackBatching.ordered(candidates, sourceIDs: ids)
            .filter { $0.trackID.map(memberIDs.contains) ?? false }
        rememberPlaylistTracks(ordered, playlistID: playlistID)
        if let index = serverPlaylists.firstIndex(where: { $0.playlistId == playlistID }) {
            let value = serverPlaylists[index]
            serverPlaylists[index] = LanePlaylist(playlistId: playlistID, playlistImageUrl: value.playlistImageUrl,
                playlistName: value.playlistName, playlistDescription: value.playlistDescription,
                playlistTracksIds: ids, playlistTracks: metadata, creatorLid: value.creatorLid,
                platform: value.platform, tracksCount: ids.count, visibility: value.visibility,
                collaboratorIds: value.collaboratorIds)
        }
        if playlistID == "lane_likes" {
            favorites = memberIDs
            for (id, desired) in pendingFavoriteStates {
                if desired { favorites.insert(id) } else { favorites.remove(id) }
            }
            likedTracks = ordered.filter { isFavorite($0) }
            restorePendingFavoriteTracks()
            persistFavoriteState()
        }
    }

    private func playlistOrderPreferenceKey(_ playlistID: String) -> String {
        // Never persist a bearer token in a preferences key. The account scope
        // is derived on every read, including direct token changes in fixtures.
        let scope = SHA256.hash(data: Data((token + "|" + playlistID).utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "lane.playlistOrder." + scope
    }

    private func playlistOrderPreference(_ playlistID: String) -> LanePlaylistOrderPreference? {
        guard !isGuest, let data = UserDefaults.standard.data(forKey: playlistOrderPreferenceKey(playlistID)) else { return nil }
        return try? JSONDecoder().decode(LanePlaylistOrderPreference.self, from: data)
    }

    private func preferredPlaylistOrder(_ membership: [String], playlistID: String) -> [String] {
        playlistOrderPreference(playlistID)?.orderedMemberIDs(membership) ?? membership
    }

    func playlistImportOrderTitle(_ playlistID: String) -> String? {
        playlistOrderPreference(playlistID)?.sort.rawValue
    }

    func playlistImportOrderIsServerConfirmed(_ playlistID: String) -> Bool {
        playlistOrderPreference(playlistID)?.isServerConfirmed ?? false
    }

    func useServerPlaylistOrder(_ playlistID: String) {
        UserDefaults.standard.removeObject(forKey: playlistOrderPreferenceKey(playlistID))
        playlistImportErrors.removeValue(forKey: playlistID)
        playlistContentGenerations[playlistID] = UUID()
        playlistTrackCache.removeValue(forKey: playlistID)
        refreshLibrary()
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
        Task {
            do {
                _ = try await setFollowingConfirmed(user, follow: follow)
                await loadFriends()
            } catch {
                output = error.localizedDescription
            }
        }
    }

    func fetchUserProfile(_ id: String) async throws -> UserInfoDTO {
        await configureAPI()
        let requestToken = token
        let value = try await LaneAPI.shared.userInfo(token: requestToken, laneId: id)
        guard token == requestToken else { throw CancellationError() }
        return value
    }

    func fetchOwnBadgeProfile() async throws -> UserInfoDTO {
        guard !isGuest else { throw LaneAPIError.decoding("Sign in to view your badges.") }
        let requestToken = token
        let generation = profileMutationGeneration
        await configureAPI()
        let value = try await LaneAPI.shared.account(token: requestToken, deviceLanguage: Locale.current.language.languageCode?.identifier ?? "en")
        guard token == requestToken, profileMutationGeneration == generation else { throw CancellationError() }
        guard let id = value.laneId, !id.isEmpty else { throw LaneAPIError.decoding("Lane did not return your profile ID.") }
        let profile = try await LaneAPI.shared.userInfo(token: requestToken, laneId: id)
        guard token == requestToken, profileMutationGeneration == generation else { throw CancellationError() }
        account = value; publicProfile = profile
        return profile
    }

    func equipBadgeConfirmed(_ badgeId: String?) async throws -> UserInfoDTO {
        let requestToken = token
        profileMutationGeneration = UUID()
        let generation = profileMutationGeneration
        let profile = try await fetchOwnBadgeProfile()
        guard token == requestToken, profileMutationGeneration == generation else { throw CancellationError() }
        guard badgeId == nil || profile.badges?.contains(where: { $0.id == badgeId }) == true else {
            throw LaneAPIError.decoding("This badge has not been earned by your account.")
        }
        try await LaneAPI.shared.equipBadge(token: requestToken, badgeId: badgeId).requireSuccess()
        guard token == requestToken, profileMutationGeneration == generation, let id = profile.laneId else { throw CancellationError() }
        for attempt in 0..<3 {
            let confirmed = try await LaneAPI.shared.userInfo(token: requestToken, laneId: id)
            guard token == requestToken, profileMutationGeneration == generation else { throw CancellationError() }
            if confirmed.equippedBadgeId == badgeId {
                publicProfile = confirmed
                return confirmed
            }
            if attempt < 2 { try await Task.sleep(nanoseconds: 500_000_000) }
        }
        throw LaneAPIError.decoding("Lane accepted the change but has not confirmed the current badge yet. Refresh to check.")
    }

    func fetchArtistCandleCount(_ id: String) async throws -> Int64 {
        let requestToken = token
        await configureAPI()
        let value = try await LaneAPI.shared.artistCandleCount(token: requestToken, artistId: id)
        guard token == requestToken else { throw CancellationError() }
        return value
    }

    func fetchArtistCandles(_ id: String, page: Int) async throws -> PaginatedResult<LaneArtistCandle> {
        let requestToken = token
        await configureAPI()
        let value = try await LaneAPI.shared.artistCandles(token: requestToken, artistId: id, page: page)
        guard token == requestToken else { throw CancellationError() }
        return value
    }

    func placeArtistCandle(_ id: String, text: String) async throws -> LaneArtistCandle {
        guard !isGuest else { throw LaneAPIError.decoding("Sign in to leave a candle.") }
        let requestToken = token
        await configureAPI()
        let value = try await LaneAPI.shared.placeArtistCandle(token: requestToken, artistId: id, text: text)
        guard token == requestToken else { throw CancellationError() }
        return value
    }

    func setFollowingConfirmed(_ user: UserInfoDTO, follow: Bool) async throws -> UserInfoDTO {
        guard !isGuest, let id = user.laneId, !id.isEmpty else { throw LaneAPIError.decoding("Sign in to follow this user.") }
        await configureAPI()
        let requestToken = token
        let result = follow ? try await LaneAPI.shared.follow(token: requestToken, userId: id)
                            : try await LaneAPI.shared.unfollow(token: requestToken, userId: id)
        try result.requireSuccess()
        for attempt in 0..<4 {
            let confirmed = try await LaneAPI.shared.userInfo(token: requestToken, laneId: id)
            guard token == requestToken else { throw CancellationError() }
            if confirmed.isFollowing == follow {
                friends = friends.map { $0.laneId == id ? confirmed : $0 }
                userSearchResults = userSearchResults.map { $0.laneId == id ? confirmed : $0 }
                return confirmed
            }
            if attempt < 3 { try await Task.sleep(nanoseconds: 350_000_000) }
        }
        throw LaneAPIError.decoding("Lane has not confirmed the subscription yet. Please refresh.")
    }

    func fetchPeople(_ id: String, following: Bool, page: Int) async throws -> PaginatedResult<UserInfoDTO> {
        await configureAPI()
        let requestToken = token
        let result = following ? try await LaneAPI.shared.following(token: requestToken, laneId: id, page: page, pageSize: 30)
                               : try await LaneAPI.shared.followers(token: requestToken, laneId: id, page: page, pageSize: 30)
        guard token == requestToken else { throw CancellationError() }
        return result
    }

    func refreshNotifications() {
        Task { await loadNotifications(reset: true) }
    }

    func refreshUnreadNotifications() async {
        guard !isGuest else { return }
        let requestToken = token
        await configureAPI()
        if let count = try? await LaneAPI.shared.notificationUnreadCount(token: requestToken), token == requestToken {
            unreadNotificationCount = count
        }
    }

    func loadNotifications(reset: Bool = false) async {
        guard !isGuest, !notificationsLoading, reset || notificationsHaveMore else { return }
        notificationsLoading = true
        notificationsError = nil
        let requestToken = token
        defer { notificationsLoading = false }
        do {
            await configureAPI()
            let page = reset ? 0 : nextNotificationPage
            let response = try await LaneAPI.shared.notificationPage(token: requestToken, page: page)
            guard token == requestToken else { return }
            let existing = reset ? [] : notifications
            var seen = Set<String>()
            notifications = (existing + response.items).filter { seen.insert($0.id).inserted }
            nextNotificationPage = page + 1
            notificationsHaveMore = response.totalPages.map { nextNotificationPage < $0 } ?? (response.items.count == 30)
            unreadNotificationCount = (try? await LaneAPI.shared.notificationUnreadCount(token: requestToken))
                ?? notifications.filter { $0.read != true }.count
            if token != requestToken { unreadNotificationCount = 0 }
        } catch {
            if token == requestToken { notificationsError = error.localizedDescription }
        }
    }

    func markNotificationRead(_ item: LaneNotification) async throws {
        guard item.read != true else { return }
        let result = try await LaneAPI.shared.markNotificationRead(token: token, id: item.id)
        try result.requireSuccess()
        if let index = notifications.firstIndex(where: { $0.id == item.id }), notifications[index].read != true {
            notifications[index].read = true
            unreadNotificationCount = max(0, unreadNotificationCount - 1)
        }
    }

    func markAllNotificationsRead() async throws {
        let result = try await LaneAPI.shared.markAllNotificationsRead(token: token)
        try result.requireSuccess()
        for index in notifications.indices { notifications[index].read = true }
        unreadNotificationCount = 0
    }

    func respondToInvitation(_ item: LaneNotification, accept: Bool) async throws {
        guard let id = item.invitationId, !id.isEmpty, notificationMutations.insert(item.id).inserted else { return }
        defer { notificationMutations.remove(item.id) }
        let result = try await LaneAPI.shared.respondToPlaylistInvitation(token: token, invitationId: id, accept: accept)
        try result.requireSuccess()
        try? await markNotificationRead(item)
        notifications.removeAll { $0.id == item.id }
        if accept { await loadLibrary() }
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
        guard let id = track.trackID, !id.isEmpty else { return }

        if currentTrack?.trackID == id, let cached = trackStatsCache[id] {
            trackStats = cached
        }

        trackStatsTask?.cancel()
        trackStatsTask = Task { [weak self] in
            guard let self else { return }
            do {
                await self.configureAPI()
                try Task.checkCancellation()
                let stats = try await LaneAPI.shared.trackStats(token: self.token, trackId: id)
                try Task.checkCancellation()

                self.trackStatsCache[id] = stats
                if let data = try? JSONEncoder().encode(self.trackStatsCache) {
                    UserDefaults.standard.set(data, forKey: "lane.cachedTrackStats")
                }

                // A slow response for the previous song must never overwrite
                // the counters for the track now shown in the full player.
                if self.currentTrack?.trackID == id {
                    self.trackStats = stats
                }
                self.output = "Likes: \(stats.likesCount)\nComments: \(stats.commentsCount)"
            } catch is CancellationError {
                return
            } catch {
                guard self.currentTrack?.trackID == id else { return }
                self.output = error.localizedDescription
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

    func startWave(from track: TrackCandidate) {
        guard let id = track.trackID, !id.isEmpty else {
            waveError = "This track has no Lane ID."
            return
        }
        waveTask?.cancel()
        let requestID = UUID()
        waveRequestID = requestID
        wavePlaylist = nil
        waveError = nil
        waveSourceCoverURL = track.coverURL
        waveIsLoading = true
        let requestToken = token
        waveTask = Task { @MainActor in
            defer { if waveRequestID == requestID { waveIsLoading = false } }
            do {
                await configureAPI()
                try Task.checkCancellation()
                let playlist = try await LaneAPI.shared.wavePlaylist(
                    token: requestToken,
                    trackId: id,
                    platform: track.platform.isEmpty ? "all" : track.platform
                )
                guard !Task.isCancelled, token == requestToken,
                      waveRequestID == requestID else { return }
                guard let playlistID = playlist.playlistId, !playlistID.isEmpty else {
                    throw LaneAPIError.decoding("Lane returned a wave without a playlist ID")
                }
                wavePlaylist = playlist
                output = "Wave ready: \(playlist.playlistName ?? playlistID)"
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, waveRequestID == requestID else { return }
                waveError = error.localizedDescription
                output = "Wave error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Player

    /// A selection from a collection replaces the playback source atomically.
    /// Navigation/library refreshes do not change the active queue afterwards.
    func startPlayback(_ track: TrackCandidate, in tracks: [TrackCandidate], at selectedIndex: Int? = nil) {
        queue = tracks.isEmpty ? [track] : tracks
        if let selectedIndex, queue.indices.contains(selectedIndex), queue[selectedIndex] == track {
            currentIndex = selectedIndex
        } else {
            currentIndex = queue.firstIndex(of: track)
        }
        if currentIndex == nil { queue = [track]; currentIndex = 0 }
        guard let currentIndex else { return }
        requestStream(for: queue[currentIndex])
    }

    private func streamCacheKey(trackID: String, refID: String?, quality: String) -> String {
        "\(trackID)|\(refID ?? "")|\(quality)"
    }

    private func streamExpiry(from ttl: Int64?) -> Date {
        guard let ttl, ttl > 0 else {
            // Keep an unannotated signed URL only briefly. This still makes
            // previous/next/replay instantaneous without risking a stale URL.
            return Date().addingTimeInterval(60)
        }

        let now = Date()
        if ttl > 10_000_000_000 {
            return Date(timeIntervalSince1970: Double(ttl) / 1000.0)
        }
        if ttl > 1_000_000_000 {
            return Date(timeIntervalSince1970: Double(ttl))
        }
        return now.addingTimeInterval(Double(ttl))
    }

    private func resolvedStream(
        trackID: String,
        refID: String?,
        quality: String,
        usePreparedStream: Bool = true
    ) async throws -> TrackStreamingResult {
        // Lane Android freezes AudioQuality for the request and keeps a
        // TrackStreamCacheManager. Cache by track + context + quality so a URL
        // resolved for BASIC can never be reused for HIGH/ULTRA (or vice versa).
        let cacheKey = streamCacheKey(trackID: trackID, refID: refID, quality: quality)
        if let cached = streamResolutionCache[cacheKey],
           cached.expiresAt.timeIntervalSinceNow > 5 {
            return cached.result
        }
        streamResolutionCache.removeValue(forKey: cacheKey)
        if usePreparedStream, nextStreamKey == cacheKey, let prepared = nextStreamTask {
            do {
                let result = try await prepared.value
                try Task.checkCancellation()
                return result
            } catch {
                // A failed speculative request must not prevent a real Play.
                try Task.checkCancellation()
            }
        }
        let requestToken = token

        // Exactly one selected quality goes to /track/stream. LaneAPI may use
        // the other official regional edge after a transport failure, but it
        // never changes streamQuality.
        var result: TrackStreamingResult
        do {
            result = try await LaneAPI.shared.stream(token: requestToken, trackId: trackID, refId: refID, quality: quality)
        } catch {
            try Task.checkCancellation()
            guard case let LaneAPIError.http(status, _) = error, [408, 500, 502, 503, 504].contains(status) else { throw error }
            // A stale playlist context or a transient provider failure must not
            // poison the player. Retry once without refId, same chosen quality.
            try await Task.sleep(nanoseconds: 400_000_000)
            result = try await LaneAPI.shared.stream(token: requestToken, trackId: trackID, refId: nil, quality: quality)
        }
        try Task.checkCancellation()
        guard token == requestToken else { throw CancellationError() }
        guard !result.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              result.trackId == nil || result.trackId == trackID else {
            // The caller's wrong-track recovery must get a fresh response.
            return result
        }
        streamResolutionCache[cacheKey] = (
            result: result,
            expiresAt: streamExpiry(from: result.ttl)
        )

        if streamResolutionCache.count > 80 {
            let now = Date()
            streamResolutionCache = streamResolutionCache.filter { $0.value.expiresAt > now }
            if streamResolutionCache.count > 80 {
                streamResolutionCache.removeValue(forKey: streamResolutionCache.keys.first!)
            }
        }
        return result
    }

    private func cancelPreparedStream() {
        nextStreamOperation = UUID()
        nextStreamTask?.cancel()
        nextStreamTask = nil
        nextStreamKey = nil
        prefetchedPlaybackRequestID = nil
    }

    /// Only prepare one signed URL, after the current audio is audible. Never
    /// download the queue, change quality, or compete with initial buffering.
    private func prepareNextStream(requestID: UUID) {
        guard playbackRequestID == requestID, prefetchedPlaybackRequestID != requestID,
              let index = currentIndex, !queue.isEmpty, repeatMode != 2 else { return }
        prefetchedPlaybackRequestID = requestID
        let next = index + 1 < queue.count ? index + 1 : (repeatMode == 1 ? 0 : -1)
        guard queue.indices.contains(next), let id = queue[next].trackID,
              !id.isEmpty, downloadedFileURL(for: queue[next]) == nil,
              (trackEffects[id] ?? .original) == .original else { return }
        let candidate = queue[next]
        let quality = selectedPlaybackQuality()
        let key = streamCacheKey(trackID: id, refID: candidate.refID, quality: quality)
        if let cached = streamResolutionCache[key], cached.expiresAt.timeIntervalSinceNow > 5 { return }
        cancelPreparedStream()
        prefetchedPlaybackRequestID = requestID
        let operation = UUID()
        nextStreamOperation = operation
        nextStreamKey = key
        nextStreamTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { throw CancellationError() }
            defer {
                if self.nextStreamOperation == operation {
                    self.nextStreamTask = nil
                    self.nextStreamKey = nil
                }
            }
            return try await self.resolvedStream(trackID: id, refID: candidate.refID,
                                                 quality: quality, usePreparedStream: false)
        }
    }

    private func endPlaybackTransition(requestID: UUID? = nil) {
        if let requestID, playbackBackgroundRequestID != requestID { return }
        playbackBackgroundLease?.end()
        playbackBackgroundLease = nil
        playbackBackgroundRequestID = nil
    }

    /// Audio background mode covers playing audio, not an arbitrary silent
    /// gap while /track/stream or the next range is being fetched. Request a
    /// bounded execution window before stopping the previous player.
    private func beginPlaybackTransition(requestID: UUID) {
        // Repeated stall notifications must not renew/reset the same finite
        // assertion or let an older expiration cancel its replacement.
        if playbackBackgroundRequestID == requestID, playbackBackgroundLease?.isActive == true { return }
        endPlaybackTransition()
        playbackBackgroundRequestID = requestID
        let lease = LaneAudioBackgroundLease()
        playbackBackgroundLease = lease
        lease.begin { [weak self] generation in
            Task { @MainActor in
                self?.playbackTransitionExpired(generation: generation)
            }
        }
    }

    private func playbackTransitionExpired(generation: UUID) {
        guard playbackBackgroundLease?.generation == generation else { return }
        playbackBackgroundLease = nil
        playbackBackgroundRequestID = nil
        recordAudioEvent("transition-expired")
        // The lease has already been ended synchronously. It is not the
        // lifetime of AVPlayer: keep ready/playing audio and buffered data.
        if player?.currentItem?.status == .readyToPlay { return }
        guard isBuffering else { return }
        streamResolveTask?.cancel()
        playbackWatchdogTask?.cancel()
        retirePlayer()
        isBuffering = false; isPlaying = false; busy = false
        playerError = "Audio loading took too long. Tap Play to retry. [BACKGROUND-TIMEOUT]"
    }

    private func recordAudioEvent(_ event: String) {
        LaneAudioDiagnostics.shared.record("\(event) app=\(UIApplication.shared.applicationState.rawValue) intent=\(playbackShouldPlay) playing=\(isPlaying) buffering=\(isBuffering) position=\(Int(playbackPosition)) buffer=\(Int(playbackBufferedDuration))")
    }

    private func configureAudioLifecycle() {
        let center = NotificationCenter.default
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereLostNotification, AVAudioSession.mediaServicesWereResetNotification,
                     UIApplication.didEnterBackgroundNotification, UIApplication.didBecomeActiveNotification,
                     UIApplication.didReceiveMemoryWarningNotification, UIApplication.willTerminateNotification] {
            audioLifecycleObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in self?.handleAudioLifecycle(notification) }
            })
        }
        _ = LaneAudioDiagnostics.shared
    }

    func fetchFriendActivity() async throws -> [LaneFriendPresence] {
        guard !isGuest else { return [] }
        let identity = token
        await configureAPI()
        let result = try await LaneAPI.shared.friendActivity(token: identity)
        guard token == identity, !Task.isCancelled else { throw CancellationError() }
        friendActivity = result.filter { !$0.laneId.isEmpty }
        return friendActivity
    }

    func fetchPricing() async throws -> LanePricing {
        let identity = token
        guard !identity.isEmpty else { throw LaneAPIError.decoding("Sign in to manage Lane Premium.") }
        await configureAPI()
        let result = try await LaneAPI.shared.pricing(token: identity)
        guard token == identity, !Task.isCancelled else { throw CancellationError() }
        return result
    }

    func cancelSubscriptionConfirmed() async throws {
        let identity = token
        guard !identity.isEmpty else { throw LaneAPIError.decoding("Sign in to manage Lane Premium.") }
        await configureAPI()
        _ = try await LaneAPI.shared.cancelSubscription(token: identity)
        let value = try await LaneAPI.shared.account(token: identity, deviceLanguage: Locale.current.language.languageCode?.identifier ?? "en")
        guard token == identity, !Task.isCancelled else { throw CancellationError() }
        account = value
        guard value.isAutoRenewalActive == false else { throw LaneAPIError.decoding("Lane accepted the request but has not confirmed cancellation yet. Refresh the subscription status.") }
    }

    private func schedulePresenceSync() {
        presenceSyncTask?.cancel()
        guard !isGuest, currentTrack?.trackID != nil else { return }
        let identity = token
        presenceSyncTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                guard let self, self.token == identity else { return }
                await self.configureAPI()
                try Task.checkCancellation()
                guard self.token == identity else { return }
                try await LaneAPI.shared.updatePresence(token: identity, trackID: self.currentTrack?.trackID,
                    positionMs: Int64(max(0, self.playbackPosition) * 1000), isPaused: !self.playbackShouldPlay || self.audioInterrupted)
            } catch { /* Social status must not fail or delay audio playback. */ }
        }
    }

    func setClientEventsActive(_ active: Bool) {
        clientEventsTask?.cancel(); clientEventsTask = nil
        clientEventsGeneration = UUID()
        guard active, !isGuest else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--lane-ui-test") { return }
        #endif
        let identity = token, operation = clientEventsGeneration
        clientEventsTask = Task { [weak self] in
            var backoff: UInt64 = 5
            while !Task.isCancelled {
                guard let self, self.token == identity, self.clientEventsGeneration == operation,
                      UIApplication.shared.applicationState != .background else { return }
                do {
                    await self.configureAPI()
                    let events = try await LaneAPI.shared.serverEvents(token: identity)
                    guard self.token == identity, self.clientEventsGeneration == operation, !Task.isCancelled else { return }
                    self.applyServerEvents(events)
                    if events.contains(where: \.refreshesFriends) { _ = try? await self.fetchFriendActivity() }
                    backoff = 5
                } catch is CancellationError { return }
                catch { backoff = min(60, backoff * 2) }
                do { try await Task.sleep(nanoseconds: backoff * 1_000_000_000) } catch { return }
            }
        }
    }

    func applyServerEvents(_ events: [LaneServerEvent]) {
        for event in events {
            if event.type == "NEW_NOTIFICATION", let notification = event.notification,
               !notifications.contains(where: { $0.id == notification.id }) {
                notifications.insert(notification, at: 0)
                if notification.read != true { unreadNotificationCount += 1 }
            }
        }
        if events.contains(where: \.refreshesAccount) { refreshAccount() }
    }

    private func activateAudioSession() throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .default, options: [])
        try audio.setActive(true)
    }

    private func handleAudioLifecycle(_ notification: Notification) {
        switch notification.name {
        case AVAudioSession.interruptionNotification:
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                interruptionResumeRequested = playbackShouldPlay
                audioInterrupted = true
                player?.pause(); isPlaying = false; isBuffering = false
                endPlaybackTransition(); updatePlaybackState(false)
                recordAudioEvent("interruption-began")
            } else {
                guard audioInterrupted else { recordAudioEvent("interruption-ended-without-begin"); return }
                let options = AVAudioSession.InterruptionOptions(rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                let shouldResume = audioInterrupted && interruptionResumeRequested && playbackShouldPlay && options.contains(.shouldResume)
                audioInterrupted = false; interruptionResumeRequested = false
                recordAudioEvent("interruption-ended resume=\(shouldResume)")
                if shouldResume { resume() }
                else { playbackShouldPlay = false; updatePlaybackState(false) }
            }
        case AVAudioSession.routeChangeNotification:
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            recordAudioEvent("route-change reason=\(reason)")
            // Removing headphones must not unexpectedly play on the speaker.
            if AVAudioSession.RouteChangeReason(rawValue: reason) == .oldDeviceUnavailable { pause() }
        case AVAudioSession.mediaServicesWereLostNotification:
            player?.pause(); isPlaying = false; isBuffering = false
            endPlaybackTransition(); updatePlaybackState(false)
            recordAudioEvent("media-services-lost")
        case AVAudioSession.mediaServicesWereResetNotification:
            // Apple's reset contract requires recreating audio objects and
            // waiting for a user play action, not automatically taking audio.
            pendingStartPosition = playbackPosition
            retirePlayer(); playbackShouldPlay = false; isPlaying = false; isBuffering = false
            streamResolveTask?.cancel(); endPlaybackTransition()
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try? AVAudioSession.sharedInstance().setActive(false)
            updatePlaybackState(false); recordAudioEvent("media-services-reset")
        case UIApplication.didBecomeActiveNotification:
            recordAudioEvent("foreground")
            if playbackShouldPlay, !audioInterrupted, player?.currentItem?.status == .readyToPlay,
               player?.timeControlStatus != .playing { resume() }
        case UIApplication.didEnterBackgroundNotification: recordAudioEvent("background")
        case UIApplication.didReceiveMemoryWarningNotification: recordAudioEvent("memory-warning")
        case UIApplication.willTerminateNotification: recordAudioEvent("will-terminate")
        default: break
        }
    }

    private func isPremiumRequired(_ error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains("PREMIUM_REQUIRED")
    }

    private func userFacingPlaybackError(_ error: Error) -> String {
        let detail = error.localizedDescription
        let code = playbackDiagnosticCode(error)
        if isPremiumRequired(error) {
            return "This quality requires Lane Premium. Choose Basic in Audio quality. [\(code)]"
        }
        if detail.localizedCaseInsensitiveContains("timed out") ||
            detail.localizedCaseInsensitiveContains("HTTP 5") ||
            detail.localizedCaseInsensitiveContains("network") {
            return "The track could not be loaded. Check your connection and try again. [\(code)]"
        }
        return "The track is temporarily unavailable. [\(code)]"
    }

    private func playbackDiagnosticCode(_ error: Error) -> String {
        if case let LaneAPIError.http(status, _) = error {
            return "STREAM-\(status)"
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return nsError.code == NSURLErrorTimedOut ? "NETWORK-TIMEOUT" : "NETWORK-\(abs(nsError.code))"
        }
        if nsError.domain == "LanePlayer" {
            return "PLAYER-\(nsError.code)"
        }
        return "STREAM-UNKNOWN"
    }

    func requestStream(for track: TrackCandidate) {
        // Every tap gets its own generation. Older resolver/download tasks are
        // ignored so a slow previous request can never start a different song.
        streamResolveTask?.cancel()
        playbackWatchdogTask?.cancel()
        let requestID = UUID()
        playbackRequestID = requestID
        beginPlaybackTransition(requestID: requestID)
        effectRequestID = UUID()
        trackEffectIsLoading = false
        trackEffectError = ""
        currentTrackEffect = track.trackID.flatMap { trackEffects[$0] } ?? .original
        playbackShouldPlay = true
        pendingStartPosition = nil
        seekingInitialPosition = false

        retirePlayer()
        isPlaying = false

        currentTrack = track
        playerError = ""
        streamURL = ""
        playbackPosition = 0
        playbackDuration = parseDuration(track.duration) ?? 0
        playbackBufferedDuration = 0
        trackStats = track.trackID.flatMap { trackStatsCache[$0] }
        currentLyrics = nil
        lyricsError = ""

        if let currentIndex,
           queue.indices.contains(currentIndex),
           queue[currentIndex] == track {
            // A queue may contain the same track more than once. The caller's
            // selected position must win over firstIndex(of:).
        } else if let index = queue.firstIndex(of: track) {
            currentIndex = index
        } else {
            // A standalone selection must never inherit Next/Previous from a
            // different playlist. Collection rows pass their queue explicitly.
            queue = [track]
            currentIndex = 0
        }

        guard let trackID = track.trackID, !trackID.isEmpty else {
            cancelPreparedStream()
            playerError = "Track has no songId"
            output = playerError
            isPlaying = false
            isBuffering = false
            endPlaybackTransition(requestID: requestID)
            return
        }

        busy = true
        isBuffering = true
        activeStreamQuality = nil
        playerRetriedWithCompatibilityHeaders = false
        playerRetriedWithLocalDownload = false
        playerRetriedWithProgressiveTransport = false

        if currentTrackEffect == .original, let localURL = downloadedFileURL(for: track) {
            cancelPreparedStream()
            do {
                streamURL = localURL.absoluteString
                try playLocalCompatibilityFile(localURL, sourceDescription: "downloaded on this iPhone", requestID: requestID, track: track)
                history.removeAll { $0.id == track.id }
                history.insert(track, at: 0)
                history = Array(history.prefix(100))
                saveHistory()
                updateNowPlaying()
            } catch {
                isBuffering = false
                playerError = error.localizedDescription
                endPlaybackTransition(requestID: requestID)
            }
            busy = false
            return
        }

        // Freeze the user's saved tier at the moment playback is requested.
        // Changing the setting while this track is loading affects only the
        // next track, exactly like Android's persisted AudioQuality flow.
        let requestedQuality = selectedPlaybackQuality()
        if nextStreamKey != streamCacheKey(trackID: trackID, refID: track.refID, quality: requestedQuality) {
            cancelPreparedStream()
        }
        prefetchedPlaybackRequestID = nil

        playbackWatchdogTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 22_000_000_000)
            } catch {
                return
            }

            guard let self,
                  self.playbackRequestID == requestID,
                  self.currentTrack?.id == track.id,
                  self.isBuffering,
                  self.streamURL.isEmpty else { return }

            self.streamResolveTask?.cancel()
            self.busy = false
            self.isBuffering = false
            self.isPlaying = false
            self.retirePlayer()
            self.endPlaybackTransition(requestID: requestID)
            self.playerError = "The track could not be loaded without VPN. Try again. [NETWORK-TIMEOUT]"
            self.output = "Playback error: stream resolution exceeded 22 seconds"
        }

        streamResolveTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.playbackRequestID == requestID {
                    self.busy = false
                    self.streamResolveTask = nil
                }
            }

            do {
                await self.configureAPI()
                try Task.checkCancellation()
                guard self.playbackRequestID == requestID,
                      self.currentTrack?.id == track.id else { return }

                var result: TrackStreamingResult
                if self.currentTrackEffect == .original {
                    result = try await self.resolvedStream(trackID: trackID, refID: track.refID, quality: requestedQuality)
                } else {
                    guard self.hasPremiumAccess else { throw LaneAPIError.decoding("Lane Premium is required for track effects") }
                    result = try await LaneAPI.shared.trackEffect(token: self.token, trackId: trackID, effect: self.currentTrackEffect)
                }

                try Task.checkCancellation()
                guard self.playbackRequestID == requestID,
                      self.currentTrack?.id == track.id else { return }

                // A contextual refId can occasionally resolve to a stale source.
                // If Lane tells us it resolved another track, retry without refId
                // and never hand the mismatched URL to AVPlayer.
                if let resolvedTrackID = result.trackId,
                   !resolvedTrackID.isEmpty,
                   resolvedTrackID != trackID {
                    guard self.currentTrackEffect == .original else {
                        throw LaneAPIError.decoding("Lane returned an effect for a different track")
                    }
                    let corrected = try await LaneAPI.shared.stream(
                        token: self.token,
                        trackId: trackID,
                        refId: nil,
                        quality: requestedQuality
                    )

                    try Task.checkCancellation()
                    guard self.playbackRequestID == requestID,
                          self.currentTrack?.id == track.id else { return }

                    if let correctedTrackID = corrected.trackId,
                       !correctedTrackID.isEmpty,
                       correctedTrackID != trackID {
                        throw NSError(
                            domain: "LanePlayer",
                            code: 409,
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    "Lane resolved a different track than the one selected."
                            ]
                        )
                    }

                    result = corrected
                }

                self.playbackWatchdogTask?.cancel()
                self.activeStreamQuality = requestedQuality
                self.streamURL = result.url
                await self.autoTuneMediaRoute(for: result.url)
                try Task.checkCancellation()
                guard self.playbackRequestID == requestID,
                      self.currentTrack?.id == track.id else { return }
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

                self.playbackWatchdogTask?.cancel()
                self.isBuffering = false
                self.isPlaying = false
                self.retirePlayer()
                self.endPlaybackTransition(requestID: requestID)
                self.invalidateCurrentStreamCache()
                self.playerError = self.userFacingPlaybackError(error)
                self.output = "Playback error: \(error.localizedDescription)"
            }
        }
    }

    func selectTrackEffect(_ effect: LaneTrackEffect) async {
        guard let track = currentTrack, let id = track.trackID, !id.isEmpty else { return }
        guard effect != currentTrackEffect || trackEffectIsLoading else { return }
        guard effect == .original || hasPremiumAccess else {
            trackEffectError = "Lane Premium is required for track effects"
            return
        }
        let operation = UUID()
        effectRequestID = operation
        let generation = playbackRequestID
        let accountToken = token
        trackEffectIsLoading = true
        trackEffectError = ""
        defer { if effectRequestID == operation { trackEffectIsLoading = false } }
        do {
            await configureAPI()
            let url: String
            if effect == .original, let local = downloadedFileURL(for: track) {
                url = local.absoluteString
            } else {
                let result = effect == .original
                    ? try await resolvedStream(trackID: id, refID: track.refID, quality: activeStreamQuality ?? selectedPlaybackQuality())
                    : try await LaneAPI.shared.trackEffect(token: accountToken, trackId: id, effect: effect)
                guard result.trackId == nil || result.trackId == id else {
                    throw LaneAPIError.decoding("Lane returned an effect for a different track")
                }
                guard normalizedStreamURL(result.url) != nil else { throw URLError(.badURL) }
                url = result.url
            }
            try Task.checkCancellation()
            guard effectRequestID == operation, playbackRequestID == generation,
                  currentTrack?.trackID == id, token == accountToken else { return }
            // Keep the current audio playing while the new URL is resolving.
            // Snapshot the position at replacement time, not at request time.
            let position = effect.position(from: playbackPosition, effect: currentTrackEffect)
            streamResolveTask?.cancel()
            playbackWatchdogTask?.cancel()
            player?.pause()
            playbackRequestID = UUID()
            if playbackShouldPlay { beginPlaybackTransition(requestID: playbackRequestID) }
            else { endPlaybackTransition() }
            cancelPreparedStream()
            pendingStartPosition = position
            playbackPosition = position
            playbackBufferedDuration = 0
            seekingInitialPosition = false
            isBuffering = true
            playerError = ""
            streamURL = url
            currentTrackEffect = effect
            trackEffects[id] = effect
            playerRetriedWithCompatibilityHeaders = false
            playerRetriedWithLocalDownload = false
            playerRetriedWithProgressiveTransport = false
            if let local = URL(string: url), local.isFileURL {
                try playLocalCompatibilityFile(local, sourceDescription: "downloaded original", requestID: playbackRequestID, track: track)
            } else {
                try play(urlString: url, useCompatibilityHeaders: false, requestID: playbackRequestID, track: track)
            }
        } catch is CancellationError { }
        catch {
            guard effectRequestID == operation, currentTrack?.trackID == id else { return }
            trackEffectError = error.localizedDescription
        }
    }

    private func startReadyPlayer(_ player: AVPlayer, item: AVPlayerItem, requestID: UUID) {
        guard playbackRequestID == requestID, self.player === player, player.currentItem === item else { return }
        if let seconds = pendingStartPosition {
            pendingStartPosition = nil
            seekingInitialPosition = true
            let duration = item.duration.seconds
            let bounded = duration.isFinite && duration > 0 ? min(seconds, max(0, duration - 0.1)) : seconds
            player.seek(to: CMTime(seconds: bounded, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] _ in
                Task { @MainActor in
                    guard let self, let player, self.playbackRequestID == requestID, self.player === player else { return }
                    self.seekingInitialPosition = false
                    self.playbackPosition = bounded
                    if self.playbackShouldPlay, !self.audioInterrupted { player.play() }
                }
            }
        } else if playbackShouldPlay, !audioInterrupted { player.play() }
    }

    private func mediaHeadProbe(_ url: URL) async -> Int? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 2.5
        request.setValue("LaneMusic/1.0 (Android; Mobile)", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        let started = Date()

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<400).contains(http.statusCode) else {
                return nil
            }
            return Int(Date().timeIntervalSince(started) * 1000)
        } catch {
            return nil
        }
    }

    private func autoTuneMediaRoute(for rawURL: String) async {
        guard !didAutoTuneMediaRoute else { return }
        didAutoTuneMediaRoute = true

        guard let original = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }
        guard let apk = laneAPKMediaURL(rawURL),
              apk.absoluteString != original.absoluteString else {
            diagnosticMediaRoute = "original"
            return
        }

        // First reachable response wins. Waiting for the blocked alternative
        // used to add its entire timeout to the first audible frame.
        let route = await withTaskGroup(of: String?.self) { group in
            group.addTask { await self.mediaHeadProbe(original) == nil ? nil : "original" }
            group.addTask { await self.mediaHeadProbe(apk) == nil ? nil : "apk" }
            for await route in group {
                if let route { group.cancelAll(); return route }
            }
            return "original"
        }
        guard !Task.isCancelled else { didAutoTuneMediaRoute = false; return }
        diagnosticMediaRoute = route
    }

    private func normalizedStreamURL(_ raw: String) -> URL? {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Apply the same CdnUrlInterceptor routing as Lane Android. Previously
        // artwork used this rewrite but audio did not, which left AVPlayer
        // talking to the blocked global CDN when the VPN was disabled.
        if let routed = laneRoutedMediaURL(clean) {
            return routed
        }

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
        equalizerTask?.cancel(); equalizerTask = nil; equalizerProcessor = nil
        progressiveAudioLoader?.cancelAll()
        progressiveAudioLoader = nil
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
        playbackEndObserver = nil
        if let playbackStallObserver { NotificationCenter.default.removeObserver(playbackStallObserver) }
        playbackStallObserver = nil

        playerItemStatusObserver?.invalidate()
        playerItemStatusObserver = nil

        playerLoadedTimeRangesObserver?.invalidate()
        playerLoadedTimeRangesObserver = nil

        playerTimeControlObserver?.invalidate()
        playerTimeControlObserver = nil

        if let periodicTimeObserver, let player {
            player.removeTimeObserver(periodicTimeObserver)
        }
        periodicTimeObserver = nil
    }

    private func retirePlayer() {
        player?.pause()
        teardownPlayerObservers()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private func invalidateCurrentStreamCache() {
        guard let id = currentTrack?.trackID else { return }
        streamResolutionCache = streamResolutionCache.filter { !$0.key.hasPrefix("\(id)|") }
    }

    private func observePlaybackEnd(
        of item: AVPlayerItem,
        requestID: UUID,
        track: TrackCandidate
    ) {
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            Task { @MainActor in
                guard let self, let item,
                      self.playbackRequestID == requestID,
                      self.currentTrack?.id == track.id,
                      self.player?.currentItem === item else { return }
                self.advanceAfterPlaybackEnd()
            }
        }
        playbackStallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
        ) { [weak self, weak item] _ in
            Task { @MainActor in
                guard let self, let item, self.playbackRequestID == requestID,
                      self.player?.currentItem === item, self.playbackShouldPlay, !self.audioInterrupted else { return }
                self.isBuffering = true
                self.recordAudioEvent("stalled")
                self.beginPlaybackTransition(requestID: requestID)
                // Do not replace the item or reset position on ordinary
                // buffering. AVPlayer resumes when more data arrives.
                self.player?.play()
            }
        }
    }

    private func observeLoadedTimeRanges(
        of item: AVPlayerItem,
        requestID: UUID,
        track: TrackCandidate
    ) {
        playerLoadedTimeRangesObserver = item.observe(
            \.loadedTimeRanges,
            options: [.initial, .new]
        ) { [weak self, weak item] itemValue, _ in
            Task { @MainActor in
                guard let self,
                      let item,
                      item === itemValue,
                      self.playbackRequestID == requestID,
                      self.currentTrack?.id == track.id,
                      self.player?.currentItem === item else { return }

                let bufferedEnd = item.loadedTimeRanges
                    .map(\.timeRangeValue)
                    .map { CMTimeGetSeconds(CMTimeRangeGetEnd($0)) }
                    .filter { $0.isFinite && $0 >= 0 }
                    .max() ?? 0
                let upperBound = self.playbackDuration > 0
                    ? min(bufferedEnd, self.playbackDuration)
                    : bufferedEnd
                self.playbackBufferedDuration = max(self.playbackPosition, upperBound)
            }
        }
    }

    private func advanceAfterPlaybackEnd() {
        recordAudioEvent("track-ended")
        if repeatMode == 2, let currentTrack {
            requestStream(for: currentTrack)
            return
        }

        let nextIndex = (currentIndex ?? -1) + 1
        if queue.isEmpty || (nextIndex >= queue.count && repeatMode != 1) {
            playbackShouldPlay = false
            isPlaying = false
            isBuffering = false
            endPlaybackTransition()
            updatePlaybackState(false)
            return
        }

        next()
    }

    private func play(
        urlString: String,
        useCompatibilityHeaders: Bool,
        requestID: UUID,
        track: TrackCandidate,
        useProgressiveTransport: Bool = false
    ) throws {
        guard playbackRequestID == requestID,
              currentTrack?.id == track.id else { return }

        guard let url = normalizedStreamURL(urlString) else {
            throw NSError(
                domain: "LanePlayer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Lane returned an invalid stream URL"]
            )
        }

        retirePlayer()

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
        var progressive = useProgressiveTransport || url.host.map { progressiveMediaHosts.contains($0) } == true
        #if DEBUG
        progressive = progressive || debugUseProgressiveTransport
        #endif
        if progressive && url.pathExtension.lowercased() != "m3u8" {
            let loader: LaneProgressiveAudioLoader
            #if DEBUG
            if debugUseProgressiveTransport, ProcessInfo.processInfo.arguments.contains("--lane-ui-test"), url.host == "127.0.0.1" {
                loader = LaneProgressiveAudioLoader(url: url, fetch: { request in
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    return (data, http)
                })
            } else { loader = LaneProgressiveAudioLoader(url: url) }
            #else
            loader = LaneProgressiveAudioLoader(url: url)
            #endif
            progressiveAudioLoader = loader
            asset = loader.makeAsset()
        } else if useCompatibilityHeaders {
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
        let usesProgressiveAudio = progressive
        // AVPlayer supports progressive HTTP range loading. Keep a short
        // forward buffer so audio starts while the remaining file arrives.
        item.preferredForwardBufferDuration = 3
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        let newPlayer = AVPlayer(playerItem: item)
        // Media3 starts promptly; AVPlayer's default conservative buffering
        // could delay the first audible frame for several seconds on LTE.
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        player = newPlayer
        attachEqualizer(to: item)
        observePlaybackEnd(of: item, requestID: requestID, track: track)
        observeLoadedTimeRanges(of: item, requestID: requestID, track: track)

        playerItemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self,
                      self.playbackRequestID == requestID,
                      self.currentTrack?.id == track.id,
                      self.player?.currentItem === item else { return }

                switch item.status {
                case .readyToPlay:
                    self.playerError = ""
                    self.isBuffering = false

                    // Statistics are not part of playback resolution in the APK.
                    // Fetch them only after audio is ready so this secondary API
                    // request cannot compete with /track/stream during startup.
                    if self.trackStats == nil {
                        self.loadTrackStats(track)
                    }

                    let seconds = item.duration.seconds
                    if seconds.isFinite && seconds > 0 {
                        self.playbackDuration = seconds
                    }

                    if let player = self.player { self.startReadyPlayer(player, item: item, requestID: requestID) }

                case .failed:
                    let detail = item.error?.localizedDescription ?? "Unable to play this stream"
                    if self.playbackPosition > 0.25, self.pendingStartPosition == nil {
                        self.pendingStartPosition = self.playbackPosition
                    }

                    if self.connectivityError(item.error), !self.playerRetriedWithProgressiveTransport,
                       !self.streamURL.isEmpty, url.pathExtension.lowercased() != "m3u8" {
                        self.playerRetriedWithProgressiveTransport = true
                        do {
                            try self.play(urlString: self.streamURL, useCompatibilityHeaders: true,
                                          requestID: requestID, track: track, useProgressiveTransport: true)
                            return
                        } catch { self.output = "Range transport failed: \(error.localizedDescription)" }
                    }

                    if self.connectivityError(item.error),
                       !self.playerRetriedWithLocalDownload,
                       !self.streamURL.isEmpty {
                        self.playerRetriedWithLocalDownload = true
                        self.downloadCompatibilityAudio(
                            self.streamURL,
                            requestID: requestID,
                            track: track
                        )
                        return
                    }

                    if !useCompatibilityHeaders,
                       !self.playerRetriedWithCompatibilityHeaders,
                       !self.streamURL.isEmpty {
                        self.playerRetriedWithCompatibilityHeaders = true
                        do {
                            try self.play(
                                urlString: self.streamURL,
                                useCompatibilityHeaders: true,
                                requestID: requestID,
                                track: track
                            )
                            return
                        } catch {
                            self.playerError = self.userFacingPlaybackError(error)
                            self.output = "Playback error: \(error.localizedDescription)"
                        }
                    }

                    if useCompatibilityHeaders,
                       !self.playerRetriedWithLocalDownload,
                       !self.streamURL.isEmpty {
                        self.playerRetriedWithLocalDownload = true
                        self.downloadCompatibilityAudio(
                            self.streamURL,
                            requestID: requestID,
                            track: track
                        )
                        return
                    }

                    self.isBuffering = false
                    self.isPlaying = false
                    self.endPlaybackTransition(requestID: requestID)
                    self.playerError = "The track is temporarily unavailable."
                    self.output = "Playback error: \(detail)"
                    self.invalidateCurrentStreamCache()

                case .unknown:
                    self.isBuffering = true

                @unknown default:
                    break
                }
            }
        }

        playerTimeControlObserver = newPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self,
                      self.playbackRequestID == requestID,
                      self.currentTrack?.id == track.id,
                      self.player === player else { return }

                switch player.timeControlStatus {
                case .playing:
                    guard !self.audioInterrupted else { player.pause(); return }
                    if !self.isPlaying { self.recordAudioEvent("audio-started") }
                    self.isPlaying = true
                    self.isBuffering = false
                    self.endPlaybackTransition(requestID: requestID)
                    // Short startup buffer, then enough headroom for carrier
                    // jitter in the background. Increasing it after playback
                    // starts does not delay the first audible frame.
                    item.preferredForwardBufferDuration = 20
                    player.automaticallyWaitsToMinimizeStalling = true
                    if usesProgressiveAudio, let host = url.host { self.progressiveMediaHosts.insert(host) }
                case .waitingToPlayAtSpecifiedRate:
                    self.isPlaying = false
                    self.isBuffering = true
                    if self.playbackShouldPlay, self.playbackBackgroundLease?.isActive != true, !self.audioInterrupted {
                        self.beginPlaybackTransition(requestID: requestID)
                    }
                case .paused:
                    self.recordAudioEvent("native-paused")
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
        ) { [weak self, weak newPlayer] time in
            Task { @MainActor in
                guard let self,
                      let newPlayer, self.player === newPlayer,
                      self.playbackRequestID == requestID,
                      self.currentTrack?.id == track.id else { return }
                let seconds = time.seconds
                if seconds.isFinite, self.pendingStartPosition == nil, !self.seekingInitialPosition {
                    self.playbackPosition = max(0, seconds)
                    if seconds >= 0.25, self.isPlaying { self.prepareNextStream(requestID: requestID) }
                }

                if let duration = self.player?.currentItem?.duration.seconds,
                   duration.isFinite,
                   duration > 0 {
                    self.playbackDuration = duration
                }
            }
        }

        if playbackShouldPlay, !audioInterrupted, pendingStartPosition == nil { newPlayer.playImmediately(atRate: 1) }

        // AVPlayer can remain in waitingToPlayAtSpecifiedRate indefinitely for
        // some signed CDN URLs without ever transitioning to .failed. Android
        // Media3 retries the source; mirror that behavior here.
        Task { [weak self, weak newPlayer] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self,
                  let newPlayer,
                  self.player === newPlayer,
                  self.playbackRequestID == requestID,
                  self.currentTrack?.id == track.id else { return }

            guard self.isBuffering,
                  self.playbackPosition < 0.25,
                  !self.streamURL.isEmpty else { return }

            if !useCompatibilityHeaders && !self.playerRetriedWithCompatibilityHeaders {
                self.playerRetriedWithCompatibilityHeaders = true
                try? self.play(
                    urlString: self.streamURL,
                    useCompatibilityHeaders: true,
                    requestID: requestID,
                    track: track
                )
            } else if useCompatibilityHeaders && !self.playerRetriedWithProgressiveTransport,
                      url.pathExtension.lowercased() != "m3u8" {
                self.playerRetriedWithProgressiveTransport = true
                do {
                    try self.play(urlString: self.streamURL, useCompatibilityHeaders: true,
                                  requestID: requestID, track: track, useProgressiveTransport: true)
                } catch { self.playerError = self.userFacingPlaybackError(error) }
            } else if useCompatibilityHeaders && !self.playerRetriedWithLocalDownload {
                // Keep using the URL returned by /track/stream. Downloading
                // that same response to a local file helps AVFoundation with
                // servers whose content metadata Media3 accepts more readily,
                // without switching normal playback to /track/download.
                self.playerRetriedWithLocalDownload = true
                self.downloadCompatibilityAudio(
                    self.streamURL,
                    requestID: requestID,
                    track: track
                )
            }
        }

        if playbackRequestID == requestID,
           currentTrack?.id == track.id {
            history.removeAll { $0.id == track.id }
            history.insert(track, at: 0)
            if history.count > 100 {
                history = Array(history.prefix(100))
            }
            saveHistory()
        }

        updateNowPlaying()
    }

    private func connectivityError(_ error: Error?) -> Bool {
        guard let error else { return false }
        let ns = error as NSError
        let networkCodes: Set<Int> = [
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorDNSLookupFailed
        ]

        if ns.domain == NSURLErrorDomain, networkCodes.contains(ns.code) {
            return true
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            return connectivityError(underlying)
        }
        return false
    }

    private func downloadMediaUsingLaneTransport(_ request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        do {
            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse else {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw URLError(.badServerResponse)
            }
            return (temporaryURL, http)
        } catch {
            try Task.checkCancellation()
            // AVPlayer/URLSession can lose the carrier route to Lane's CDN
            // without VPN even though the API itself is reachable. Reuse the
            // Android-style direct TLS transport (DoH/IP + original SNI/Host)
            // for the exact same selected-quality stream URL.
            // This is the last full-file fallback, not the range streaming
            // path. Never let an ignored Range/huge response exhaust RAM.
            let direct = try await AndroidNetworkTransport.data(for: request, timeout: 60, maximumResponseBytes: 48 * 1024 * 1024)
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("lane_direct_\(UUID().uuidString)")
            try direct.data.write(to: temporaryURL, options: .atomic)
            return (temporaryURL, direct.response)
        }
    }

    private func downloadStreamAndPlayLocally(
        _ urlString: String,
        requestID: UUID,
        track: TrackCandidate
    ) {
        guard let url = normalizedStreamURL(urlString) else { return }

        // HLS playlists need AVPlayer's segment loader and cannot be converted
        // into a single local audio file by this fallback.
        if url.pathExtension.lowercased() == "m3u8" {
            isBuffering = false
            isPlaying = false
            playerError = "The track is temporarily unavailable."
            output = "Playback error: The HLS stream could not be opened by AVPlayer."
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

                let (temporaryURL, response) = try await self.downloadMediaUsingLaneTransport(request)

                guard self.playbackRequestID == requestID,
                      self.currentTrack?.id == track.id else {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    return
                }

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

                retirePlayer()

                let item = AVPlayerItem(url: destination)
                let localPlayer = AVPlayer(playerItem: item)
                localPlayer.automaticallyWaitsToMinimizeStalling = false
                player = localPlayer
                attachEqualizer(to: item)
                observePlaybackEnd(of: item, requestID: requestID, track: track)
                observeLoadedTimeRanges(of: item, requestID: requestID, track: track)

                playerItemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                    Task { @MainActor in
                        guard let self, self.playbackRequestID == requestID, self.currentTrack?.id == track.id,
                              self.player?.currentItem === item else { return }
                        switch item.status {
                        case .readyToPlay:
                            self.playerError = ""
                            self.isBuffering = false
                            if item.duration.seconds.isFinite && item.duration.seconds > 0 {
                                self.playbackDuration = item.duration.seconds
                                self.playbackBufferedDuration = item.duration.seconds
                            }
                            if let player = self.player { self.startReadyPlayer(player, item: item, requestID: requestID) }
                        case .failed:
                            let detail = item.error?.localizedDescription ?? "Unable to decode Lane audio"

                            guard self.playbackRequestID == requestID,
                                  self.currentTrack?.id == track.id else { return }

                            self.isBuffering = false
                            self.isPlaying = false
                            self.endPlaybackTransition(requestID: requestID)
                            self.playerError = "The track is temporarily unavailable."
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
                        guard let self, self.playbackRequestID == requestID, self.currentTrack?.id == track.id,
                              self.player === player else { return }
                        if player.timeControlStatus == .playing, self.audioInterrupted { player.pause(); return }
                        self.isPlaying = player.timeControlStatus == .playing
                        self.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                        if self.isPlaying { self.endPlaybackTransition(requestID: requestID) }
                        self.updatePlaybackState(self.isPlaying)
                    }
                }

                periodicTimeObserver = localPlayer.addPeriodicTimeObserver(
                    forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                    queue: .main
                ) { [weak self, weak localPlayer] time in
                    Task { @MainActor in
                        guard let self, let localPlayer, self.player === localPlayer,
                              self.playbackRequestID == requestID, self.currentTrack?.id == track.id else { return }
                        if time.seconds.isFinite, self.pendingStartPosition == nil, !self.seekingInitialPosition {
                            self.playbackPosition = max(0, time.seconds)
                            if time.seconds >= 0.25, self.isPlaying { self.prepareNextStream(requestID: requestID) }
                        }
                    }
                }

                if playbackShouldPlay, !audioInterrupted, pendingStartPosition == nil { localPlayer.play() }
            } catch {
                guard self.playbackRequestID == requestID,
                      self.currentTrack?.id == track.id else { return }
                isBuffering = false
                isPlaying = false
                endPlaybackTransition(requestID: requestID)
                playerError = userFacingPlaybackError(error)
                output = "Playback error: \(error.localizedDescription)"
            }
        }
    }


    private func downloadCompatibilityAudio(
        _ urlString: String,
        requestID: UUID,
        track: TrackCandidate
    ) {
        guard let url = normalizedStreamURL(urlString) else {
            isBuffering = false
            playerError = "The track is temporarily unavailable."
            output = "Playback error: Lane returned an invalid compatibility audio URL."
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

                let (temporaryURL, response) = try await self.downloadMediaUsingLaneTransport(request)

                guard self.playbackRequestID == requestID,
                      self.currentTrack?.id == track.id else {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    return
                }

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
                    sourceDescription: signature.description,
                    requestID: requestID,
                    track: track
                )
            } catch {
                guard self.playbackRequestID == requestID,
                      self.currentTrack?.id == track.id else { return }
                isBuffering = false
                isPlaying = false
                playerError = userFacingPlaybackError(error)
                output = "Playback error: \(error.localizedDescription)"
            }
        }
    }

    private func playLocalCompatibilityFile(
        _ url: URL,
        sourceDescription: String,
        requestID: UUID,
        track: TrackCandidate
    ) throws {
        guard playbackRequestID == requestID,
              currentTrack?.id == track.id else { return }

        retirePlayer()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .default, options: [])
        try audioSession.setActive(true)

        let item = AVPlayerItem(url: url)
        let localPlayer = AVPlayer(playerItem: item)
        localPlayer.automaticallyWaitsToMinimizeStalling = false
        player = localPlayer
        attachEqualizer(to: item)
        observePlaybackEnd(of: item, requestID: requestID, track: track)
        observeLoadedTimeRanges(of: item, requestID: requestID, track: track)

        playerItemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self,
                      self.playbackRequestID == requestID,
                      self.currentTrack?.id == track.id,
                      self.player?.currentItem === item else { return }

                switch item.status {
                case .readyToPlay:
                    self.playerError = ""
                    self.output = "Playing Lane audio (\(sourceDescription))."
                    self.isBuffering = false

                    let duration = item.duration.seconds
                    if duration.isFinite && duration > 0 {
                        self.playbackDuration = duration
                        self.playbackBufferedDuration = duration
                    }

                    if let player = self.player { self.startReadyPlayer(player, item: item, requestID: requestID) }

                case .failed:
                    self.isBuffering = false
                    self.isPlaying = false
                    self.endPlaybackTransition(requestID: requestID)
                    let avError = item.error as NSError?
                    let detail = avError?.localizedDescription ?? "Cannot Open"
                    let code = avError.map { "\($0.domain) \($0.code)" } ?? "unknown AVFoundation error"

                    self.playerError = "The track is temporarily unavailable."
                    self.output = "Playback error: \(detail) · \(sourceDescription) · \(code)"

                case .unknown:
                    self.isBuffering = true

                @unknown default:
                    break
                }
            }
        }

        playerTimeControlObserver = localPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, self.playbackRequestID == requestID,
                      self.currentTrack?.id == track.id, self.player === player else { return }
                if player.timeControlStatus == .playing, self.audioInterrupted { player.pause(); return }
                self.isPlaying = player.timeControlStatus == .playing
                self.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                if self.isPlaying { self.endPlaybackTransition(requestID: requestID) }
                self.updatePlaybackState(self.isPlaying)
            }
        }

        periodicTimeObserver = localPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self, weak localPlayer] time in
            Task { @MainActor in
                guard let self, let localPlayer, self.player === localPlayer, self.playbackRequestID == requestID,
                      self.currentTrack?.id == track.id else { return }
                if time.seconds.isFinite, self.pendingStartPosition == nil, !self.seekingInitialPosition {
                    self.playbackPosition = max(0, time.seconds)
                    if time.seconds >= 0.25, self.isPlaying { self.prepareNextStream(requestID: requestID) }
                }
            }
        }

        if playbackShouldPlay, !audioInterrupted, pendingStartPosition == nil { localPlayer.play() }
    }

    private enum LaneMediaSignature {
        case mp4
        case mp3
        case hls
        case ogg
        case webm
        case wav
        case unknown(String)

        var description: String {
            switch self {
            case .mp4: return "M4A/MP4"
            case .mp3: return "MP3"
            case .hls: return "HLS"
            case .ogg: return "Ogg/Opus"
            case .webm: return "WebM"
            case .wav: return "WAV"
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
        if data.starts(with: Data("RIFF".utf8)), data.count >= 12,
           String(data: data[8..<12], encoding: .ascii) == "WAVE" { return .wav }
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
        case .wav:
            return "wav"
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
        playbackShouldPlay = false
        interruptionResumeRequested = false
        player?.pause()
        isPlaying = false
        endPlaybackTransition()
        updatePlaybackState(false)
        recordAudioEvent("pause")
    }

    func resume() {
        playbackShouldPlay = true
        guard !audioInterrupted else { interruptionResumeRequested = true; return }
        do { try activateAudioSession() }
        catch { playerError = userFacingPlaybackError(error); recordAudioEvent("session-activation-failed"); return }
        guard !seekingInitialPosition else { return }
        if !playerError.isEmpty || player?.currentItem?.status == .failed {
            if let currentTrack {
                invalidateCurrentStreamCache()
                requestStream(for: currentTrack)
            }
            return
        }
        // Resolution already in flight: don't start a retired item or cancel
        // the fresh request each time the Play button is pressed.
        if player == nil, streamResolveTask != nil, isBuffering {
            beginPlaybackTransition(requestID: playbackRequestID)
            return
        }
        if let player {
            beginPlaybackTransition(requestID: playbackRequestID)
            // The initial startup already uses this policy. Resume buffered
            // audio promptly too, instead of waiting to refill the entire
            // 20-second forward buffer after a call or user pause.
            player.playImmediately(atRate: 1)
            isBuffering = player.timeControlStatus != .playing
            if !isBuffering { endPlaybackTransition(requestID: playbackRequestID) }
        } else if let currentTrack {
            let savedPosition = pendingStartPosition
            requestStream(for: currentTrack)
            pendingStartPosition = savedPosition
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
        nowPlayingArtworkTask?.cancel(); nowPlayingArtworkTask = nil
        nowPlayingArtworkKey = nil; nowPlayingArtwork = nil
        interruptionResumeRequested = false
        endPlaybackTransition()
        cancelPreparedStream()
        busy = false
        playbackRequestID = UUID()
        effectRequestID = UUID()
        trackEffectIsLoading = false
        playbackShouldPlay = false
        pendingStartPosition = nil
        seekingInitialPosition = false
        streamResolveTask?.cancel()
        playbackWatchdogTask?.cancel()
        player?.pause()
        teardownPlayerObservers()
        player = nil
        isPlaying = false
        isBuffering = false
        playbackPosition = 0
        playbackDuration = 0
        playbackBufferedDuration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func next() {
        guard !queue.isEmpty else { return }

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
        let artworkKey = currentTrack.map { "\($0.trackID ?? $0.id)|\($0.coverURL ?? "")" }
        if nowPlayingArtworkKey != artworkKey {
            nowPlayingArtworkTask?.cancel(); nowPlayingArtworkTask = nil
            nowPlayingArtworkKey = artworkKey; nowPlayingArtwork = nil
            if let url = laneRoutedMediaURL(currentTrack?.coverURL) {
                nowPlayingArtworkTask = Task { [weak self] in
                    guard let data = try? await AndroidNetworkTransport.imageData(from: url), !Task.isCancelled,
                          let image = await laneDecodeArtwork(data, maximumPixels: 640), !Task.isCancelled,
                          let self, self.nowPlayingArtworkKey == artworkKey else { return }
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    self.nowPlayingArtwork = artwork
                    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    info[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            }
        }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = currentTrack?.title ?? "Lane"
        info[MPMediaItemPropertyArtist] = currentTrack?.subtitle ?? ""
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPMediaItemPropertyPlaybackDuration] = playbackDuration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackPosition
        info[MPMediaItemPropertyArtwork] = nowPlayingArtwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updatePlaybackState(_ playing: Bool) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        info[MPMediaItemPropertyPlaybackDuration] = playbackDuration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackPosition
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        schedulePresenceSync()
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        func register(_ command: MPRemoteCommand, handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
            remoteCommandTargets.append((command, command.addTarget(handler: handler)))
        }

        register(commands.playCommand) { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }

        register(commands.pauseCommand) { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }

        register(commands.nextTrackCommand) { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }

        register(commands.previousTrackCommand) { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        commands.changePlaybackPositionCommand.isEnabled = true
        register(commands.changePlaybackPositionCommand) { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    // MARK: Favorites / local playlists

    private func migrateLegacyFavorites(_ ids: [String], token requestToken: String) async {
        defer {
            if token == requestToken { favoriteMigrationInProgress = false }
        }
        var failed: [String] = []
        let ordered = ids.sorted()
        for start in stride(from: 0, to: ordered.count, by: 15) {
            guard token == requestToken else { return }
            let batch = Array(ordered[start..<min(start + 15, ordered.count)])
            do {
                let result = try await LaneAPI.shared.addTracks(
                    token: requestToken,
                    playlistId: "lane_likes",
                    trackIds: batch
                )
                try result.requireSuccess()
            } catch {
                // One obsolete local ID must not prevent the remaining likes
                // from being saved to the account.
                for id in batch {
                    guard token == requestToken else { return }
                    do {
                        let result = try await LaneAPI.shared.addTracks(
                            token: requestToken,
                            playlistId: "lane_likes",
                            trackIds: [id]
                        )
                        try result.requireSuccess()
                    } catch {
                        failed.append(id)
                    }
                }
            }
        }
        guard token == requestToken else { return }
        if failed.isEmpty {
            UserDefaults.standard.set(true, forKey: favoriteMigrationKey)
            await loadLibrary()
        } else {
            output = "Could not sync \(failed.count) older liked tracks to Lane. Please retry when the connection is stable."
        }
    }

    private func favoriteKey(_ track: TrackCandidate) -> String {
        track.trackID ?? track.id
    }

    private func favoriteStateOnServer(
        trackID: String,
        token requestToken: String
    ) async -> Bool? {
        async let detailRequest = try? LaneAPI.shared.playlist(
            token: requestToken,
            playlistId: "lane_likes"
        )
        async let tracksRequest = loadPlaylistTrackCollection(
            token: requestToken,
            playlistId: "lane_likes",
            pageSize: 100
        )
        async let playlistsRequest = try? LaneAPI.shared.userPlaylists(token: requestToken)
        let (detail, tracks, playlists) = await (detailRequest, tracksRequest, playlistsRequest)

        var didReadState = false
        var readIDs = Set<String>()
        var expectedCount = detail?.effectiveTrackCount ?? 0
        if let ids = detail?.playlistTracksIds {
            didReadState = true
            readIDs.formUnion(ids)
            if ids.contains(trackID) { return true }
        }
        if let embedded = detail?.playlistTracks {
            didReadState = true
            readIDs.formUnion(embedded.compactMap(\.songId))
            if embedded.contains(where: { $0.songId == trackID }) { return true }
        }
        if let tracks {
            didReadState = true
            readIDs.formUnion(tracks.compactMap(\.songId))
            if tracks.contains(where: { $0.songId == trackID }) { return true }
        }
        if let likedPlaylist = playlists?.first(where: { $0.playlistId == "lane_likes" }) {
            expectedCount = max(expectedCount, likedPlaylist.effectiveTrackCount)
            if let ids = likedPlaylist.playlistTracksIds { didReadState = true; readIDs.formUnion(ids) }
            if let embedded = likedPlaylist.playlistTracks { didReadState = true; readIDs.formUnion(embedded.compactMap(\.songId)) }
            if likedPlaylist.playlistTracksIds?.contains(trackID) == true ||
                likedPlaylist.playlistTracks?.contains(where: { $0.songId == trackID }) == true {
                return true
            }
        }
        // Metadata-only and truncated pages cannot confirm a removal. A
        // positive occurrence proves membership; absence needs a complete read.
        return didReadState && readIDs.count >= expectedCount ? false : nil
    }

    private func waitForFavoriteState(
        trackID: String,
        liked: Bool,
        token requestToken: String,
        attempts: Int = 4
    ) async -> Bool {
        for attempt in 0..<attempts {
            guard token == requestToken else { return false }
            if await favoriteStateOnServer(trackID: trackID, token: requestToken) == liked {
                return true
            }
            if attempt + 1 < attempts {
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
        }
        return false
    }

    func isFavorite(_ track: TrackCandidate) -> Bool {
        favorites.contains(favoriteKey(track))
    }

    func isFavoriteSyncPending(_ track: TrackCandidate) -> Bool {
        track.trackID.map { pendingFavoriteStates[$0] != nil } ?? false
    }

    private func persistFavoriteState() {
        UserDefaults.standard.set(Array(favorites), forKey: "lane.favorites")
        if pendingFavoriteStates.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingFavoriteStatesKey)
        } else if let data = try? JSONEncoder().encode(pendingFavoriteStates) {
            UserDefaults.standard.set(data, forKey: pendingFavoriteStatesKey)
        }
    }

    private func restorePendingFavoriteTracks() {
        for (trackID, shouldBeLiked) in pendingFavoriteStates {
            if shouldBeLiked {
                favorites.insert(trackID)
                guard !likedTracks.contains(where: { $0.trackID == trackID }),
                      let cached = resolvedTrackCache[trackID] ?? localTrackStore[trackID] else {
                    continue
                }
                likedTracks.append(cached)
            } else {
                favorites.remove(trackID)
                likedTracks.removeAll { $0.trackID == trackID }
            }
        }
        UserDefaults.standard.set(Array(favorites), forKey: "lane.favorites")
    }

    private func retryPendingFavoriteMutations(token requestToken: String) {
        guard token == requestToken else { return }
        for (trackID, shouldBeLiked) in pendingFavoriteStates {
            guard favoriteMutationsInFlight.insert(trackID).inserted else { continue }
            Task { @MainActor [weak self] in
                await self?.syncPendingFavoriteMutation(
                    trackID: trackID,
                    shouldBeLiked: shouldBeLiked,
                    token: requestToken
                )
            }
        }
    }

    private func syncPendingFavoriteMutation(
        trackID: String,
        shouldBeLiked: Bool,
        token requestToken: String
    ) async {
        defer {
            if token == requestToken {
                favoriteMutationsInFlight.remove(trackID)
            }
        }

        await configureAPI()
        var acceptedByServer = false
        var confirmedOnServer = false
        var lastError: Error?

        // Adding/removing a playlist track is idempotent on Lane. A bounded
        // retry covers a dead regional route, while the persisted pending
        // state survives app restarts and later Library refreshes.
        for attempt in 0..<2 {
            guard token == requestToken,
                  pendingFavoriteStates[trackID] == shouldBeLiked else { return }
            do {
                let result: APIResult
                if shouldBeLiked {
                    result = try await LaneAPI.shared.addTracks(
                        token: requestToken,
                        playlistId: "lane_likes",
                        trackIds: [trackID]
                    )
                } else {
                    result = try await LaneAPI.shared.removeTrack(
                        token: requestToken,
                        playlistId: "lane_likes",
                        trackId: trackID
                    )
                }
                status = result.status
                try result.requireSuccess()
                acceptedByServer = true
            } catch {
                lastError = error
            }

            confirmedOnServer = await waitForFavoriteState(
                trackID: trackID,
                liked: shouldBeLiked,
                token: requestToken,
                attempts: acceptedByServer ? 4 : 1
            )
            if confirmedOnServer { break }

            if attempt == 0 {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }

        guard token == requestToken,
              pendingFavoriteStates[trackID] == shouldBeLiked else { return }

        if confirmedOnServer {
            libraryLoadGeneration = UUID()
            pendingFavoriteStates.removeValue(forKey: trackID)
            output = shouldBeLiked ? "Added to liked tracks." : "Removed from liked tracks."
        } else if acceptedByServer {
            // A successful write can take a moment to reach a regional read
            // endpoint. Keep the optimistic state until any Lane read model
            // confirms it instead of allowing a stale empty replica to win.
            output = shouldBeLiked
                ? "Lane accepted the like; server confirmation is pending."
                : "Lane accepted the removal; server confirmation is pending."
        } else {
            // Network and regional validation failures are not proof that the
            // user changed their mind. Keep the operation durable and retry it
            // on the next Library refresh/app launch.
            let reason = lastError?.localizedDescription ?? "Lane did not accept the change yet"
            output = shouldBeLiked
                ? "Like saved on this iPhone; Lane sync will retry automatically. \(reason)"
                : "Like removal saved on this iPhone; Lane sync will retry automatically. \(reason)"
        }
        persistFavoriteState()
    }

    func toggleFavorite(_ track: TrackCandidate) {
        guard !clearingPlaylistIDs.contains("lane_likes") else {
            output = "Liked tracks are being cleared. Wait for the operation to finish."
            return
        }
        guard !isGuest else {
            output = "Sign in to save liked tracks to Lane."
            return
        }
        guard let trackID = track.trackID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trackID.isEmpty else {
            output = "This track has no Lane ID and cannot be liked."
            return
        }
        guard favoriteMutationsInFlight.insert(trackID).inserted else { return }

        libraryLoadGeneration = UUID()
        let requestToken = token
        let shouldBeLiked = !favorites.contains(trackID)
        pendingFavoriteStates[trackID] = shouldBeLiked
        if shouldBeLiked {
            favorites.insert(trackID)
            likedTracks.removeAll { $0.trackID == trackID }
            likedTracks.insert(
                TrackCandidate(
                    id: track.id,
                    title: track.title,
                    subtitle: track.subtitle,
                    trackID: trackID,
                    refID: "lane_likes",
                    platform: track.platform,
                    coverURL: track.coverURL,
                    duration: track.duration,
                    genre: track.genre,
                    artistAvatars: track.artistAvatars,
                    artistIDs: track.artistIDs
                ),
                at: 0
            )
            rememberResolvedTracks([track])
        } else {
            favorites.remove(trackID)
            likedTracks.removeAll { $0.trackID == trackID }
        }
        persistFavoriteState()

        Task { @MainActor in
            await syncPendingFavoriteMutation(
                trackID: trackID,
                shouldBeLiked: shouldBeLiked,
                token: requestToken
            )
        }
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
        localTrackStore[key] = track
        if !localPlaylists[index].trackKeys.contains(key) {
            localPlaylists[index].trackKeys.append(key)
        }
        saveLocalPlaylists()
    }

    @discardableResult
    func saveLocalImport(name: String, tracks: [TrackCandidate]) -> Int {
        var seen = Set<String>()
        let unique = tracks.filter { seen.insert(favoriteKey($0)).inserted }
        guard !unique.isEmpty else { return 0 }

        let baseName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Imported playlist"
            : name.trimmingCharacters(in: .whitespacesAndNewlines)
        let keys = unique.map { track -> String in
            let key = favoriteKey(track)
            localTrackStore[key] = track
            return key
        }

        if let index = localPlaylists.firstIndex(where: { $0.name == baseName }) {
            for key in keys where !localPlaylists[index].trackKeys.contains(key) {
                localPlaylists[index].trackKeys.append(key)
            }
            saveLocalPlaylists()
            return localPlaylists[index].trackKeys.count
        }

        localPlaylists.append(LocalPlaylist(name: baseName, trackKeys: keys))
        saveLocalPlaylists()
        return keys.count
    }

    func tracks(in playlist: LocalPlaylist) -> [TrackCandidate] {
        let all = history + searchTracks + queue + homeTracks + recentTracks
        return playlist.trackKeys.compactMap { key in
            localTrackStore[key] ?? all.first { favoriteKey($0) == key }
        }
    }

    // MARK: Downloads

    #if DEBUG
    func debugDownloadTrack(_ track: TrackCandidate) async throws {
        await configureAPI(); try await persistDownloadedTrack(track)
    }
    #endif

    func downloadTrack(_ track: TrackCandidate) {
        guard track.trackID != nil else { return }

        busy = true
        Task {
            defer { busy = false }
            do {
                await configureAPI()
                try await persistDownloadedTrack(track)
                output = "Downloaded \(track.title)"
            } catch {
                output = error.localizedDescription
            }
        }
    }

    func downloadPlaylistTracks(_ tracks: [TrackCandidate], playlistID: String) {
        guard !tracks.isEmpty, playlistDownloadTasks[playlistID] == nil else { return }

        playlistDownloads[playlistID] = LanePlaylistDownloadState(
            completed: 0, total: tracks.count, failed: 0, isRunning: true
        )

        playlistDownloadTasks[playlistID] = Task {
            await configureAPI()
            var completed = 0
            var failed = 0

            for track in tracks {
                if Task.isCancelled { break }
                do {
                    if !isDownloaded(track) {
                        try await persistDownloadedTrack(track)
                    }
                } catch {
                    if Task.isCancelled { break }
                    failed += 1
                    output = "Download failed for \(track.title): \(error.localizedDescription)"
                }
                completed += 1
                playlistDownloads[playlistID] = LanePlaylistDownloadState(
                    completed: completed, total: tracks.count, failed: failed, isRunning: true
                )
            }

            playlistDownloads[playlistID] = LanePlaylistDownloadState(
                completed: completed, total: tracks.count, failed: failed, isRunning: false
            )
            playlistDownloadTasks[playlistID] = nil
        }
    }

    func cancelPlaylistDownload(_ playlistID: String) {
        playlistDownloadTasks[playlistID]?.cancel()
    }

    private func persistDownloadedTrack(_ track: TrackCandidate) async throws {
        guard let trackID = track.trackID else { throw LaneAPIError.invalidURL }
        let requestToken = token
        let downloadQuality = selectedPlaybackQuality()
        let stream = try await LaneAPI.shared.downloadURL(
            token: requestToken, trackId: trackID, quality: downloadQuality
        )
        guard token == requestToken, !Task.isCancelled else { throw CancellationError() }
        guard let remoteURL = normalizedStreamURL(stream.url) else {
            throw LaneAPIError.invalidURL
        }
        if remoteURL.pathExtension.lowercased() == "m3u8" {
            _ = try await LaneHLSOfflineStore.shared.download(track: track, remote: remoteURL, quality: downloadQuality)
            refreshHLSDownloads(); return
        }

        // Use the same route selection and DNS/TLS fallback as playback.
        let (temporary, response) = try await downloadMediaUsingLaneTransport(URLRequest(url: remoteURL))
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        if !(200..<300).contains(response.statusCode) {
            throw NSError(
                domain: "LaneDownload",
                code: response.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Audio download returned HTTP \(response.statusCode)"]
            )
        }
        let signature = Self.mediaSignature(at: temporary)
        if case .hls = signature {
            _ = try await LaneHLSOfflineStore.shared.download(track: track, remote: remoteURL, quality: downloadQuality)
            refreshHLSDownloads(); return
        }
        let directory = downloadsDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "\(UUID().uuidString).\(Self.localAudioExtension(for: signature))"
        let destination = directory.appendingPathComponent(fileName)
        try FileManager.default.moveItem(at: temporary, to: destination)
        let previous = downloadedFileURL(for: track)
        downloadedTrackRecords[trackID] = LaneDownloadedTrack(track: track, fileName: fileName)
        downloadedTrackIDs.insert(trackID)
        rememberResolvedTracks([track])
        if let data = try? JSONEncoder().encode(downloadedTrackRecords) {
            UserDefaults.standard.set(data, forKey: "lane.downloadedTrackRecords")
        }
        UserDefaults.standard.set(Array(downloadedTrackIDs), forKey: "lane.downloads")
        if let previous { try? FileManager.default.removeItem(at: previous) }
    }

    private var downloadsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LaneDownloads", isDirectory: true)
    }

    func downloadedFileURL(for track: TrackCandidate) -> URL? {
        if let id = track.trackID, let url = LaneHLSOfflineStore.shared.fileURL(for: id) { return url }
        guard let id = track.trackID, downloadedTrackIDs.contains(id) else { return nil }
        if let record = downloadedTrackRecords[id],
           record.fileName == URL(fileURLWithPath: record.fileName).lastPathComponent {
            let url = downloadsDirectory.appendingPathComponent(record.fileName)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        // Recover downloads produced before persistent metadata was added.
        let legacyName = id.replacingOccurrences(of: "/", with: "_")
        let files = (try? FileManager.default.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.deletingPathExtension().lastPathComponent == legacyName }
    }

    var downloadedTracks: [TrackCandidate] {
        let candidates = LaneHLSOfflineStore.shared.tracks + downloadedTrackRecords.values.map(\.track) + history + Array(resolvedTrackCache.values) + Array(localTrackStore.values)
        var seen = Set<String>()
        return candidates.filter { downloadedFileURL(for: $0) != nil && seen.insert($0.trackID ?? $0.id).inserted }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func removeDownload(_ track: TrackCandidate) throws {
        guard let id = track.trackID else { return }
        try LaneHLSOfflineStore.shared.remove(id)
        if let url = downloadedFileURL(for: track) { try FileManager.default.removeItem(at: url) }
        downloadedTrackRecords.removeValue(forKey: id)
        downloadedTrackIDs.remove(id)
        UserDefaults.standard.set(Array(downloadedTrackIDs), forKey: "lane.downloads")
        if let data = try? JSONEncoder().encode(downloadedTrackRecords) {
            UserDefaults.standard.set(data, forKey: "lane.downloadedTrackRecords")
        }
    }

    func isDownloaded(_ track: TrackCandidate) -> Bool {
        downloadedFileURL(for: track) != nil
    }

    private func refreshHLSDownloads() {
        for track in LaneHLSOfflineStore.shared.tracks {
            if let id = track.trackID { downloadedTrackIDs.insert(id) }
            rememberResolvedTracks([track])
        }
    }

    // MARK: Local storage

    private func loadLocalState() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: "lane.favorites") ?? [])
        downloadedTrackIDs = Set(UserDefaults.standard.stringArray(forKey: "lane.downloads") ?? [])
        if let data = UserDefaults.standard.data(forKey: "lane.downloadedTrackRecords"),
           let records = try? JSONDecoder().decode([String: LaneDownloadedTrack].self, from: data) {
            downloadedTrackRecords = records
        }
        if let data = UserDefaults.standard.data(forKey: pendingFavoriteStatesKey),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            pendingFavoriteStates = decoded
            for (trackID, shouldBeLiked) in decoded {
                if shouldBeLiked {
                    favorites.insert(trackID)
                } else {
                    favorites.remove(trackID)
                }
            }
        }

        if let data = UserDefaults.standard.data(forKey: "lane.localPlaylists"),
           let decoded = try? JSONDecoder().decode([LocalPlaylist].self, from: data) {
            localPlaylists = decoded
        }

        if let data = UserDefaults.standard.data(forKey: "lane.localTrackStore"),
           let decoded = try? JSONDecoder().decode([String: TrackCandidate].self, from: data) {
            localTrackStore = decoded
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
        if let data = try? JSONEncoder().encode(localTrackStore) {
            UserDefaults.standard.set(data, forKey: "lane.localTrackStore")
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "lane.history")
        }
    }
}
