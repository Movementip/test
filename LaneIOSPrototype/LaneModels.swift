import Foundation

// MARK: - Exact / recovered API models

struct LaneTokenResponse: Decodable {
    let token: String
    let isFirstAuth: Bool?
}

struct LaneBackendConfig: Decodable {
    let service: String?
    let auth: String?
    let telegramBotUsername: String?
    let apiKeyRequired: Bool?
    let musicProvider: String?
}

struct TelegramImportCode: Decodable {
    let code: String
}

struct TrackStreamingResult: Decodable {
    let url: String
    let trackId: String?
    let playbackToken: String?
    let ttl: Int64?
}

struct TrackStatsDTO: Decodable {
    let likesCount: Int64
    let commentsCount: Int64
}

struct LaneShareItem: Decodable {
    let id: String
}


struct LaneTrackLyricsLine: Decodable, Hashable, Identifiable {
    let startTimeMs: String
    let words: String

    var id: String { "\(startTimeMs)|\(words)" }

    var startMilliseconds: Int64 {
        Int64(startTimeMs) ?? 0
    }
}

struct LaneTrackLyrics: Decodable, Hashable {
    let trackId: String
    let lines: [LaneTrackLyricsLine]
    let syncType: String
    let provider: String
    let language: String
}

struct LaneCombinedSearchResponse: Decodable {
    let results: [LaneSearchResultItem]
    let searchToken: String?
}

struct LaneSearchResultItem: Decodable, Identifiable {
    let type: String?
    let track: TrackData?
    let artist: LaneArtist?
    let platform: String?
    let album: LaneAlbum?
    let playlist: LanePlaylist?

    var id: String {
        if let track { return "track|\(track.songId ?? track.title ?? UUID().uuidString)" }
        if let artist { return "artist|\(artist.id ?? artist.name ?? UUID().uuidString)" }
        if let album { return "album|\(album.id ?? album.name ?? UUID().uuidString)" }
        if let playlist { return "playlist|\(playlist.playlistId ?? playlist.playlistName ?? UUID().uuidString)" }
        return UUID().uuidString
    }
}

struct LaneSearchHistoryItem: Identifiable {
    let id: String
    let track: TrackData?
    let artist: LaneArtist?
    let album: LaneAlbum?

    var title: String {
        track?.title ?? artist?.name ?? album?.name ?? ""
    }

    var subtitle: String {
        if let track { return track.artistsDisplayedName ?? "Track" }
        if artist != nil { return "Artist" }
        return "Album • \(album?.artistsDisplayedName ?? "")"
    }

    var imageURL: String? {
        track?.coverUrl ?? artist?.avatarUrl ?? album?.coverUrl
    }

    var platform: String? {
        track?.platform ?? artist?.platform ?? album?.platform
    }
}

struct TrackData: Decodable, Hashable {
    let songId: String?
    let platform: String?
    let title: String?
    let artistsDisplayedName: String?
    let coverUrl: String?
    let duration: String?
    let genre: String?
    let artistAvatars: [String]?
}

struct YandexImportTrack: Identifiable, Hashable, Sendable {
    let yandexID: String
    let originalIndex: Int
    let title: String
    let artists: [String]
    let coverURL: String?

    var id: String { "\(yandexID)|\(originalIndex)" }
    var artistText: String { artists.joined(separator: ", ") }
}

struct LaneRelatedArtist: Decodable, Hashable {
    let id: String?
    let name: String?
    let avatarUrl: String?
    let platform: String?
}

struct LaneArtist: Decodable, Hashable {
    let name: String?
    let id: String?
    let platform: String?
    let description: String?
    let verified: Bool?
    let avatarUrl: String?
    let headerUrl: String?
    let biography: String?
    let topTracks: [String]?
    let recentTracks: [String]?
    let albums: [LaneAlbum]?
    let relatedArtists: [LaneRelatedArtist]?
    let lastUpdated: Int64?

    init(
        name: String? = nil,
        id: String? = nil,
        platform: String? = nil,
        description: String? = nil,
        verified: Bool? = nil,
        avatarUrl: String? = nil,
        headerUrl: String? = nil,
        biography: String? = nil,
        topTracks: [String]? = nil,
        recentTracks: [String]? = nil,
        albums: [LaneAlbum]? = nil,
        relatedArtists: [LaneRelatedArtist]? = nil,
        lastUpdated: Int64? = nil
    ) {
        self.name = name
        self.id = id
        self.platform = platform
        self.description = description
        self.verified = verified
        self.avatarUrl = avatarUrl
        self.headerUrl = headerUrl
        self.biography = biography
        self.topTracks = topTracks
        self.recentTracks = recentTracks
        self.albums = albums
        self.relatedArtists = relatedArtists
        self.lastUpdated = lastUpdated
    }
}

struct LaneAlbum: Decodable, Hashable {
    let name: String?
    let id: String?
    let platform: String?
    let type: String?
    let coverUrl: String?
    let year: String?
    let artists: [String]?
    let artistsDisplayedName: String?
    let tracks: [String]?
    let lastUpdated: Int64?

    init(
        name: String? = nil,
        id: String? = nil,
        platform: String? = nil,
        type: String? = nil,
        coverUrl: String? = nil,
        year: String? = nil,
        artists: [String]? = nil,
        artistsDisplayedName: String? = nil,
        tracks: [String]? = nil,
        lastUpdated: Int64? = nil
    ) {
        self.name = name
        self.id = id
        self.platform = platform
        self.type = type
        self.coverUrl = coverUrl
        self.year = year
        self.artists = artists
        self.artistsDisplayedName = artistsDisplayedName
        self.tracks = tracks
        self.lastUpdated = lastUpdated
    }
}

struct LanePlaylist: Decodable, Hashable {
    let playlistId: String?
    let playlistImageUrl: String?
    let playlistName: String?
    let playlistDescription: String?
    let playlistTracksIds: [String]?
    let playlistTracks: [TrackData]?
    let creatorLid: String?
    let platform: String?
    let tracksCount: Int?
    let visibility: String?
    let collaboratorIds: [String]?
}


struct UserAccountDTO: Decodable, Hashable {
    let telegramId: Int64?
    let displayedName: String?
    let userName: String?
    let laneId: String?
    let email: String?
    let premiumExpiresIn: Int64?
    let avatarUrl: String?
    let headerUrl: String?
    let userPlaylists: [String]?
    let deviceIds: [String]?
    let searchHistory: [String]?
    let equippedBadgeId: String?
    let countryCode: String?
    let isAutoRenewalActive: Bool?
    let statusText: String?
}

struct UserInfoDTO: Decodable, Hashable {
    let displayedName: String?
    let premiumExpiresIn: Int64?
    let userName: String?
    let platform: String?
    let avatarUrl: String?
    let headerUrl: String?
    let laneId: String?
    let statusTrack: TrackData?
    let statusTrackId: String?
    let publicPlaylists: [LanePlaylist]?
    let followersCount: Int64?
    let followingCount: Int64?
    let isFollowing: Bool?
    let equippedBadgeId: String?
    let statusText: String?
}

struct PaginatedResult<T: Decodable>: Decodable {
    let items: [T]
    let totalItems: Int64?
    let page: Int?
    let pageSize: Int?
    let totalPages: Int?

    private enum CodingKeys: String, CodingKey {
        case items
        case content
        case data
        case results
        case totalItems
        case total
        case page
        case pageSize
        case size
        case totalPages
        case pages
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)

        items =
            (try? box.decode([T].self, forKey: .items)) ??
            (try? box.decode([T].self, forKey: .content)) ??
            (try? box.decode([T].self, forKey: .data)) ??
            (try? box.decode([T].self, forKey: .results)) ??
            []

        totalItems =
            (try? box.decode(Int64.self, forKey: .totalItems)) ??
            (try? box.decode(Int64.self, forKey: .total))

        page = try? box.decode(Int.self, forKey: .page)

        pageSize =
            (try? box.decode(Int.self, forKey: .pageSize)) ??
            (try? box.decode(Int.self, forKey: .size))

        totalPages =
            (try? box.decode(Int.self, forKey: .totalPages)) ??
            (try? box.decode(Int.self, forKey: .pages))
    }
}

struct LaneTrackCommentDTO: Decodable, Identifiable {
    let id: String
    let userName: String?
    let userAvatar: String?
    let userId: String?
    let text: String?
    let likesCount: Int64?
    let repliesCount: Int64?
    let isLiked: Bool?
    let attachment: String?
    let timestamp: Int64?
    let parentId: String?
    let userEquippedBadgeImageUrl: String?
    let replyToUserId: String?
    let replyToUserName: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case userName
        case userAvatar
        case userId
        case text
        case likesCount
        case repliesCount
        case isLiked
        case attachment
        case timestamp
        case parentId
        case userEquippedBadgeImageUrl
        case replyToUserId
        case replyToUserName
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)

        if let string = try? box.decode(String.self, forKey: .id) {
            id = string
        } else if let number = try? box.decode(Int64.self, forKey: .id) {
            id = String(number)
        } else {
            id = UUID().uuidString
        }

        userName = try? box.decodeIfPresent(String.self, forKey: .userName)
        userAvatar = try? box.decodeIfPresent(String.self, forKey: .userAvatar)

        if let string = try? box.decode(String.self, forKey: .userId) {
            userId = string
        } else if let number = try? box.decode(Int64.self, forKey: .userId) {
            userId = String(number)
        } else {
            userId = nil
        }

        text = try? box.decodeIfPresent(String.self, forKey: .text)

        if let value = try? box.decode(Int64.self, forKey: .likesCount) {
            likesCount = value
        } else if let value = try? box.decode(Int.self, forKey: .likesCount) {
            likesCount = Int64(value)
        } else {
            likesCount = nil
        }

        if let value = try? box.decode(Int64.self, forKey: .repliesCount) {
            repliesCount = value
        } else if let value = try? box.decode(Int.self, forKey: .repliesCount) {
            repliesCount = Int64(value)
        } else {
            repliesCount = nil
        }

        isLiked = try? box.decodeIfPresent(Bool.self, forKey: .isLiked)
        attachment = try? box.decodeIfPresent(String.self, forKey: .attachment)

        if let value = try? box.decode(Int64.self, forKey: .timestamp) {
            timestamp = value
        } else if let value = try? box.decode(Int.self, forKey: .timestamp) {
            timestamp = Int64(value)
        } else {
            timestamp = nil
        }

        parentId = try? box.decodeIfPresent(String.self, forKey: .parentId)
        userEquippedBadgeImageUrl = try? box.decodeIfPresent(String.self, forKey: .userEquippedBadgeImageUrl)
        replyToUserId = try? box.decodeIfPresent(String.self, forKey: .replyToUserId)
        replyToUserName = try? box.decodeIfPresent(String.self, forKey: .replyToUserName)
    }
}

// MARK: - iOS UI models

struct TrackCandidate: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let subtitle: String
    let trackID: String?
    let refID: String?
    let platform: String
    let coverURL: String?
    let duration: String?
    let genre: String?
    let artistAvatars: [String]?

    init(
        id: String? = nil,
        title: String,
        subtitle: String,
        trackID: String?,
        refID: String? = nil,
        platform: String = "",
        coverURL: String? = nil,
        duration: String? = nil,
        genre: String? = nil,
        artistAvatars: [String]? = nil
    ) {
        self.id = id ?? trackID ?? refID ?? "\(title)|\(subtitle)"
        self.title = title
        self.subtitle = subtitle
        self.trackID = trackID
        self.refID = refID
        self.platform = platform
        self.coverURL = coverURL
        self.duration = duration
        self.genre = genre
        self.artistAvatars = artistAvatars
    }

    init(_ track: TrackData, refID: String? = nil) {
        self.init(
            title: track.title ?? "Unknown track",
            subtitle: track.artistsDisplayedName ?? "Unknown artist",
            trackID: track.songId,
            refID: refID,
            platform: track.platform ?? "",
            coverURL: track.coverUrl,
            duration: track.duration,
            genre: track.genre,
            artistAvatars: track.artistAvatars
        )
    }
}

struct LaneCardItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let imageURL: String?
    let kind: String
    let backendID: String?
    let platform: String?
}


enum LaneHomeSectionType: String, Hashable {
    case personalMix = "PERSONAL_MIX"
    case chart = "CHART"
    case discovery = "DISCOVERY"
    case history = "HISTORY"
    case promotion = "PROMOTION"
    case utility = "UTILITY"
    case rediscover = "REDISCOVER"
    case unknown = "UNKNOWN"

    init(raw: String?) {
        self = LaneHomeSectionType(rawValue: raw?.uppercased() ?? "") ?? .unknown
    }
}

enum LaneHomeRenderType: String, Hashable {
    case horizontalList = "HORIZONTAL_LIST"
    case grid2x2 = "GRID_2X2"
    case fullWidth = "FULL_WIDTH"
    case verticalList = "VERTICAL_LIST"

    init(raw: String?) {
        self = LaneHomeRenderType(rawValue: raw?.uppercased() ?? "") ?? .horizontalList
    }
}

struct LaneHomeBanner: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let imageURL: String
    let backgroundColor: String
    let actionURL: String
    let buttonText: String?
}

struct LaneHomeItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case playlist
        case chart
        case banner
    }

    let id: String
    let kind: Kind
    let playlist: LanePlaylist?
    let banner: LaneHomeBanner?
}

struct LaneHomeSection: Identifiable, Hashable {
    let id: String
    let title: String?
    let subtitle: String?
    let type: LaneHomeSectionType
    let renderType: LaneHomeRenderType
    let content: [LaneHomeItem]
}

struct LocalPlaylist: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var trackKeys: [String] = []
}

enum SearchFilter: String, CaseIterable, Identifiable {
    // Exact SearchFilter enum recovered from Lane Android 1.4.7:
    // ALL, SPOTIFY, SOUNDCLOUD, TRACKS, PLAYLISTS, ALBUMS.
    case all = "All"
    case spotify = "Spotify"
    case soundcloud = "SoundCloud"
    case tracks = "Tracks"
    case playlists = "Playlists"
    case albums = "Albums"

    var id: String { rawValue }
}

enum AudioQualityChoice: String, CaseIterable, Identifiable {
    case basic = "BASIC"
    case high = "HIGH"
    case ultra = "ULTRA"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: return "Basic"
        case .high: return "High"
        case .ultra: return "Ultra"
        }
    }

    var detail: String {
        switch self {
        case .basic: return "128 kbps"
        case .high: return "192 kbps"
        case .ultra: return "320 kbps"
        }
    }
}

// MARK: - Flexible JSON adapters

enum JSONProbe {
    static func tracks(_ value: Any?) -> [TrackCandidate] {
        var output: [TrackCandidate] = []
        walkTracks(value, &output)
        var seen = Set<String>()
        return output.filter { seen.insert($0.id).inserted }
    }

    static func cards(_ value: Any?, preferredKind: String = "item") -> [LaneCardItem] {
        var output: [LaneCardItem] = []
        walkCards(value, preferredKind: preferredKind, &output)
        var seen = Set<String>()
        return output.filter { seen.insert($0.id).inserted }
    }


    static func homeSections(_ value: Any?) -> [LaneHomeSection] {
        guard let sectionValues = locateHomeSections(value) else { return [] }

        return sectionValues.compactMap { raw in
            guard let dict = raw as? [String: Any] else { return nil }

            let id = firstString(dict, ["id", "sectionId"]) ?? UUID().uuidString
            let title = firstString(dict, ["title"])
            let subtitle = firstString(dict, ["subtitle"])
            let type = LaneHomeSectionType(raw: firstString(dict, ["type", "sectionType"]))
            let renderType = LaneHomeRenderType(raw: firstString(dict, ["renderType", "render_type"]))
            let rawContent = (dict["content"] as? [Any]) ?? (dict["items"] as? [Any]) ?? []

            let items: [LaneHomeItem] = rawContent.compactMap { rawItem in
                guard let item = rawItem as? [String: Any] else { return nil }

                let discriminator = (
                    firstString(item, ["type", "itemType", "kind", "_type", "@type"]) ?? ""
                ).lowercased()

                if let playlistObject = item["playlist"] as? [String: Any],
                   let playlist = decodeObject(LanePlaylist.self, from: playlistObject) {
                    let itemID = firstString(item, ["id"]) ?? playlist.playlistId ?? UUID().uuidString
                    let kind: LaneHomeItem.Kind =
                        type == .chart || discriminator.contains("chart") ? .chart : .playlist
                    return LaneHomeItem(id: itemID, kind: kind, playlist: playlist, banner: nil)
                }

                if looksLikePlaylist(item),
                   let playlist = decodeObject(LanePlaylist.self, from: item) {
                    let itemID = firstString(item, ["id"]) ?? playlist.playlistId ?? UUID().uuidString
                    let kind: LaneHomeItem.Kind =
                        type == .chart || discriminator.contains("chart") ? .chart : .playlist
                    return LaneHomeItem(id: itemID, kind: kind, playlist: playlist, banner: nil)
                }

                if discriminator.contains("banner") ||
                   item["imageUrl"] != nil ||
                   item["actionUrl"] != nil {
                    guard let bannerID = firstString(item, ["id"]),
                          let bannerTitle = firstString(item, ["title"]),
                          let description = firstString(item, ["description"]),
                          let imageURL = firstString(item, ["imageUrl", "image_url"]),
                          let actionURL = firstString(item, ["actionUrl", "action_url"]) else {
                        return nil
                    }

                    let banner = LaneHomeBanner(
                        id: bannerID,
                        title: bannerTitle,
                        description: description,
                        imageURL: imageURL,
                        backgroundColor: firstString(item, ["backgroundColor", "background_color"]) ?? "#121212",
                        actionURL: actionURL,
                        buttonText: firstString(item, ["buttonText", "button_text"])
                    )
                    return LaneHomeItem(id: bannerID, kind: .banner, playlist: nil, banner: banner)
                }

                return nil
            }

            return LaneHomeSection(
                id: id,
                title: title,
                subtitle: subtitle,
                type: type,
                renderType: renderType,
                content: items
            )
        }
        .filter { !$0.content.isEmpty }
    }

    private static func locateHomeSections(_ value: Any?) -> [Any]? {
        if let dict = value as? [String: Any] {
            if let sections = dict["sections"] as? [Any] {
                return sections
            }

            for key in ["data", "feed", "result", "home", "payload"] {
                if let sections = locateHomeSections(dict[key]) {
                    return sections
                }
            }

            for child in dict.values {
                if let sections = locateHomeSections(child) {
                    return sections
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let sections = locateHomeSections(child) {
                    return sections
                }
            }
        }
        return nil
    }

    private static func looksLikePlaylist(_ dict: [String: Any]) -> Bool {
        dict["playlistId"] != nil ||
        dict["playlistName"] != nil ||
        dict["playlistTracks"] != nil ||
        dict["playlistTracksIds"] != nil
    }

    private static func decodeObject<T: Decodable>(_ type: T.Type, from object: [String: Any]) -> T? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func token(_ value: Any?) -> String? {
        if let dict = value as? [String: Any] {
            for key in ["token", "accessToken", "access_token", "bearerToken"] {
                if let string = dict[key] as? String, !string.isEmpty { return string }
            }
            for value in dict.values {
                if let result = token(value) { return result }
            }
        } else if let array = value as? [Any] {
            for value in array {
                if let result = token(value) { return result }
            }
        }
        return nil
    }

    static func pretty(_ value: Any?) -> String {
        guard let value else { return "" }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }

    private static func walkTracks(_ value: Any?, _ output: inout [TrackCandidate]) {
        if let dict = value as? [String: Any] {
            let title = firstString(dict, ["title", "name", "trackName", "track_name"])
            let artist = firstString(dict, ["artistsDisplayedName", "artist", "artistName", "artist_name", "author", "username"])
            let trackID = firstString(dict, ["songId", "trackId", "track_id"])
            let refID = firstString(dict, ["refId", "ref_id"])
            let platform = firstString(dict, ["platform", "source"]) ?? ""
            let cover = http(firstString(dict, ["coverUrl", "cover_url", "artworkUrl", "artwork_url", "image", "photoUrl", "avatarUrl"]))
            let duration = firstString(dict, ["duration", "durationText"])
            let genre = firstString(dict, ["genre"])

            if let title, trackID != nil || artist != nil {
                output.append(
                    TrackCandidate(
                        title: title,
                        subtitle: artist ?? "Track",
                        trackID: trackID,
                        refID: refID,
                        platform: platform,
                        coverURL: cover,
                        duration: duration,
                        genre: genre
                    )
                )
            }

            for child in dict.values {
                walkTracks(child, &output)
            }
        } else if let array = value as? [Any] {
            for child in array {
                walkTracks(child, &output)
            }
        }
    }

    private static func walkCards(_ value: Any?, preferredKind: String, _ output: inout [LaneCardItem]) {
        if let dict = value as? [String: Any] {
            let backendID = firstString(dict, ["playlistId", "albumId", "artistId", "laneId", "id", "userId"])
            let title = firstString(dict, ["playlistName", "albumName", "artistName", "displayedName", "displayName", "name", "title", "username", "userName"])
            let subtitle = firstString(dict, ["playlistDescription", "description", "artistsDisplayedName", "statusText", "status", "username", "userName"]) ?? ""
            let image = http(firstString(dict, ["playlistImageUrl", "coverUrl", "cover_url", "imageUrl", "avatarUrl", "photoUrl", "image"]))
            let platform = firstString(dict, ["platform", "source"])

            if let title, backendID != nil || image != nil {
                let id = backendID ?? "\(preferredKind)|\(title)|\(subtitle)"
                output.append(.init(id: id, title: title, subtitle: subtitle, imageURL: image, kind: preferredKind, backendID: backendID, platform: platform))
            }

            for child in dict.values {
                walkCards(child, preferredKind: preferredKind, &output)
            }
        } else if let array = value as? [Any] {
            for child in array {
                walkCards(child, preferredKind: preferredKind, &output)
            }
        }
    }

    private static func firstString(_ dict: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let string = dict[key] as? String, !string.isEmpty { return string }
            if let number = dict[key] as? NSNumber { return number.stringValue }
        }
        return nil
    }

    private static func http(_ string: String?) -> String? {
        guard let string,
              let url = URL(string: string),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return string
    }
}
