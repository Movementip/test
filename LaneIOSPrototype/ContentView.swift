import SwiftUI
import UIKit

private let lanePink = Color(red: 1.0, green: 130.0 / 255.0, blue: 132.0 / 255.0)
private let laneBackground = Color(red: 14.0 / 255.0, green: 14.0 / 255.0, blue: 14.0 / 255.0)
private let laneCard = Color.white.opacity(0.07)

private struct BundlePNG: View {
    let name: String
    var contentMode: ContentMode = .fit

    var body: some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image.withRenderingMode(.alwaysOriginal))
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: contentMode)
        } else {
            ZStack {
                Color.clear
                switch name {
                case "telegram":
                    Image(systemName: "paperplane.fill").foregroundStyle(.blue)
                case "lane_logo_3d_wave":
                    Image(systemName: "waveform").foregroundStyle(lanePink)
                case "lane_3d_logo_playlist":
                    Image(systemName: "music.note.list").foregroundStyle(lanePink)
                case "import_tracks_background_card":
                    Image(systemName: "square.and.arrow.down.fill").foregroundStyle(lanePink)
                case "lane_pro_banner":
                    Image(systemName: "sparkles").foregroundStyle(lanePink)
                default:
                    Image(systemName: "music.note").foregroundStyle(.white)
                }
            }
        }
    }
}

private struct TelegramIcon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 11.0 / 255.0, green: 45.0 / 255.0, blue: 66.0 / 255.0))
            Image(systemName: "paperplane.fill")
                .font(.system(size: size * 0.47, weight: .semibold))
                .foregroundStyle(Color(red: 3.0 / 255.0, green: 155.0 / 255.0, blue: 229.0 / 255.0))
                .rotationEffect(.degrees(-8))
        }
        .frame(width: size, height: size)
    }
}


struct ContentView: View {
    @EnvironmentObject private var session: LaneSession
    @State private var selectedTab = 0
    @State private var showPlayer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 1:
                    SearchScreen(showPlayer: $showPlayer)
                case 2:
                    LibraryScreen(showPlayer: $showPlayer)
                default:
                    HomeScreen(showPlayer: $showPlayer)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 67)

            VStack(spacing: 0) {
                if session.currentTrack != nil {
                    MiniPlayerView(showPlayer: $showPlayer)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                }

                LaneBottomBar(selection: $selectedTab)
            }
        }
        .background(laneBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showPlayer) {
            APKFullPlayerView()
                .environmentObject(session)
        }
        .task {
            if !session.isGuest && session.homeTracks.isEmpty {
                await session.refreshAfterLogin()
            }
        }
    }
}

private struct LaneBottomBar: View {
    @Binding var selection: Int

    var body: some View {
        HStack {
            bottomButton(index: 0, title: "Home", asset: selection == 0 ? "bottom_main" : "bottom_main_unselected")
            Spacer()
            bottomButton(index: 1, title: "Search", asset: "bottom_search")
            Spacer()
            bottomButton(index: 2, title: "Library", asset: "bottom_library")
        }
        .padding(.horizontal, 46)
        .padding(.top, 9)
        .padding(.bottom, 5)
        .frame(height: 67)
        .background(
            Color(red: 27.0 / 255.0, green: 27.0 / 255.0, blue: 27.0 / 255.0)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.055))
                .frame(height: 1)
        }
    }

    private func bottomButton(index: Int, title: String, asset: String) -> some View {
        let active = selection == index
        let tint = active ? lanePink : Color.white.opacity(0.48)

        return Button {
            selection = index
        } label: {
            VStack(spacing: 3) {
                APKTemplateIcon(name: asset, size: 26, color: tint)
                    .frame(height: 27)

                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(tint)
            }
            .frame(minWidth: 58)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Home

private struct HomeScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Binding var showPlayer: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    HomeHeader()

                    if session.isGuest {
                        TelegramLoginCard()
                    } else {
                        if session.busy && session.homeSections.isEmpty && session.homeTracks.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(lanePink)
                                Spacer()
                            }
                            .padding(.vertical, 24)
                        }

                        if !session.homeSections.isEmpty {
                            APKHomeFeedView(
                                sections: session.homeSections,
                                showPlayer: $showPlayer
                            )
                        } else {
                            // Compatibility fallback for older Lane feed payloads.
                            if !session.homeTracks.isEmpty {
                                TrackSection(
                                    title: "For you",
                                    subtitle: "Picked for your listening",
                                    tracks: Array(session.homeTracks.prefix(12)),
                                    showPlayer: $showPlayer
                                )
                            }

                            if !session.recentTracks.isEmpty {
                                TrackSection(
                                    title: "Recently played",
                                    subtitle: nil,
                                    tracks: Array(session.recentTracks.prefix(10)),
                                    showPlayer: $showPlayer
                                )
                            }

                            if !session.serverPlaylists.isEmpty {
                                CardShelf(
                                    title: "Your playlists",
                                    cards: session.serverPlaylists.map {
                                        LaneCardItem(
                                            id: $0.playlistId ?? UUID().uuidString,
                                            title: $0.playlistName ?? "Playlist",
                                            subtitle: $0.playlistDescription ?? "\($0.tracksCount ?? 0) tracks",
                                            imageURL: $0.playlistImageUrl,
                                            kind: "playlist",
                                            backendID: $0.playlistId,
                                            platform: $0.platform
                                        )
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.bottom, 22)
            }
            .background(laneBackground)
            .refreshable {
                if !session.isGuest {
                    await session.refreshAfterLogin()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct HomeHeader: View {
    @EnvironmentObject private var session: LaneSession

    var body: some View {
        HStack(spacing: 0) {
            NavigationLink {
                ProfileScreen()
            } label: {
                AvatarView(url: session.account?.avatarUrl, size: 36)
            }
            .buttonStyle(.plain)

            Spacer()
                .frame(width: 20)

            APKLaneHeaderTitle(
                subtitle: session.account?.displayedName ?? session.account?.userName ?? ""
            )

            Spacer()

            if !session.isGuest {
                NavigationLink {
                    NotificationsScreen()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)

                        if !session.notificationCards.isEmpty {
                            Circle()
                                .fill(lanePink)
                                .frame(width: 8, height: 8)
                                .offset(x: -4, y: 5)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

private struct TelegramLoginCard: View {
    var body: some View {
        NavigationLink {
            TelegramLoginScreen()
        } label: {
            HStack(spacing: 16) {
                TelegramIcon(size: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sign in to Lane")
                        .font(.headline)
                    Text("Continue with Telegram to restore your library, friends and playlists.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(laneCard, in: RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search

private struct SearchScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Binding var showPlayer: Bool

    @State private var query = ""
    @State private var selectedFilter: SearchFilter = .all

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 0) {
                        NavigationLink {
                            ProfileScreen()
                        } label: {
                            AvatarView(url: session.account?.avatarUrl, size: 36)
                        }
                        .buttonStyle(.plain)

                        Spacer().frame(width: 20)

                        APKLaneHeaderTitle(subtitle: "Search")

                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)

                        TextField("Search for people, tracks, and albums", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { session.search(query) }

                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
                    .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SearchFilter.allCases) { filter in
                                Button {
                                    selectedFilter = filter
                                } label: {
                                    Text(filter.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            selectedFilter == filter ? lanePink : Color.white.opacity(0.08),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(selectedFilter == filter ? Color.black : Color.white)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 10)

                if session.isGuest {
                    Spacer()
                    VStack(spacing: 16) {
                        EmptyLaneView(
                            icon: "person.crop.circle.badge.exclamationmark",
                            title: "Sign in to search",
                            subtitle: "Lane search uses your Telegram authorization token."
                        )
                        TelegramLoginCard()
                    }
                    Spacer()
                } else if session.busy && session.searchTracks.isEmpty {
                    Spacer()
                    ProgressView()
                        .tint(lanePink)
                    Spacer()
                } else if hasSearchResults {
                    searchResults
                } else {
                    Spacer()
                    EmptyLaneView(
                        icon: "magnifyingglass",
                        title: query.isEmpty ? "What are we looking for today?" : "Nothing found",
                        subtitle: query.isEmpty ? "A track, artist, or album?" : session.output
                    )
                    Spacer()
                }
            }
            .background(laneBackground)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var hasSearchResults: Bool {
        !session.searchResultItems.isEmpty ||
        !session.searchTracks.isEmpty ||
        !session.searchArtists.isEmpty ||
        !session.searchAlbums.isEmpty ||
        !session.searchPlaylists.isEmpty
    }

    private func candidate(for track: TrackData) -> TrackCandidate {
        if let songId = track.songId,
           let existing = session.searchTracks.first(where: { $0.trackID == songId }) {
            return existing
        }
        return TrackCandidate(track)
    }

    private func platform(of item: LaneSearchResultItem) -> String {
        (
            item.platform ??
            item.track?.platform ??
            item.artist?.platform ??
            item.album?.platform ??
            item.playlist?.platform ??
            ""
        ).lowercased()
    }

    private func matchesPlatform(_ item: LaneSearchResultItem, _ name: String) -> Bool {
        platform(of: item).contains(name.lowercased())
    }

    @ViewBuilder
    private func mixedSearchRow(_ item: LaneSearchResultItem) -> some View {
        if let track = item.track {
            let value = candidate(for: track)
            APKSearchTrackRow(
                track: value,
                onTap: {
                    session.queue = session.searchTracks
                    session.currentIndex = session.searchTracks.firstIndex(of: value)
                    session.requestStream(for: value)
                    showPlayer = true
                },
                onMore: {
                    session.addToQueue(value)
                }
            )
        } else if let artist = item.artist {
            APKSearchArtistRow(artist: artist)
        } else if let album = item.album {
            APKSearchAlbumRow(album: album)
        } else if let playlist = item.playlist {
            NavigationLink {
                PlaylistDetailScreen(playlist: playlist, showPlayer: $showPlayer)
            } label: {
                APKSearchPlaylistRow(playlist: playlist)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                switch selectedFilter {
                case .all:
                    if !session.searchResultItems.isEmpty {
                        ForEach(session.searchResultItems) { item in
                            mixedSearchRow(item)
                        }
                    } else {
                        ForEach(session.searchTracks) { track in
                            APKSearchTrackRow(
                                track: track,
                                onTap: {
                                    session.queue = session.searchTracks
                                    session.currentIndex = session.searchTracks.firstIndex(of: track)
                                    session.requestStream(for: track)
                                    showPlayer = true
                                },
                                onMore: { session.addToQueue(track) }
                            )
                        }

                        ForEach(Array(session.searchArtists.enumerated()), id: \.offset) { _, artist in
                            APKSearchArtistRow(artist: artist)
                        }

                        ForEach(Array(session.searchAlbums.enumerated()), id: \.offset) { _, album in
                            APKSearchAlbumRow(album: album)
                        }

                        ForEach(Array(session.searchPlaylists.enumerated()), id: \.offset) { _, playlist in
                            NavigationLink {
                                PlaylistDetailScreen(playlist: playlist, showPlayer: $showPlayer)
                            } label: {
                                APKSearchPlaylistRow(playlist: playlist)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                case .spotify:
                    ForEach(session.searchResultItems.filter { matchesPlatform($0, "spotify") }) { item in
                        mixedSearchRow(item)
                    }

                case .soundcloud:
                    ForEach(session.searchResultItems.filter { matchesPlatform($0, "soundcloud") }) { item in
                        mixedSearchRow(item)
                    }

                case .tracks:
                    ForEach(session.searchTracks) { track in
                        APKSearchTrackRow(
                            track: track,
                            onTap: {
                                session.queue = session.searchTracks
                                session.currentIndex = session.searchTracks.firstIndex(of: track)
                                session.requestStream(for: track)
                                showPlayer = true
                            },
                            onMore: { session.addToQueue(track) }
                        )
                    }

                case .playlists:
                    ForEach(Array(session.searchPlaylists.enumerated()), id: \.offset) { _, playlist in
                        NavigationLink {
                            PlaylistDetailScreen(playlist: playlist, showPlayer: $showPlayer)
                        } label: {
                            APKSearchPlaylistRow(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }

                case .albums:
                    ForEach(Array(session.searchAlbums.enumerated()), id: \.offset) { _, album in
                        APKSearchAlbumRow(album: album)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, session.currentTrack == nil ? 24 : 90)
        }
        .background(laneBackground)
    }

}

// MARK: - Library

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case playlists = "Playlists"
    case albums = "Albums"
    case artists = "Artists"

    var id: String { rawValue }
}

private struct LibraryScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Binding var showPlayer: Bool

    @State private var filter: LibraryFilter = .all
    @State private var showCreatePlaylist = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    LibraryHeader(showCreatePlaylist: $showCreatePlaylist)
                        .padding(.bottom, 10)

                    if session.isGuest {
                        TelegramLoginCard()
                            .padding(.top, 8)
                    } else {
                        // Android Lane 1.4.7: top bar -> filter chips -> import card ->
                        // divider -> filtered library rows.
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(LibraryFilter.allCases) { item in
                                    Button {
                                        filter = item
                                    } label: {
                                        Text(item.rawValue)
                                            .font(.system(size: 14, weight: .semibold))
                                            .padding(.horizontal, 14)
                                            .frame(height: 36)
                                            .background(
                                                filter == item ? lanePink : Color.white.opacity(0.08),
                                                in: Capsule()
                                            )
                                            .foregroundStyle(filter == item ? .black : .white)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 14)

                        NavigationLink {
                            TelegramImportScreen()
                        } label: {
                            APKImportTracksCard()
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(.plain)

                        Color.white.opacity(0.14)
                            .frame(height: 1)
                            .padding(.horizontal, 10)
                            .padding(.top, 20)
                            .padding(.bottom, 20)

                        libraryContents
                    }
                }
                .padding(.bottom, 22)
            }
            .background(laneBackground)
            .refreshable {
                if !session.isGuest {
                    session.refreshLibrary()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCreatePlaylist) {
                CreatePlaylistSheet()
            }
        }
    }

    @ViewBuilder
    private var libraryContents: some View {
        if filter == .all || filter == .playlists {
            VStack(spacing: 2) {
                NavigationLink {
                    FavoriteTracksScreen(showPlayer: $showPlayer)
                } label: {
                    APKFavoritePlaylistCard(trackCount: session.favorites.count)
                }
                .buttonStyle(.plain)

                ForEach(Array(session.serverPlaylists.enumerated()), id: \.offset) { _, playlist in
                    NavigationLink {
                        PlaylistDetailScreen(playlist: playlist, showPlayer: $showPlayer)
                    } label: {
                        PlaylistRow(playlist: playlist)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if filter == .all || filter == .albums {
            if !session.serverAlbums.isEmpty {
                LibrarySectionTitle(title: "Albums", count: session.serverAlbums.count)
                    .padding(.top, 10)

                VStack(spacing: 2) {
                    ForEach(Array(session.serverAlbums.enumerated()), id: \.offset) { _, album in
                        AlbumRow(album: album)
                    }
                }
                .padding(.horizontal, 8)
            }
        }

        if filter == .all || filter == .artists {
            if !session.serverArtists.isEmpty {
                LibrarySectionTitle(title: "Artists", count: session.serverArtists.count)
                    .padding(.top, 10)

                VStack(spacing: 2) {
                    ForEach(Array(session.serverArtists.enumerated()), id: \.offset) { _, artist in
                        ArtistRow(artist: artist)
                    }
                }
                .padding(.horizontal, 8)
            }
        }

        if filter == .all && !session.recentTracks.isEmpty {
            LibrarySectionTitle(title: "Recently played", count: session.recentTracks.count)
                .padding(.top, 10)

            VStack(spacing: 2) {
                ForEach(session.recentTracks.prefix(12)) { track in
                    TrackRow(track: track, showPlayer: $showPlayer)
                }
            }
            .padding(.horizontal, 8)
        }

        if session.serverPlaylists.isEmpty &&
            session.serverAlbums.isEmpty &&
            session.serverArtists.isEmpty &&
            session.recentTracks.isEmpty &&
            session.favorites.isEmpty {
            EmptyLaneView(
                icon: "square.stack",
                title: "Your Library",
                subtitle: "Saved music and playlists will appear here."
            )
            .padding(.top, 30)
        }
    }
}

private struct LibraryHeader: View {
    @EnvironmentObject private var session: LaneSession
    @Binding var showCreatePlaylist: Bool

    var body: some View {
        HStack(spacing: 0) {
            NavigationLink {
                ProfileScreen()
            } label: {
                AvatarView(url: session.account?.avatarUrl, size: 36)
            }
            .buttonStyle(.plain)

            Spacer().frame(width: 20)

            APKLaneHeaderTitle(subtitle: "Library")

            Spacer()

            Button {
                showCreatePlaylist = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Player

private struct MiniPlayerView: View {
    @EnvironmentObject private var session: LaneSession
    @Binding var showPlayer: Bool

    var body: some View {
        if let track = session.currentTrack {
            HStack(spacing: 11) {
                ArtworkView(url: track.coverURL, size: 44, radius: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(track.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    session.toggleFavoriteCurrent()
                } label: {
                    Image(systemName: session.isFavorite(track) ? "heart.fill" : "heart")
                        .foregroundStyle(session.isFavorite(track) ? lanePink : .white)
                }

                Button {
                    session.togglePlayback()
                } label: {
                    Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 34, height: 34)
                }
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
            .onTapGesture { showPlayer = true }
        }
    }
}

private struct FullPlayerView: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var showComments = false
    @State private var showTrackInfo = false

    var body: some View {
        NavigationStack {
            ZStack {
                laneBackground.ignoresSafeArea()

                if let track = session.currentTrack {
                    VStack(spacing: 24) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 42, height: 5)
                            .padding(.top, 8)

                        HStack {
                            Button { dismiss() } label: {
                                Image(systemName: "chevron.down")
                                    .font(.headline)
                                    .frame(width: 38, height: 38)
                            }

                            Spacer()
                            Text("Now Playing")
                                .font(.headline)
                            Spacer()

                            Menu {
                                Button("Add to queue", systemImage: "text.badge.plus") {
                                    session.addToQueue(track)
                                }
                                Button("Play next", systemImage: "text.insert") {
                                    session.playNext(track)
                                }
                                Button("Download track", systemImage: "arrow.down.circle") {
                                    session.downloadTrack(track)
                                }
                                Button("Track info", systemImage: "info.circle") {
                                    showTrackInfo = true
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.headline)
                                    .frame(width: 38, height: 38)
                            }
                        }
                        .padding(.horizontal, 16)

                        ArtworkView(url: track.coverURL, size: 310, radius: 22)
                            .shadow(color: .black.opacity(0.35), radius: 28, y: 18)

                        VStack(spacing: 8) {
                            Text(track.title)
                                .font(.title2.bold())
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            Text(track.subtitle)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            if let genre = track.genre, !genre.isEmpty {
                                Text(genre)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 28)

                        HStack(spacing: 40) {
                            Button {
                                session.toggleFavoriteCurrent()
                            } label: {
                                Image(systemName: session.isFavorite(track) ? "heart.fill" : "heart")
                                    .font(.title2)
                                    .foregroundStyle(session.isFavorite(track) ? lanePink : .white)
                            }

                            Button { session.previous() } label: {
                                Image(systemName: "backward.fill")
                                    .font(.title2)
                            }

                            Button {
                                session.togglePlayback()
                            } label: {
                                Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 27, weight: .bold))
                                    .foregroundStyle(.black)
                                    .frame(width: 68, height: 68)
                                    .background(Color.white, in: Circle())
                            }

                            Button { session.next() } label: {
                                Image(systemName: "forward.fill")
                                    .font(.title2)
                            }

                            Button {
                                showQueue = true
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(.title2)
                            }
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 28) {
                            PlayerAction(icon: "text.quote", title: "Lyrics") {
                                session.loadLyrics(track)
                            }
                            PlayerAction(icon: "bubble.left.and.bubble.right.fill", title: "Comments") {
                                session.loadComments(for: track)
                                showComments = true
                            }
                            PlayerAction(icon: "waveform", title: "Wave") {
                                session.loadRecommendations(track)
                            }
                            PlayerAction(
                                icon: session.isDownloaded(track) ? "checkmark.circle.fill" : "arrow.down.circle",
                                title: session.isDownloaded(track) ? "Saved" : "Download"
                            ) {
                                session.downloadTrack(track)
                            }
                        }

                        Spacer(minLength: 8)
                    }
                } else {
                    EmptyLaneView(icon: "music.note", title: "Nothing is playing", subtitle: "Pick a track to start listening.")
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showQueue) {
                QueueScreen()
                    .environmentObject(session)
            }
            .sheet(isPresented: $showComments) {
                if let track = session.currentTrack {
                    CommentsScreen(track: track)
                        .environmentObject(session)
                }
            }
            .sheet(isPresented: $showTrackInfo) {
                if let track = session.currentTrack {
                    TrackInfoScreen(track: track)
                        .environmentObject(session)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct PlayerAction: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

private struct QueueScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(session.queue.enumerated()), id: \.element.id) { index, track in
                    Button {
                        session.currentIndex = index
                        session.requestStream(for: track)
                    } label: {
                        HStack {
                            ArtworkView(url: track.coverURL, size: 44, radius: 8)
                            VStack(alignment: .leading) {
                                Text(track.title)
                                    .foregroundStyle(.primary)
                                Text(track.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if index == session.currentIndex {
                                Image(systemName: "waveform")
                                    .foregroundStyle(lanePink)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Rows and details

private struct TrackRow: View {
    @EnvironmentObject private var session: LaneSession
    let track: TrackCandidate
    @Binding var showPlayer: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button {
                session.requestStream(for: track)
            } label: {
                HStack(spacing: 12) {
                    ArtworkView(url: track.coverURL, size: 52, radius: 10)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(track.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Menu {
                Button("Play next", systemImage: "text.insert") {
                    session.playNext(track)
                }
                Button("Add to queue", systemImage: "text.badge.plus") {
                    session.addToQueue(track)
                }
                Button(session.isFavorite(track) ? "Remove from liked" : "Like", systemImage: session.isFavorite(track) ? "heart.slash" : "heart") {
                    session.toggleFavorite(track)
                }
                Button("Download track", systemImage: "arrow.down.circle") {
                    session.downloadTrack(track)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            session.requestStream(for: track)
            showPlayer = true
        }
    }
}

private struct ArtistRow: View {
    let artist: LaneArtist

    var body: some View {
        APKArtistCardRow(artist: artist)
    }
}

private struct AlbumRow: View {
    let album: LaneAlbum

    var body: some View {
        APKAlbumCardRow(album: album)
    }
}

private struct PlaylistRow: View {
    let playlist: LanePlaylist

    var body: some View {
        HStack(spacing: 16) {
            ArtworkView(url: playlist.playlistImageUrl, size: 64, radius: 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.playlistName ?? "Playlist")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                let count = playlist.tracksCount ?? playlist.playlistTracks?.count ?? 0
                Text(count == 1 ? "1 track" : "\(count) tracks")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(red: 29.0 / 255.0, green: 29.0 / 255.0, blue: 29.0 / 255.0),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

struct PlaylistDetailScreen: View {
    @EnvironmentObject private var session: LaneSession
    let playlist: LanePlaylist
    @Binding var showPlayer: Bool

    @State private var tracks: [TrackCandidate] = []
    @State private var loading = true
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 18)

                ArtworkView(
                    url: playlist.playlistImageUrl,
                    size: 250,
                    radius: 8
                )
                .shadow(color: .black.opacity(0.40), radius: 22, y: 14)

                VStack(alignment: .leading, spacing: 8) {
                    Text(playlist.playlistName ?? "Playlist")
                        .font(.system(size: 25, weight: .bold))
                        .lineLimit(2)

                    if let description = playlist.playlistDescription, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.62))
                            .lineLimit(3)
                    }

                    HStack(spacing: 6) {
                        if let platform = playlist.platform, !platform.isEmpty {
                            Text(platform.capitalized)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.72))

                            Text("•")
                                .foregroundStyle(Color.white.opacity(0.38))
                        }

                        Text(tracks.count == 1 ? "1 track" : "\(tracks.count) tracks")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.52))
                    }

                    HStack(spacing: 16) {
                        Button {
                            if let first = tracks.first {
                                session.downloadTrack(first)
                            }
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 23, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.82))
                                .frame(width: 34, height: 40)
                        }
                        .buttonStyle(.plain)
                        .disabled(tracks.isEmpty)

                        Menu {
                            Button("Delete playlist", systemImage: "trash", role: .destructive) {
                                confirmDelete = true
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .rotationEffect(.degrees(90))
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.82))
                                .frame(width: 34, height: 40)
                        }

                        Spacer()

                        Button {
                            guard !tracks.isEmpty else { return }
                            let list = tracks.shuffled()
                            session.queue = list
                            session.currentIndex = 0
                            session.requestStream(for: list[0])
                            showPlayer = true
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .disabled(tracks.isEmpty)

                        Button {
                            guard let first = tracks.first else { return }
                            session.queue = tracks
                            session.currentIndex = 0
                            session.requestStream(for: first)
                            showPlayer = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 54, height: 54)

                                Image(systemName: "play.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.black)
                                    .offset(x: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(tracks.isEmpty)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)

                if loading {
                    HStack {
                        Spacer()
                        ProgressView().tint(lanePink)
                        Spacer()
                    }
                    .padding(.vertical, 32)
                } else if tracks.isEmpty {
                    EmptyLaneView(
                        icon: "music.note.list",
                        title: "Empty playlist",
                        subtitle: "Tracks added to this playlist will appear here."
                    )
                    .padding(.top, 18)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            Button {
                                session.queue = tracks
                                session.currentIndex = index
                                session.requestStream(for: track)
                                showPlayer = true
                            } label: {
                                HStack(spacing: 12) {
                                    Group {
                                        if session.currentTrack?.id == track.id {
                                            Image(systemName: "waveform")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(lanePink)
                                        } else {
                                            Text("\(index + 1)")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(Color.white.opacity(0.45))
                                        }
                                    }
                                    .frame(width: 24)

                                    ArtworkView(url: track.coverURL, size: 46, radius: 5)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(
                                                session.currentTrack?.id == track.id ? lanePink : .white
                                            )
                                            .lineLimit(1)

                                        Text(track.subtitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.white.opacity(0.56))
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Menu {
                                        Button("Play next", systemImage: "text.insert") {
                                            session.playNext(track)
                                        }
                                        Button("Add to queue", systemImage: "text.badge.plus") {
                                            session.addToQueue(track)
                                        }
                                        Button(
                                            session.isFavorite(track) ? "Remove from favorites" : "Add to favorites",
                                            systemImage: session.isFavorite(track) ? "heart.slash" : "heart"
                                        ) {
                                            session.toggleFavorite(track)
                                        }
                                        Button("Download", systemImage: "arrow.down.circle") {
                                            session.downloadTrack(track)
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(Color.white.opacity(0.62))
                                            .frame(width: 34, height: 46)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 64)
                            }
                            .buttonStyle(.plain)

                            Rectangle()
                                .fill(Color.white.opacity(0.055))
                                .frame(height: 1)
                                .padding(.leading, 98)
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.bottom, 28)
        }
        .background(laneBackground.ignoresSafeArea())
        .navigationTitle(playlist.playlistName ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            session.loadPlaylistTracks(playlist) { loaded in
                tracks = loaded
                loading = false
            }
        }
        .alert("Delete playlist?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                session.deleteServerPlaylist(playlist)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }
}

private struct TrackInfoScreen: View {
    @EnvironmentObject private var session: LaneSession
    let track: TrackCandidate

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ArtworkView(url: track.coverURL, size: 70, radius: 12)
                        VStack(alignment: .leading) {
                            Text(track.title).font(.headline)
                            Text(track.subtitle).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Track") {
                    LabeledContent("Platform", value: track.platform.isEmpty ? "Lane" : track.platform)
                    if let duration = track.duration, !duration.isEmpty {
                        LabeledContent("Duration", value: duration)
                    }
                    if let genre = track.genre, !genre.isEmpty {
                        LabeledContent("Genre", value: genre)
                    }
                    if let id = track.trackID {
                        LabeledContent("ID", value: id)
                    }
                }

                Section("Actions") {
                    Button("Track stats") { session.loadTrackStats(track) }
                    Button("Lyrics") { session.loadLyrics(track) }
                    Button("Recommendations") { session.loadRecommendations(track) }
                }

                if !session.output.isEmpty {
                    Section("Lane response") {
                        Text(session.output)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Track info")
        }
    }
}

// MARK: - Profile / login / social

private struct ProfileScreen: View {
    @EnvironmentObject private var session: LaneSession
    @State private var showEditProfile = false
    @State private var showPlayer = false

    private var profileName: String {
        session.publicProfile?.displayedName ??
        session.account?.displayedName ??
        (session.isGuest ? "Lane user" : "Profile")
    }

    private var profileUsername: String? {
        session.publicProfile?.userName ?? session.account?.userName
    }

    private var profileAvatar: String? {
        session.publicProfile?.avatarUrl ?? session.account?.avatarUrl
    }

    private var profileHeader: String? {
        session.publicProfile?.headerUrl ?? session.account?.headerUrl
    }

    private var profileStatus: String? {
        session.publicProfile?.statusText ?? session.account?.statusText
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    AsyncImage(url: URL(string: profileHeader ?? "")) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            ZStack {
                                LinearGradient(
                                    colors: [
                                        lanePink.opacity(0.38),
                                        Color.purple.opacity(0.20),
                                        laneBackground
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )

                                BundlePNG(name: "lane_lines_banner", contentMode: .fill)
                                    .opacity(0.40)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 250)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            colors: [.clear, laneBackground.opacity(0.35), laneBackground],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }

                    VStack(spacing: 10) {
                        AvatarView(url: profileAvatar, size: 96)
                            .overlay(Circle().stroke(laneBackground, lineWidth: 4))

                        HStack(spacing: 6) {
                            Text(profileName)
                                .font(.system(size: 25, weight: .bold))
                                .lineLimit(1)

                            if session.publicProfile?.equippedBadgeId != nil {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.blue)
                            }
                        }

                        if let username = profileUsername, !username.isEmpty {
                            Text("@\(username)")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.white.opacity(0.58))
                        }

                        if let status = profileStatus, !status.isEmpty {
                            Text(status)
                                .font(.system(size: 14))
                                .foregroundStyle(Color.white.opacity(0.74))
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .padding(.horizontal, 28)
                        }
                    }
                    .padding(.bottom, 6)
                }

                if session.isGuest {
                    TelegramLoginCard()
                        .padding(.top, 18)
                } else {
                    VStack(spacing: 18) {
                        HStack(spacing: 8) {
                            profileStat(
                                value: session.publicProfile?.followersCount ?? 0,
                                title: "Followers"
                            )

                            Rectangle()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 1, height: 28)

                            profileStat(
                                value: session.publicProfile?.followingCount ?? 0,
                                title: "Following"
                            )
                        }
                        .padding(.top, 8)

                        HStack(spacing: 10) {
                            Button {
                                showEditProfile = true
                            } label: {
                                Label("Edit profile", systemImage: "pencil")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(lanePink, in: RoundedRectangle(cornerRadius: 13))
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                FriendsScreen()
                            } label: {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                NotificationsScreen()
                            } label: {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)

                        if let statusTrack = session.publicProfile?.statusTrack {
                            let track = TrackCandidate(statusTrack)
                            Button {
                                session.requestStream(for: track)
                                showPlayer = true
                            } label: {
                                HStack(spacing: 12) {
                                    ArtworkView(url: track.coverURL, size: 58, radius: 8)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Status track")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Color.white.opacity(0.50))

                                        Text(track.title)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)

                                        Text(track.subtitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.white.opacity(0.58))
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Image(systemName: "play.fill")
                                        .foregroundStyle(.white)
                                }
                                .padding(10)
                                .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 14))
                                .padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)
                        }

                        if let playlists = session.publicProfile?.publicPlaylists, !playlists.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Public playlists")
                                        .font(.system(size: 20, weight: .bold))
                                    Spacer()
                                    Text("\(playlists.count)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)

                                ForEach(Array(playlists.prefix(6).enumerated()), id: \.offset) { _, playlist in
                                    NavigationLink {
                                        PlaylistDetailScreen(playlist: playlist, showPlayer: $showPlayer)
                                    } label: {
                                        PlaylistRow(playlist: playlist)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(spacing: 0) {
                            profileMenuRow(
                                icon: "waveform",
                                title: "Audio quality",
                                subtitle: AudioQualityChoice(rawValue: session.streamQuality)?.detail ?? session.streamQuality
                            )

                            Divider().padding(.leading, 58)

                            NavigationLink {
                                TelegramImportScreen()
                            } label: {
                                profileMenuRow(
                                    icon: "square.and.arrow.down",
                                    title: "Import music",
                                    subtitle: "Transfer tracks to Lane"
                                )
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.leading, 58)

                            NavigationLink {
                                DiagnosticsScreen()
                            } label: {
                                profileMenuRow(
                                    icon: "gearshape.fill",
                                    title: "Settings",
                                    subtitle: "Playback and API settings"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16)

                        Picker("Streaming quality", selection: $session.streamQuality) {
                            ForEach(AudioQualityChoice.allCases) { quality in
                                Text("\(quality.title) · \(quality.detail)")
                                    .tag(quality.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .onChange(of: session.streamQuality) { _ in
                            session.persist()
                        }

                        Button(role: .destructive) {
                            session.clearAccount()
                        } label: {
                            Text("Log out")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red.opacity(0.85))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .background(laneBackground.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !session.isGuest {
                session.refreshAccount()
            }
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileSheet()
                .environmentObject(session)
        }
        .fullScreenCover(isPresented: $showPlayer) {
            APKFullPlayerView()
                .environmentObject(session)
        }
    }

    private func profileStat(value: Int64, title: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold))
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 82)
    }

    private func profileMenuRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(lanePink)
                .frame(width: 32, height: 32)
                .background(lanePink.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
    }
}

private struct TelegramLoginScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.openURL) private var openURL

    @State private var authId = ""
    @State private var polling = false
    @State private var message = ""
    @State private var botUsername = "lane_music_bot"
    @State private var showDeviceIDEditor = false
    @State private var editedAuthId = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            TelegramIcon(size: 116)

            VStack(spacing: 8) {
                Text("Sign in with Telegram")
                    .font(.title.bold())

                Text("Lane will open @\(botUsername). Confirm the authorization there, then return to this app.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)

            Button {
                beginTelegramLogin()
            } label: {
                HStack {
                    if polling {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }

                    Text(polling ? "Waiting for Telegram…" : "Continue with Telegram")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.horizontal, 24)
            .disabled(polling)

            if !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .textSelection(.enabled)
            }

            if polling {
                Button {
                    checkAuthorizationNow()
                } label: {
                    Text("Check authorization now")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(lanePink)
            }

            Spacer()

            VStack(spacing: 8) {
                Text("Authentication ID: \(authId)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)

                Button(showDeviceIDEditor ? "Hide Android ID tools" : "Use ID from logged-in Android") {
                    editedAuthId = authId
                    showDeviceIDEditor.toggle()
                }
                .font(.caption)

                if showDeviceIDEditor {
                    HStack(spacing: 8) {
                        TextField("16-char Android ID", text: $editedAuthId)
                            .font(.caption.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)

                        Button("Save") {
                            if session.setTelegramAuthID(editedAuthId) {
                                authId = session.persistentTelegramAuthID()
                                editedAuthId = authId
                                message = "Authentication ID saved. Start Telegram authorization again with this ID."
                            } else {
                                message = session.output
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 24)

                    Button("Generate new ID") {
                        authId = session.generateNewTelegramAuthID()
                        editedAuthId = authId
                        message = "Generated a new Authentication ID. Start Telegram authorization again."
                    }
                    .font(.caption)
                }
            }
            .padding(.bottom, 4)

            if session.backendMode == .custom {
                Text("Custom backend: \(session.baseURL)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else {
                Text("Official Lane requires its supported signed client.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text("Keep this screen open after confirming in Telegram.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 14)
        }
        .background(laneBackground.ignoresSafeArea())
        .navigationTitle("Telegram")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            authId = session.persistentTelegramAuthID()
            editedAuthId = authId
            Task {
                await loadLoginConfiguration()
            }
        }
    }

    private func loadLoginConfiguration() async {
        if session.backendMode == .official {
            botUsername = "lane_music_bot"
            await session.prepareAPI()
            return
        }

        do {
            let config = try await session.fetchBackendConfig()
            let username = (config.telegramBotUsername ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "@", with: "")

            guard !username.isEmpty else {
                message = "Custom backend is reachable, but TELEGRAM_BOT_USERNAME is not configured."
                return
            }

            botUsername = username
            message = ""
        } catch {
            message = "Could not connect to custom backend: \(error.localizedDescription)"
        }
    }

    private func checkAuthorizationNow() {
        let id = session.persistentTelegramAuthID()
        authId = id
        message = "Checking authorization…"

        Task {
            await session.prepareAPI()

            do {
                let response = try await LaneAPI.shared.pollAuth(authId: id, attempts: 1)
                let successfulBase = await LaneAPI.shared.currentBaseURL()
                session.acceptLaneToken(response.token, serverBaseURL: successfulBase)
                message = "Authorization successful."
                polling = false
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func beginTelegramLogin() {
        let id = session.persistentTelegramAuthID()
        authId = id
        polling = true
        message = "Preparing Telegram authorization…"

        Task {
            if session.backendMode == .custom {
                do {
                    let config = try await session.fetchBackendConfig()
                    let username = (config.telegramBotUsername ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "@", with: "")

                    guard !username.isEmpty else {
                        polling = false
                        message = "Custom backend has no Telegram bot username configured."
                        return
                    }

                    botUsername = username
                } catch {
                    polling = false
                    message = "Custom backend is unavailable: \(error.localizedDescription)"
                    return
                }
            } else {
                await session.prepareAPI()
                botUsername = "lane_music_bot"
            }

            let payload = "auth\(id)"
            let command = "/start \(payload)"

            await MainActor.run {
                UIPasteboard.general.string = command
                message = "Telegram command copied: \(command)\nIf Telegram does not send it automatically, paste this exact command to @\(botUsername)."
            }

            let tgURL = URL(string: "tg://resolve?domain=\(botUsername)&start=\(payload)")
            let webURL = URL(string: "https://t.me/\(botUsername)?start=\(payload)")

            if let tgURL {
                await MainActor.run {
                    UIApplication.shared.open(tgURL, options: [:]) { opened in
                        if !opened, let webURL {
                            UIApplication.shared.open(webURL)
                        }
                    }
                }
            } else if let webURL {
                await MainActor.run {
                    UIApplication.shared.open(webURL)
                }
            } else {
                polling = false
                message = "Could not create Telegram authorization link."
                return
            }

            do {
                let response = try await LaneAPI.shared.pollAuth(authId: id)
                let successfulBase = await LaneAPI.shared.currentBaseURL()
                session.acceptLaneToken(response.token, serverBaseURL: successfulBase)
                message = "Authorization successful."
            } catch {
                message = error.localizedDescription
            }

            polling = false
        }
    }
}

private struct EditProfileSheet: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var username = ""
    @State private var statusText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $name)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                    TextField("About me", text: $statusText, axis: .vertical)
                }
            }
            .navigationTitle("Edit Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        session.saveProfile(name: name, username: username, statusText: statusText)
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = session.account?.displayedName ?? ""
                username = session.account?.userName ?? ""
                statusText = session.account?.statusText ?? ""
            }
        }
    }
}

private struct FriendsScreen: View {
    @EnvironmentObject private var session: LaneSession
    @State private var query = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Search users", text: $query)
                        .textInputAutocapitalization(.never)
                        .onSubmit { session.searchUsers(query) }
                    Button("Search") { session.searchUsers(query) }
                }
            }

            if !session.userSearchResults.isEmpty {
                Section("Search results") {
                    ForEach(Array(session.userSearchResults.enumerated()), id: \.offset) { _, user in
                        UserRow(user: user)
                    }
                }
            }

            Section("Friends") {
                if session.friends.isEmpty {
                    Text("No friends yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(session.friends.enumerated()), id: \.offset) { _, user in
                        UserRow(user: user)
                    }
                }
            }
        }
        .navigationTitle("Friends")
        .onAppear {
            session.refreshFriends()
        }
    }
}

private struct UserRow: View {
    @EnvironmentObject private var session: LaneSession
    let user: UserInfoDTO

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: user.avatarUrl, size: 46)
            VStack(alignment: .leading) {
                Text(user.displayedName ?? user.userName ?? "Lane user")
                    .font(.subheadline.weight(.semibold))
                if let username = user.userName, !username.isEmpty {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let laneId = user.laneId {
                Button(user.isFollowing == true ? "Following" : "Follow") {
                    session.setFollowing(user, follow: user.isFollowing != true)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .id(laneId)
            }
        }
    }
}

private struct NotificationsScreen: View {
    @EnvironmentObject private var session: LaneSession

    var body: some View {
        List {
            if session.notificationCards.isEmpty {
                EmptyLaneView(icon: "bell", title: "No notifications", subtitle: "Updates from Lane will appear here.")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(session.notificationCards) { card in
                    HStack(spacing: 12) {
                        ArtworkView(url: card.imageURL, size: 46, radius: 23)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(card.title)
                                .font(.subheadline.weight(.semibold))
                            Text(card.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .onAppear {
            session.refreshNotifications()
        }
    }
}

private struct CommentsScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss

    let track: TrackCandidate
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    if session.comments.isEmpty {
                        Text("No comments yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.comments) { comment in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 9) {
                                    AvatarView(url: comment.userAvatar, size: 34)
                                    VStack(alignment: .leading) {
                                        Text(comment.userName ?? "Lane user")
                                            .font(.subheadline.weight(.semibold))
                                        if let timestamp = comment.timestamp {
                                            Text(Date(timeIntervalSince1970: TimeInterval(timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp)), style: .relative)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }

                                Text(comment.text ?? "")
                                    .font(.body)

                                Button {
                                    session.toggleCommentLike(comment, for: track)
                                } label: {
                                    Label("\(comment.likesCount ?? 0)", systemImage: comment.isLiked == true ? "heart.fill" : "heart")
                                        .font(.caption)
                                        .foregroundStyle(comment.isLiked == true ? lanePink : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.plain)

                HStack(spacing: 10) {
                    TextField("Add a comment…", text: $text, axis: .vertical)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        let outgoing = text
                        text = ""
                        session.sendComment(outgoing, for: track)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundStyle(lanePink)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(12)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Comments")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                session.loadComments(for: track)
            }
        }
    }
}

// MARK: - Library auxiliary screens

private struct FavoriteTracksScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Binding var showPlayer: Bool

    private var tracks: [TrackCandidate] {
        let all = session.history + session.searchTracks + session.queue + session.homeTracks + session.recentTracks
        var seen = Set<String>()
        return all.filter {
            session.isFavorite($0) && seen.insert($0.id).inserted
        }
    }

    var body: some View {
        List {
            if tracks.isEmpty {
                EmptyLaneView(icon: "heart", title: "Favorite Tracks", subtitle: "Tap the heart on a track to save it.")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(tracks) { track in
                    TrackRow(track: track, showPlayer: $showPlayer)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(laneBackground)
        .navigationTitle("Liked tracks")
    }
}

private struct DownloadsScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Binding var showPlayer: Bool

    private var downloaded: [TrackCandidate] {
        let all = session.history + session.searchTracks + session.queue + session.homeTracks + session.recentTracks
        var seen = Set<String>()
        return all.filter {
            session.isDownloaded($0) && seen.insert($0.id).inserted
        }
    }

    var body: some View {
        List {
            if downloaded.isEmpty {
                EmptyLaneView(icon: "arrow.down.circle", title: "Downloads", subtitle: "Save tracks to listen offline.")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(downloaded) { track in
                    TrackRow(track: track, showPlayer: $showPlayer)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(laneBackground)
        .navigationTitle("Downloads")
    }
}

private struct CreatePlaylistSheet: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        BundlePNG(name: "lane_3d_logo_playlist")
                            .frame(width: 120, height: 148)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Playlist") {
                    TextField("Playlist name", text: $name)
                    TextField("Playlist description", text: $description, axis: .vertical)
                }
            }
            .navigationTitle("Create Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        session.createServerPlaylist(name: name, description: description)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct TelegramImportScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.openURL) private var openURL
    @State private var response = ""
    @State private var loading = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            BundlePNG(name: "import_tracks_background_card", contentMode: .fill)
                .frame(maxWidth: 330)
                .frame(height: 99)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Text("Import your tracks")
                .font(.title.bold())

            Text("Transfer your music from other platforms to Lane")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button {
                loading = true
                Task {
                    await LaneAPI.shared.setBase(session.baseURL)
                    do {
                        let result = try await LaneAPI.shared.telegramImportStart(token: session.token)
                        response = result.pretty
                    } catch {
                        response = error.localizedDescription
                    }
                    loading = false
                }
            } label: {
                Label(loading ? "Starting…" : "Transfer via Telegram", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(lanePink)
            .disabled(session.isGuest || loading)
            .padding(.horizontal, 24)

            if !response.isEmpty {
                ScrollView {
                    Text(response)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .padding()
            }

            Spacer()
        }
        .background(laneBackground)
        .navigationTitle("Import")
    }
}

private struct WaveScreen: View {
    @EnvironmentObject private var session: LaneSession

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            BundlePNG(name: "lane_logo_3d_wave")
                .frame(width: 150, height: 170)
            Text("Wave")
                .font(.largeTitle.bold())
            Text("Build a continuous queue from your current track using Lane recommendations.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            if let current = session.currentTrack {
                Button("Start wave from this song") {
                    session.loadRecommendations(current)
                }
                .buttonStyle(.borderedProminent)
                .tint(lanePink)
            } else {
                Text("Play a track first")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .background(laneBackground)
        .navigationTitle("Wave")
    }
}

private struct SearchProxyScreen: View {
    @EnvironmentObject private var session: LaneSession
    @State private var query = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Search", text: $query)
                        .onSubmit { session.search(query) }
                    Button("Search") { session.search(query) }
                }
            }

            ForEach(session.searchTracks) { track in
                Button {
                    session.requestStream(for: track)
                } label: {
                    HStack {
                        ArtworkView(url: track.coverURL, size: 46, radius: 9)
                        VStack(alignment: .leading) {
                            Text(track.title)
                            Text(track.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Search")
    }
}

// MARK: - Diagnostics

private struct DiagnosticsScreen: View {
    @EnvironmentObject private var session: LaneSession
    @State private var path = "/time"
    @State private var method = "GET"

    var body: some View {
        Form {
            Section("Backend") {
                Picker("Mode", selection: $session.backendMode) {
                    ForEach(LaneBackendMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .onChange(of: session.backendMode) { _ in
                    session.clearAccount()
                    session.persist()
                }

                TextField("Base URL", text: $session.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { session.persist() }

                if session.backendMode == .custom {
                    TextField("API-key header", text: $session.apiKeyHeader)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("API key", text: $session.apiKey)

                    Button("Save custom backend settings") {
                        session.persist()
                    }

                    Text("Custom mode uses a standard API-key header and is intended for a backend you control or are authorized to access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label(
                        "Official Lane currently requires its supported client-signature mechanism. The iOS port will not attempt to recreate or bypass that protection.",
                        systemImage: "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Playback") {
                Picker("Quality", selection: $session.streamQuality) {
                    ForEach(AudioQualityChoice.allCases) { quality in
                        Text(quality.rawValue)
                            .tag(quality.rawValue)
                    }
                }
                .onChange(of: session.streamQuality) { _ in session.persist() }
            }

            Section("Request") {
                TextField("/endpoint", text: $path)
                    .textInputAutocapitalization(.never)

                Picker("Method", selection: $method) {
                    Text("GET").tag("GET")
                    Text("POST").tag("POST")
                    Text("DELETE").tag("DELETE")
                }
                .pickerStyle(.segmented)

                Button("Send request") {
                    session.persist()
                    session.rawCall(path: path, method: method)
                }
            }

            Section("Response") {
                LabeledContent("HTTP", value: session.status == 0 ? "—" : "\(session.status)")
                ScrollView(.horizontal) {
                    Text(session.output)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .frame(minHeight: 140)
            }
        }
        .navigationTitle("Advanced / API")
    }
}

// MARK: - Reusable components

private struct TrackSection: View {
    @EnvironmentObject private var session: LaneSession
    let title: String
    let subtitle: String?
    let tracks: [TrackCandidate]
    @Binding var showPlayer: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.bold())
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(tracks) { track in
                        Button {
                            session.queue = tracks
                            session.currentIndex = tracks.firstIndex(of: track)
                            session.requestStream(for: track)
                            showPlayer = true
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ArtworkView(url: track.coverURL, size: 148, radius: 15)
                                Text(track.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(width: 148, alignment: .leading)
                                Text(track.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 148, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }
}

private struct CardShelf: View {
    let title: String
    let cards: [LaneCardItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(cards) { card in
                        VStack(alignment: .leading, spacing: 8) {
                            ArtworkView(url: card.imageURL, size: 148, radius: 15)
                            Text(card.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(card.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 148, alignment: .leading)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }
}

private struct FeatureBanner: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 58, height: 58)
                .background(lanePink, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(laneCard, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 16)
    }
}

private struct LibraryFeatureCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradient: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)

            Spacer()

            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .background(
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }
}

private struct LibrarySectionTitle: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.bold())
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }
}

private struct ArtworkView: View {
    let url: String?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        AsyncImage(url: URL(string: url ?? "")) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                ZStack {
                    LinearGradient(
                        colors: [lanePink.opacity(0.75), Color.purple.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: max(15, size * 0.24), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

private struct AvatarView: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: URL(string: url ?? "")) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Circle().fill(Color.white.opacity(0.10))
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private struct EmptyLaneView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}
