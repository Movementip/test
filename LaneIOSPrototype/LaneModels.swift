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

    init(
        id: String? = nil,
        title: String,
        subtitle: String,
        trackID: String?,
        refID: String? = nil,
        platform: String = "",
        coverURL: String? = nil,
        duration: String? = nil,
        genre: String? = nil
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
    }

    init(_ track: TrackData) {
        self.init(
            title: track.title ?? "Unknown track",
            subtitle: track.artistsDisplayedName ?? "Unknown artist",
            trackID: track.songId,
            platform: track.platform ?? "",
            coverURL: track.coverUrl,
            duration: track.duration,
            genre: track.genre
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

struct LocalPlaylist: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var trackKeys: [String] = []
}

enum SearchFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case tracks = "Tracks"
    case artists = "Artists"
    case albums = "Albums"
    case playlists = "Playlists"

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
