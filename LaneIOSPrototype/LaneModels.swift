import Foundation

struct LaneTokenResponse: Decodable {
    let token: String
    let isFirstAuth: Bool?
}

struct TrackStreamingResult: Decodable {
    let url: String
    let trackId: String?
    let playbackToken: String?
    let ttl: Int64?
}

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
        self.id = id ?? trackID ?? refID ?? "(title)|(subtitle)"
        self.title = title
        self.subtitle = subtitle
        self.trackID = trackID
        self.refID = refID
        self.platform = platform
        self.coverURL = coverURL
        self.duration = duration
        self.genre = genre
    }
}

struct LaneCardItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let imageURL: String?
    let kind: String
    let backendID: String?
}

struct TrackStatsDTO: Decodable {
    let likesCount: Int64
    let commentsCount: Int64
}

struct PlaylistDraft {
    var name = ""
    var description = ""
    var imageURL = ""
}

enum LaneSection: String, CaseIterable, Identifiable {
    case tracks = "Tracks"
    case playlists = "Playlists"
    case albums = "Albums"
    case artists = "Artists"
    case users = "Users"

    var id: String { rawValue }
}

enum AudioQualityChoice: String, CaseIterable, Identifiable {
    case basic = "BASIC"
    case high = "HIGH"
    case ultra = "ULTRA"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .basic: return "128 kbps"
        case .high: return "192 kbps"
        case .ultra: return "320 kbps"
        }
    }
}

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

    static func string(_ value: Any?, keys: [String]) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        return firstString(dict, keys)
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
            let title = firstString(dict, ["playlistName", "albumName", "artistName", "displayName", "name", "title", "username"])
            let subtitle = firstString(dict, ["playlistDescription", "description", "artistsDisplayedName", "status", "username"]) ?? ""
            let image = http(firstString(dict, ["playlistImageUrl", "coverUrl", "cover_url", "imageUrl", "avatarUrl", "photoUrl", "image"]))
            if let title, backendID != nil || image != nil {
                let id = backendID ?? "(preferredKind)|(title)|(subtitle)"
                output.append(.init(id: id, title: title, subtitle: subtitle, imageURL: image, kind: preferredKind, backendID: backendID))
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
