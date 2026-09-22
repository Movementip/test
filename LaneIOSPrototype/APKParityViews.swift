import SwiftUI
import UIKit

private let apkPink = Color(red: 1.0, green: 130.0 / 255.0, blue: 132.0 / 255.0)
private let apkBackground = Color(red: 10.0 / 255.0, green: 10.0 / 255.0, blue: 10.0 / 255.0)
private let apkSurface = Color(red: 29.0 / 255.0, green: 29.0 / 255.0, blue: 29.0 / 255.0)


struct APKTemplateIcon: View {
    let name: String
    var size: CGFloat = 24
    var color: Color = .white

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image.withRenderingMode(.alwaysTemplate))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .foregroundStyle(color)
            } else {
                fallback
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var fallback: some View {
        switch name {
        case "heart", "like":
            Image(systemName: name == "like" ? "heart.fill" : "heart")
        case "comment":
            Image(systemName: "bubble.left")
        case "ic_download":
            Image(systemName: "arrow.down.circle")
        case "queue":
            Image(systemName: "text.badge.plus")
        case "repeat":
            Image(systemName: "repeat")
        case "repeat_1":
            Image(systemName: "repeat.1")
        case "shuffle":
            Image(systemName: "shuffle")
        case "text":
            Image(systemName: "text.quote")
        case "ic_track_effect":
            Image(systemName: "slider.horizontal.3")
        case "baseline_pause_24":
            Image(systemName: "pause.fill")
        case "baseline_play_arrow_24":
            Image(systemName: "play.fill")
        case "bottom_search":
            Image(systemName: "magnifyingglass")
        case "bottom_library":
            Image(systemName: "square.stack.fill")
        case "bottom_main_unselected":
            Image(systemName: "house.fill")
        default:
            Image(systemName: "circle")
        }
    }
}

struct APKLaneWordmark: View {
    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "lane", withExtension: "png"),
               let image = UIImage(contentsOfFile: url.path) {
                // The original APK wordmark includes the full lower strokes.
                // Keep its native aspect without clipping the header image.
                Image(uiImage: image.withRenderingMode(.alwaysOriginal))
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: 94.3, height: 20, alignment: .leading)
            } else {
                Text("LANE")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .tracking(-0.5)
                    .fixedSize()
            }
        }
        .frame(height: 20, alignment: .leading)
        .accessibilityLabel("Lane")
    }
}

struct APKLaneHeaderTitle: View {
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            APKLaneWordmark()
            Text(subtitle)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.56))
                .lineLimit(1)
        }
    }
}


private struct APKBundleImage: View {
    let name: String
    var contentMode: ContentMode = .fit

    var body: some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image.withRenderingMode(.alwaysOriginal))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: contentMode)
        } else {
            Color.clear
        }
    }
}


struct APKPlatformIcon: View {
    let platform: String?
    var size: CGFloat = 10

    private var assetName: String? {
        let value = (platform ?? "").lowercased()
        if value.contains("spotify") { return "ic_spotify" }
        if value.contains("soundcloud") || value.contains("sound_cloud") { return "ic_soundcloud" }
        if value.contains("yandex") { return "ic_yandex_music" }
        if value.contains("telegram") { return "telegram" }
        return nil
    }

    var body: some View {
        Group {
            if let assetName,
               let url = Bundle.main.url(forResource: assetName, withExtension: "png"),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image.withRenderingMode(.alwaysOriginal))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Circle()
                    .fill(Color.white.opacity(0.45))
                    .overlay {
                        Circle()
                            .fill(Color.black.opacity(0.55))
                            .padding(2)
                    }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct APKVerifiedBadge: View {
    var size: CGFloat = 10

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "verified", withExtension: "png"),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image.withRenderingMode(.alwaysOriginal))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color(red: 73.0 / 255.0, green: 173.0 / 255.0, blue: 244.0 / 255.0))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// Exact compact rows used by SearchScreen in Lane Android 1.4.7.
// Artwork/avatars, spacings, platform icons and typography are matched to
// TrackResultItem / ArtistResultItem / AlbumResultItem / PlaylistResultItem.
struct APKSearchTrackRow: View {
    let track: TrackCandidate
    let onTap: () -> Void
    @State private var showActions = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 0) {
                    APKRemoteImage(url: track.coverURL, cornerRadius: 5)
                        .frame(width: 52, height: 52)

                    Spacer().frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        HStack(spacing: 5) {
                            APKPlatformIcon(platform: track.platform, size: 10)
                            Text("Song • \(track.subtitle)")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.70))
                                .lineLimit(1)
                                .padding(.trailing, 10)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            Button {
                showActions = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 44, height: 52)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .sheet(isPresented: $showActions) {
            APKTrackActionsSheet(track: track)
        }
    }
}

// Lane Android presents track actions as a bottom sheet, not as an immediate
// "add to queue" side effect when the overflow button is tapped.
struct APKTrackActionsSheet: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss
    let track: TrackCandidate

    @State private var choosingPlaylist = false
    @State private var shareItem: LaneShareURL?
    @State private var actionError: String?
    @State private var actionNotice: String?
    @State private var sharing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 40, height: 5)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 18)

                    HStack(spacing: 14) {
                        APKRemoteImage(url: track.coverURL, cornerRadius: 8)
                            .frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title)
                                .font(.system(size: 24, weight: .bold))
                                .lineLimit(1)
                            Text(track.subtitle)
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.bottom, 32)

                    if choosingPlaylist {
                        actionRow("Back to track", icon: "chevron.left") {
                            choosingPlaylist = false
                        }
                        Text("Add to playlist")
                            .font(.system(size: 20, weight: .bold))
                            .padding(.vertical, 10)

                        ForEach(Array(session.serverPlaylists.enumerated()), id: \.offset) { _, playlist in
                            actionRow(playlist.playlistName ?? "Playlist", icon: "music.note.list") {
                                session.addTrack(track, to: playlist)
                                dismiss()
                            }
                        }
                        ForEach(session.localPlaylists) { playlist in
                            actionRow(playlist.name, icon: "music.note.list") {
                                session.add(track, to: playlist.id)
                                dismiss()
                            }
                        }
                    } else {
                        actionRow(session.isFavorite(track) ? "Remove from liked" : "Like",
                                  icon: session.isFavorite(track) ? "heart.fill" : "heart") {
                            session.toggleFavorite(track)
                            dismiss()
                        }
                        actionRow("Add to playlist", icon: "music.note.list") {
                            choosingPlaylist = true
                        }

                        Rectangle()
                            .fill(Color.white.opacity(0.10))
                            .frame(height: 1)
                            .padding(.vertical, 20)

                        capsuleAction(
                            session.isDownloaded(track) ? "Downloaded" : "Download track",
                            icon: session.isDownloaded(track) ? "checkmark" : "arrow.down"
                        ) {
                            session.downloadTrack(track)
                            dismiss()
                        }
                        capsuleAction("Use as status", icon: "music.note") {
                            Task {
                                do {
                                    try await session.setStatusTrack(track)
                                    actionNotice = "Status updated"
                                } catch {
                                    actionError = error.localizedDescription
                                }
                            }
                        }
                        if track.platform.lowercased() != "telegram" {
                            capsuleAction("Start wave from this song", icon: "waveform") {
                                session.startWave(from: track)
                                dismiss()
                            }
                        }

                        Rectangle()
                            .fill(Color.white.opacity(0.10))
                            .frame(height: 1)
                            .padding(.vertical, 18)

                        HStack(spacing: 36) {
                            Button("Copy link") { createShareLink(copy: true) }
                            Button("More") { createShareLink(copy: false) }
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .disabled(sharing)
                        .padding(.bottom, 12)

                        if sharing { ProgressView().tint(.white) }
                        if let actionNotice {
                            Text(actionNotice).foregroundStyle(.green)
                        }
                        if let actionError {
                            Text(actionError).foregroundStyle(apkPink)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 26)
            }
            .background(apkBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .sheet(item: $shareItem) { item in
            LaneShareActivitySheet(url: item.url)
        }
    }

    private func createShareLink(copy: Bool) {
        guard !sharing else { return }
        sharing = true
        actionError = nil
        Task {
            defer { sharing = false }
            do {
                let url = try await session.shareTrack(track)
                if copy {
                    UIPasteboard.general.url = url
                    actionNotice = "Link copied"
                } else {
                    shareItem = LaneShareURL(url: url)
                }
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func capsuleAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24)
                Text(title).font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(apkSurface, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 15)
    }

    private func actionRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 26)
                    .foregroundStyle(apkPink)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .frame(height: 55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct APKPlaylistActionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let playlist: LanePlaylist
    let creatorName: String
    let isOwner: Bool
    let isSaved: Bool
    let visibility: String
    let onEdit: () -> Void
    let onInvite: () -> Void
    let onShare: () -> Void
    let onToggleVisibility: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 40, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 18)

                APKRemoteImage(url: playlist.playlistImageUrl, cornerRadius: 12)
                    .frame(width: 200, height: 200)

                Text(playlist.playlistName ?? "Playlist")
                    .font(.system(size: 21, weight: .bold))
                    .lineLimit(1)
                    .padding(.top, 16)

                Text(creatorName)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 5)
                    .padding(.bottom, 20)

                if isOwner {
                    action("Edit", icon: "pencil", asset: nil, perform: onEdit)
                    action("Invite collaborators", icon: "person.badge.plus", asset: nil, perform: onInvite)
                } else if !isSaved {
                    action("Add to Library", icon: "square.stack", asset: "ic_lib_outline", perform: onSave)
                } else {
                    action("Remove from Library", icon: "minus.circle", asset: "ic_lib_outline", perform: onDelete)
                }

                action("Share", icon: "square.and.arrow.up", asset: "ic_share", perform: onShare)

                if isOwner {
                    action(
                        visibility.lowercased() == "public" ? "Make private" : "Make public",
                        icon: visibility.lowercased() == "public" ? "eye.slash" : "eye",
                        asset: visibility.lowercased() == "public" ? "invisible" : "visible",
                        perform: onToggleVisibility
                    )
                    action("Delete", icon: "trash", asset: "ic_delete", perform: onDelete)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.bottom, 28)
        }
        .background(apkBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private func action(
        _ title: String,
        icon: String,
        asset: String?,
        perform: @escaping () -> Void
    ) -> some View {
        Button {
            dismiss()
            perform()
        } label: {
            HStack(spacing: 17) {
                if let asset {
                    APKTemplateIcon(name: asset, size: 25)
                        .frame(width: 28)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 28)
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.white)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct APKSearchArtistRow: View {
    let artist: LaneArtist

    var body: some View {
        NavigationLink {
            APKArtistDetailScreen(seed: artist)
        } label: {
            HStack(spacing: 0) {
                APKRemoteImage(url: artist.avatarUrl, circle: true)
                    .frame(width: 50, height: 50)

                Spacer().frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if artist.verified == true {
                            APKVerifiedBadge(size: 10)
                        }

                        Text(artist.name ?? "Artist")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    HStack(spacing: 5) {
                        APKPlatformIcon(platform: artist.platform, size: 10)
                        Text("Artist")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.70))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .frame(width: 34, height: 50)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

struct APKSearchAlbumRow: View {
    let album: LaneAlbum

    var body: some View {
        NavigationLink {
            APKAlbumDetailScreen(seed: album)
        } label: {
            HStack(spacing: 0) {
                APKRemoteImage(url: album.coverUrl, cornerRadius: 5)
                    .frame(width: 52, height: 52)

                Spacer().frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(album.name ?? "Album")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        APKPlatformIcon(platform: album.platform, size: 10)
                        Text("Album • \(album.artistsDisplayedName ?? "")")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.70))
                            .lineLimit(1)
                            .padding(.trailing, 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .frame(width: 34, height: 52)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

struct APKSearchPlaylistRow: View {
    let playlist: LanePlaylist

    var body: some View {
        HStack(spacing: 0) {
            APKRemoteImage(url: playlist.playlistImageUrl, cornerRadius: 5)
                .frame(width: 52, height: 52)

            Spacer().frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.playlistName ?? "Playlist")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    APKPlatformIcon(platform: playlist.platform, size: 10)
                    Text("Playlist")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.70))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.60))
                .frame(width: 34, height: 52)
        }
        .padding(.vertical, 4)
    }
}

struct APKFavoritePlaylistCard: View {
    let trackCount: Int

    var body: some View {
        ZStack {
            APKBundleImage(name: "lane_1_4_favourite_tracks_dark_theme__2", contentMode: .fill)
                .opacity(0.95)

            if Bundle.main.url(forResource: "lane_1_4_favourite_tracks_dark_theme__2", withExtension: "png") == nil {
                LinearGradient(
                    colors: [Color(red: 0.17, green: 0.11, blue: 0.13), Color(red: 0.08, green: 0.08, blue: 0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Favorite tracks")
                        .font(.system(size: 16, weight: .bold))
                    Text("\(trackCount) tracks")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.70))
                }

                Spacer()

                ZStack {
                    APKBundleImage(name: "cover_liked_tracks_dark", contentMode: .fill)
                    if Bundle.main.url(forResource: "cover_liked_tracks_dark", withExtension: "png") == nil {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(apkPink.opacity(0.18))
                        Image(systemName: "heart.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(apkPink)
                    }
                }
                .frame(width: 86, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 20)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

struct APKImportTracksCard: View {
    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.10, blue: 0.13),
                    Color(red: 0.07, green: 0.07, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            APKBundleImage(name: "import_tracks_background_card", contentMode: .fill)
                .scaleEffect(1.2)
                .opacity(0.92)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import tracks")
                        .font(.system(size: 14, weight: .bold))

                    Text("Transfer your music to Lane")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.70))

                    HStack(spacing: 10) {
                        Image(systemName: "music.note")
                        Image(systemName: "cloud.fill")
                        Image(systemName: "paperplane.fill")
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .padding(.top, 12)
                }
                .padding(16)

                Spacer()

                ZStack {
                    Image(systemName: "waveform")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(apkPink.opacity(0.55))

                    APKBundleImage(name: "lane_logo_3d_wave")
                        .scaleEffect(1.2)
                }
                .frame(width: 92, height: 105)
                .offset(x: 2, y: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.20), lineWidth: 1)
        }
    }
}

// MARK: - Import components recovered from Lane Android 1.4.7

struct APKImportBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct APKImportPlatformButton: View {
    let title: String
    let asset: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                APKBundleImage(name: asset)
                    .frame(width: 24, height: 24)
                    .opacity(0.8)
            }
            .padding(.horizontal, 25)
            .frame(height: 60)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct APKImportOptionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    Image(systemName: icon)
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(accent)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct APKPrimaryButton: View {
    let title: String
    var loading = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if loading {
                    ProgressView()
                        .tint(.black)
                }
                Text(title)
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(apkPink.opacity(enabled ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || loading)
    }
}

struct APKPlaylistEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.50))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "music.note")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .offset(x: 20, y: 10)
                }
                .padding(.bottom, 8)

            Text("Playlist is empty")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            Text("Add tracks to start listening to music at your own pace.")
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.60))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, 38)
    }
}

struct APKRemoteImage: View {
    let url: String?
    var cornerRadius: CGFloat = 8
    var circle = false

    var body: some View {
        LaneResilientImage(url: url) {
            ZStack {
                Color.white.opacity(0.07)
                Image(systemName: circle ? "person.fill" : "music.note")
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }
}

private struct AnyShape: Shape {
    private let pathBuilder: (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        pathBuilder = { rect in shape.path(in: rect) }
    }

    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}

struct APKArtistCardRow: View {
    let artist: LaneArtist

    var body: some View {
        NavigationLink {
            APKArtistDetailScreen(seed: artist)
        } label: {
            HStack(spacing: 16) {
                APKRemoteImage(url: artist.avatarUrl, circle: true)
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(artist.name ?? "Artist")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if artist.verified == true {
                            APKVerifiedBadge(size: 10)
                        }
                    }

                    Text("Artist")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(apkSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }
}

struct APKAlbumCardRow: View {
    let album: LaneAlbum

    var body: some View {
        NavigationLink {
            APKAlbumDetailScreen(seed: album)
        } label: {
            HStack(spacing: 16) {
                APKRemoteImage(url: album.coverUrl, cornerRadius: 5)
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(album.name ?? "Album")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("Album • " + ((album.year?.isEmpty == false ? album.year : album.artistsDisplayedName) ?? ""))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.42))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(apkSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }
}


struct APKAlbumDetailScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss
    let seed: LaneAlbum

    @State private var album: LaneAlbum?
    @State private var tracks: [TrackCandidate] = []
    @State private var loading = true
    @State private var albumLoadMessage = ""
    @State private var libraryActionError: String?
    @State private var showPlayer = false

    private var value: LaneAlbum { album ?? seed }
    private var isSavedToLibrary: Bool { session.isAlbumSaved(value) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    APKRemoteImage(url: value.coverUrl, cornerRadius: 0)
                        .frame(maxWidth: .infinity)
                        .frame(height: 330)
                        .clipped()
                        .blur(radius: 26)
                        .scaleEffect(1.16)
                        .opacity(0.45)

                    LinearGradient(
                        colors: [
                            apkBackground.opacity(0.05),
                            apkBackground.opacity(0.60),
                            apkBackground
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    APKRemoteImage(url: value.coverUrl, cornerRadius: 10)
                        .frame(width: 225, height: 225)
                        .shadow(color: .black.opacity(0.45), radius: 22, y: 14)
                        .padding(.bottom, 18)
                }
                .frame(height: 345)

                VStack(alignment: .leading, spacing: 10) {
                    Text(value.name ?? "Album")
                        .font(.system(size: 28, weight: .bold))
                        .lineLimit(2)

                    if let artists = value.artistsDisplayedName, !artists.isEmpty {
                        Text(artists)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        APKPlatformIcon(platform: value.platform, size: 11)

                        Text(albumInfo)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.56))
                    }

                    HStack(spacing: 14) {
                        Button {
                            play(shuffled: false)
                        } label: {
                            HStack(spacing: 8) {
                                APKTemplateIcon(name: "baseline_play_arrow_24", size: 20, color: .black)
                                Text("Play")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(apkPink, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(tracks.isEmpty)

                        Button {
                            Task {
                                do {
                                    libraryActionError = nil
                                    try await session.setAlbumSaved(value, saved: !isSavedToLibrary)
                                } catch {
                                    libraryActionError = error.localizedDescription
                                }
                            }
                        } label: {
                            Group {
                                if isSavedToLibrary {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 20, weight: .bold))
                                } else {
                                    APKTemplateIcon(name: "ic_lib_outline", size: 23, color: .white)
                                }
                            }
                            .frame(width: 48, height: 48)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isSavedToLibrary ? "Remove album from Library" : "Add album to Library")

                        Button {
                            play(shuffled: true)
                        } label: {
                            APKTemplateIcon(name: "shuffle", size: 22, color: .white)
                                .frame(width: 48, height: 48)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(tracks.isEmpty)
                    }
                    .padding(.top, 6)

                    if let libraryActionError {
                        Text(libraryActionError)
                            .font(.system(size: 12))
                            .foregroundStyle(apkPink)
                    }

                    if loading {
                        HStack {
                            Spacer()
                            ProgressView().tint(apkPink)
                            Spacer()
                        }
                        .padding(.vertical, 28)
                    } else if tracks.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 31, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(albumLoadMessage.isEmpty ? "No tracks" : albumLoadMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Try again") {
                                Task { await loadAlbum() }
                            }
                            .buttonStyle(.bordered)
                            .tint(apkPink)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                APKAlbumTrackRow(
                                    index: index + 1,
                                    track: track,
                                    onTap: {
                                        session.queue = tracks
                                        session.currentIndex = index
                                        session.requestStream(for: track)
                                    }
                                )
                            }
                        }
                        .padding(.top, 8)
                    }

                    if let year = value.year, !year.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Release date")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(year)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .background(apkBackground.ignoresSafeArea())
        .tint(.white)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .principal) {
                Text("Album")
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .task { await loadAlbum() }
        .refreshable { await loadAlbum() }
        .fullScreenCover(isPresented: $showPlayer) {
            APKFullPlayerView()
                .environmentObject(session)
        }
    }

    private var albumInfo: String {
        var pieces: [String] = []
        if let type = value.type, !type.isEmpty {
            pieces.append(type.capitalized)
        } else {
            pieces.append("Album")
        }
        if let year = value.year, !year.isEmpty {
            pieces.append(year)
        }
        let knownCount = !tracks.isEmpty ? tracks.count : (value.tracks ?? seed.tracks)?.count
        if let knownCount {
            pieces.append(knownCount == 1 ? "1 track" : "\(knownCount) tracks")
        }
        return pieces.joined(separator: " • ")
    }

    private func loadAlbum() async {
        let previouslyKnownIDs = !(seed.tracks ?? []).isEmpty
            ? (seed.tracks ?? [])
            : (session.cachedAlbumDetail(for: seed)?.tracks ?? [])
        let cachedTracks = session.cachedTracksForIDs(
            previouslyKnownIDs,
            refID: seed.id.map { "album:\($0)" }
        )
        if !cachedTracks.isEmpty {
            tracks = cachedTracks
        }
        loading = tracks.isEmpty
        albumLoadMessage = ""
        let detail: LaneAlbum
        do {
            detail = try await session.fetchAlbumDetailStrict(seed)
        } catch {
            session.output = "Album detail error: \(error.localizedDescription)"
            albumLoadMessage = "Could not load this album. Try again."
            detail = session.cachedAlbumDetail(for: seed) ?? seed
        }
        album = detail
        let trackIDs = !(detail.tracks ?? []).isEmpty
            ? (detail.tracks ?? [])
            : (session.cachedAlbumDetail(for: seed)?.tracks ?? seed.tracks ?? [])
        guard !trackIDs.isEmpty else {
            if tracks.isEmpty && albumLoadMessage.isEmpty {
                albumLoadMessage = "Lane returned no tracks for this album. Try again."
            }
            loading = false
            return
        }
        let resolved = await session.resolveTracksByIDs(
            trackIDs,
            prefetch: false,
            refID: detail.id.map { "album:\($0)" }
        )
        if !resolved.isEmpty { tracks = resolved }
        if tracks.isEmpty {
            albumLoadMessage = session.trackResolveMessage.isEmpty
                ? "Could not resolve this album's tracks. Try again."
                : session.trackResolveMessage
        }
        loading = false
    }

    private func play(shuffled: Bool) {
        guard !tracks.isEmpty else { return }
        let list = shuffled ? tracks.shuffled() : tracks
        session.queue = list
        session.currentIndex = 0
        session.requestStream(for: list[0])
    }
}


private struct APKAlbumTrackRow: View {
    @EnvironmentObject private var session: LaneSession
    let index: Int
    let track: TrackCandidate
    let onTap: () -> Void
    @State private var showActions = false

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.48))
                .frame(width: 22, alignment: .center)

            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        APKPlatformIcon(platform: track.platform, size: 9)
                        Text(track.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.58))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if let duration = track.duration, !duration.isEmpty {
                Text(duration)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.42))
            }

            Button {
                showActions = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .frame(width: 34, height: 46)
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 58)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.055))
                .frame(height: 1)
                .padding(.leading, 34)
        }
        .sheet(isPresented: $showActions) {
            APKTrackActionsSheet(track: track)
        }
    }
}


struct APKArtistDetailScreen: View {
    @EnvironmentObject private var session: LaneSession
    let seed: LaneArtist

    @State private var artist: LaneArtist?
    @State private var topTracks: [TrackCandidate] = []
    @State private var recentTracks: [TrackCandidate] = []
    @State private var loading = true
    @State private var libraryActionError: String?
    @State private var showPlayer = false

    private var value: LaneArtist { artist ?? seed }
    private var isSavedToLibrary: Bool { session.isArtistSaved(value) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    APKRemoteImage(url: value.headerUrl ?? value.avatarUrl, cornerRadius: 0)
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipped()
                        .overlay {
                            LinearGradient(
                                colors: [.clear, apkBackground.opacity(0.34), apkBackground],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }

                    HStack(alignment: .bottom, spacing: 14) {
                        APKRemoteImage(url: value.avatarUrl, circle: true)
                            .frame(width: 94, height: 94)
                            .overlay(Circle().stroke(apkBackground, lineWidth: 4))

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text(value.name ?? "Artist")
                                    .font(.system(size: 27, weight: .bold))
                                    .lineLimit(2)

                                if value.verified == true {
                                    APKVerifiedBadge(size: 13)
                                }
                            }

                            HStack(spacing: 5) {
                                APKPlatformIcon(platform: value.platform, size: 10)
                                Text(value.platform?.capitalized ?? "Artist")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }

                VStack(alignment: .leading, spacing: 22) {
                    if loading {
                        ProgressView()
                            .tint(apkPink)
                            .frame(maxWidth: .infinity)
                    }

                    if !topTracks.isEmpty || value.id != nil {
                        HStack(spacing: 12) {
                            Button {
                                play(topTracks, shuffled: false)
                            } label: {
                                HStack(spacing: 7) {
                                    APKTemplateIcon(name: "baseline_play_arrow_24", size: 20, color: .black)
                                    Text("Play")
                                        .font(.system(size: 15, weight: .bold))
                                }
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                    .background(apkPink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(topTracks.isEmpty)

                            Button {
                                Task {
                                    do {
                                        libraryActionError = nil
                                        try await session.setArtistSaved(value, saved: !isSavedToLibrary)
                                    } catch {
                                        libraryActionError = error.localizedDescription
                                    }
                                }
                            } label: {
                                Group {
                                    if isSavedToLibrary {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 19, weight: .bold))
                                    } else {
                                        APKTemplateIcon(name: "ic_lib_outline", size: 22, color: .white)
                                    }
                                }
                                .frame(width: 46, height: 46)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isSavedToLibrary ? "Remove artist from Library" : "Add artist to Library")

                            Button {
                                play(topTracks, shuffled: true)
                            } label: {
                                APKTemplateIcon(name: "shuffle", size: 21, color: .white)
                                    .frame(width: 46, height: 46)
                                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(topTracks.isEmpty)
                        }

                        if let libraryActionError {
                            Text(libraryActionError)
                                .font(.system(size: 12))
                                .foregroundStyle(apkPink)
                        }
                    }

                    if let description = value.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }

                    if !topTracks.isEmpty {
                        trackSection(title: "Music", tracks: topTracks)
                    }

                    if !recentTracks.isEmpty {
                        trackSection(title: "Recent tracks", tracks: recentTracks)
                    }

                    if let albums = value.albums, !albums.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Albums")
                                    .font(.system(size: 20, weight: .bold))
                                Spacer()
                                if albums.count > 4 {
                                    NavigationLink {
                                        APKArtistAlbumsScreen(albums: albums)
                                    } label: {
                                        Text("Show all")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color.white.opacity(0.50))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            ForEach(Array(albums.prefix(6).enumerated()), id: \.offset) { _, album in
                                APKAlbumCardRow(album: album)
                            }
                        }
                    }

                    if let biography = value.biography, !biography.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About")
                                .font(.system(size: 20, weight: .bold))
                            Text(biography)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let related = value.relatedArtists, !related.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Related artists")
                                    .font(.system(size: 20, weight: .bold))
                                Spacer()
                                if related.count > 5 {
                                    NavigationLink {
                                        APKRelatedArtistsScreen(artists: related)
                                    } label: {
                                        Text("Show all")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color.white.opacity(0.50))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(Array(related.prefix(10).enumerated()), id: \.offset) { _, relatedArtist in
                                        NavigationLink {
                                            APKArtistDetailScreen(
                                                seed: LaneArtist(
                                                    name: relatedArtist.name,
                                                    id: relatedArtist.id,
                                                    platform: relatedArtist.platform,
                                                    avatarUrl: relatedArtist.avatarUrl
                                                )
                                            )
                                        } label: {
                                            VStack(spacing: 8) {
                                                APKRemoteImage(url: relatedArtist.avatarUrl, circle: true)
                                                    .frame(width: 88, height: 88)

                                                Text(relatedArtist.name ?? "Artist")
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                    .frame(width: 96)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(apkBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let cached = session.cachedArtistDetail(for: seed) {
                artist = cached
                let context = cached.id.map { "artist:\($0)" }
                topTracks = session.cachedTracksForIDs(cached.topTracks ?? [], refID: context)
                recentTracks = session.cachedTracksForIDs(cached.recentTracks ?? [], refID: context)
                loading = false
            }
            let detail = await session.fetchArtistDetail(seed)
            artist = detail

            let artistContext = detail.id.map { "artist:\($0)" }
            topTracks = await session.resolveTracksByIDs(
                detail.topTracks ?? [],
                prefetch: false,
                refID: artistContext
            )
            recentTracks = await session.resolveTracksByIDs(
                detail.recentTracks ?? [],
                prefetch: false,
                refID: artistContext
            )

            loading = false
        }
        .fullScreenCover(isPresented: $showPlayer) {
            APKFullPlayerView()
                .environmentObject(session)
        }
    }

    @ViewBuilder
    private func trackSection(title: String, tracks: [TrackCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                if tracks.count > 5 {
                    NavigationLink {
                        APKArtistTracksScreen(title: title, tracks: tracks)
                    } label: {
                        Text("Show all")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.50))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(tracks.prefix(5).enumerated()), id: \.element.id) { index, track in
                    APKAlbumTrackRow(
                        index: index + 1,
                        track: track,
                        onTap: {
                            session.queue = tracks
                            session.currentIndex = index
                            session.requestStream(for: track)
                        }
                    )
                }
            }
        }
    }

    private func play(_ tracks: [TrackCandidate], shuffled: Bool) {
        guard !tracks.isEmpty else { return }
        let list = shuffled ? tracks.shuffled() : tracks
        session.queue = list
        session.currentIndex = 0
        session.requestStream(for: list[0])
    }
}

private struct APKArtistTracksScreen: View {
    @EnvironmentObject private var session: LaneSession
    let title: String
    let tracks: [TrackCandidate]
    @State private var showPlayer = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    APKAlbumTrackRow(index: index + 1, track: track) {
                        session.queue = tracks
                        session.currentIndex = index
                        session.requestStream(for: track)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(apkBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showPlayer) {
            APKFullPlayerView().environmentObject(session)
        }
    }
}

private struct APKArtistAlbumsScreen: View {
    let albums: [LaneAlbum]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(albums.enumerated()), id: \.offset) { _, album in
                    APKAlbumCardRow(album: album)
                }
            }
            .padding(.vertical, 12)
        }
        .background(apkBackground.ignoresSafeArea())
        .navigationTitle("Albums")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct APKRelatedArtistsScreen: View {
    let artists: [LaneRelatedArtist]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(artists.enumerated()), id: \.offset) { _, related in
                    APKArtistCardRow(artist: LaneArtist(
                        name: related.name,
                        id: related.id,
                        platform: related.platform,
                        avatarUrl: related.avatarUrl
                    ))
                }
            }
            .padding(.vertical, 12)
        }
        .background(apkBackground.ignoresSafeArea())
        .navigationTitle("Artists")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct APKCommentsScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss

    let track: TrackCandidate
    @State private var text = ""
    @State private var replyingTo: LaneTrackCommentDTO?
    @State private var replyParent: LaneTrackCommentDTO?
    @State private var expandedReplies: Set<String> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 42, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 14)

                HStack {
                    Text("Comments")
                        .font(.system(size: 20, weight: .bold))
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                }
                .padding(.horizontal, 16)

                if session.busy && session.comments.isEmpty {
                    Spacer()
                    ProgressView().tint(apkPink)
                    Spacer()
                } else if session.comments.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 38))
                            .foregroundStyle(.secondary)
                        Text("No comments yet")
                            .font(.headline)
                        Text(session.output)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(session.comments) { comment in
                                HStack(alignment: .top, spacing: 11) {
                                    APKRemoteImage(url: comment.userAvatar, circle: true)
                                        .frame(width: 40, height: 40)

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(comment.userName ?? "Lane user")
                                                .font(.system(size: 14, weight: .bold))
                                            Spacer()
                                            if let timestamp = comment.timestamp {
                                                Text(Self.relative(timestamp))
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }

                                        Text(comment.text ?? "")
                                            .font(.system(size: 15))
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        HStack(spacing: 16) {
                                            Button {
                                                session.toggleCommentLike(comment, for: track)
                                            } label: {
                                                Label(
                                                    "\(comment.likesCount ?? 0)",
                                                    systemImage: comment.isLiked == true ? "heart.fill" : "heart"
                                                )
                                                .foregroundStyle(comment.isLiked == true ? apkPink : .secondary)
                                            }
                                            .buttonStyle(.plain)

                                            Button("Reply") {
                                                replyParent = comment
                                                replyingTo = comment
                                            }
                                            .foregroundStyle(.secondary)

                                            if (comment.repliesCount ?? 0) > 0 {
                                                Button {
                                                    if expandedReplies.contains(comment.id) {
                                                        expandedReplies.remove(comment.id)
                                                    } else {
                                                        expandedReplies.insert(comment.id)
                                                        session.loadReplies(for: comment)
                                                    }
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        if session.loadingReplyIDs.contains(comment.id) {
                                                            ProgressView()
                                                                .controlSize(.mini)
                                                        }
                                                        Text(
                                                            expandedReplies.contains(comment.id)
                                                                ? "Hide replies"
                                                                : "Show \(comment.repliesCount ?? 0) replies"
                                                        )
                                                    }
                                                }
                                                .foregroundStyle(.secondary)
                                            }
                                        }
                                        .font(.caption)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                if expandedReplies.contains(comment.id),
                                   let replies = session.commentReplies[comment.id] {
                                    VStack(spacing: 0) {
                                        ForEach(replies) { reply in
                                            HStack(alignment: .top, spacing: 9) {
                                                APKRemoteImage(url: reply.userAvatar, circle: true)
                                                    .frame(width: 30, height: 30)

                                                VStack(alignment: .leading, spacing: 5) {
                                                    HStack(spacing: 5) {
                                                        Text(reply.userName ?? "Lane user")
                                                            .font(.system(size: 12, weight: .bold))

                                                        if let replyName = reply.replyToUserName,
                                                           !replyName.isEmpty {
                                                            Text("→ @\(replyName)")
                                                                .font(.system(size: 11))
                                                                .foregroundStyle(.secondary)
                                                        }

                                                        Spacer()

                                                        if let timestamp = reply.timestamp {
                                                            Text(Self.relative(timestamp))
                                                                .font(.caption2)
                                                                .foregroundStyle(.tertiary)
                                                        }
                                                    }

                                                    Text(reply.text ?? "")
                                                        .font(.system(size: 13))
                                                        .frame(maxWidth: .infinity, alignment: .leading)

                                                    HStack(spacing: 14) {
                                                        Button {
                                                            session.toggleReplyLike(reply, parentComment: comment)
                                                        } label: {
                                                            Label(
                                                                "\(reply.likesCount ?? 0)",
                                                                systemImage: reply.isLiked == true ? "heart.fill" : "heart"
                                                            )
                                                            .foregroundStyle(reply.isLiked == true ? apkPink : .secondary)
                                                        }
                                                        .buttonStyle(.plain)

                                                        Button("Reply") {
                                                            replyParent = comment
                                                            replyingTo = reply
                                                        }
                                                        .foregroundStyle(.secondary)
                                                    }
                                                    .font(.caption)
                                                }
                                            }
                                            .padding(.leading, 66)
                                            .padding(.trailing, 16)
                                            .padding(.vertical, 8)
                                        }
                                    }
                                }

                                Divider()
                                    .padding(.leading, 67)
                            }
                        }
                    }
                }

                VStack(spacing: 0) {
                    if let replyingTo {
                        HStack {
                            Text("Replying to @\(replyingTo.userName ?? "user")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                self.replyingTo = nil
                                replyParent = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 9)
                    }

                    HStack(spacing: 10) {
                        TextField(
                            replyingTo == nil ? "Write a comment…" : "Write a reply…",
                            text: $text,
                            axis: .vertical
                        )
                        .lineLimit(1...4)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))

                        Button {
                            let outgoing = text
                            text = ""

                            if let replyingTo, let replyParent {
                                session.sendReply(outgoing, to: replyParent, replyTo: replyingTo)
                                expandedReplies.insert(replyParent.id)
                                self.replyingTo = nil
                                self.replyParent = nil
                            } else {
                                session.sendComment(outgoing, for: track)
                            }
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 38, height: 38)
                                .background(apkPink, in: Circle())
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(12)
                }
                .background(.ultraThinMaterial)
            }
            .background(apkBackground)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                session.loadComments(for: track)
            }
        }
        .preferredColorScheme(.dark)
    }

    private static func relative(_ raw: Int64) -> String {
        let value = raw > 10_000_000_000 ? Double(raw) / 1000.0 : Double(raw)
        let date = Date(timeIntervalSince1970: value)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct APKWaveLoadingToast: View {
    let coverURL: String?

    var body: some View {
        HStack(spacing: 10) {
            APKRemoteImage(url: coverURL, cornerRadius: 6)
                .frame(width: 38, height: 38)
            Text("Finding a wave…")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            ProgressView()
                .tint(apkPink)
        }
        .padding(8)
        .background(Color(red: 0.14, green: 0.14, blue: 0.14), in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }
}

struct APKFullPlayerView: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss

    @State private var showQueue = false
    @State private var showTrackActions = false
    @State private var showComments = false
    @State private var showLyrics = false
    @State private var draggingProgress = false
    @State private var draggedValue: Double = 0
    @State private var artworkDragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            apkBackground.ignoresSafeArea()

            if let track = session.currentTrack {
                GeometryReader { proxy in
                    ZStack {
                        LaneResilientImage(url: track.coverURL) {
                            Color.clear
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: 40)
                        .scaleEffect(1.25)
                        .opacity(0.42)

                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.30),
                                Color.black.opacity(0.70),
                                Color.black.opacity(0.96)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        VStack(spacing: 0) {
                            topBar
                                .padding(.horizontal, 8)
                                .padding(.top, 6)

                            Spacer(minLength: 12)

                            Group {
                                if showLyrics {
                                    lyricsPanel(track)
                                        .frame(
                                            width: min(proxy.size.width - 32, 430),
                                            height: min(proxy.size.width - 32, 430)
                                        )
                                } else {
                                    APKRemoteImage(url: track.coverURL, cornerRadius: 14)
                                        .aspectRatio(1, contentMode: .fit)
                                        .frame(maxWidth: min(proxy.size.width - 32, 430))
                                        .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
                                }
                            }
                            .padding(.horizontal, 8)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                            .offset(x: artworkDragOffset)
                            .opacity(1 - min(Double(abs(artworkDragOffset)) / 500.0, 0.35))
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 38)
                                    .onChanged { value in
                                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                        artworkDragOffset = value.translation.width * 0.55
                                    }
                                    .onEnded { value in
                                        if abs(value.translation.width) > abs(value.translation.height),
                                           abs(value.translation.width) > 70 {
                                            if value.translation.width < 0 {
                                                session.next()
                                            } else {
                                                session.previous()
                                            }
                                        }
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                            artworkDragOffset = 0
                                        }
                                    }
                            )

                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title)
                                        .font(.system(size: 21, weight: .bold))
                                        .lineLimit(1)

                                    HStack(spacing: 7) {
                                        if let avatars = track.artistAvatars, !avatars.isEmpty {
                                            HStack(spacing: -5) {
                                                ForEach(Array(avatars.prefix(3).enumerated()), id: \.offset) { _, avatar in
                                                    APKRemoteImage(url: avatar, circle: true)
                                                        .frame(width: 20, height: 20)
                                                        .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                                                }
                                            }
                                        }

                                        Text(track.subtitle)
                                            .font(.system(size: 15))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        showLyrics.toggle()
                                    }
                                    if showLyrics, session.currentLyrics == nil {
                                        session.loadLyrics(track)
                                    }
                                } label: {
                                    APKTemplateIcon(
                                        name: "text",
                                        size: 24,
                                        color: showLyrics ? apkPink : .white
                                    )
                                    .frame(width: 40, height: 40)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 18)

                            progress(track)
                                .padding(.top, 14)

                            playbackControls(track)
                                .padding(.horizontal, 24)
                                .padding(.top, 15)

                            actionBar(track)
                                .padding(.horizontal, 24)
                                .padding(.top, 12)

                            if !session.playerError.isEmpty {
                                Text(session.playerError)
                                    .font(.caption)
                                    .foregroundStyle(apkPink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                                    .padding(.top, 8)
                            }

                            Spacer(minLength: 14)
                        }
                    }
                    .clipped()
                }
            }
        }
        .preferredColorScheme(.dark)
        .simultaneousGesture(
            DragGesture(minimumDistance: 45)
                .onEnded { value in
                    guard value.translation.height > 110,
                          abs(value.translation.height) > abs(value.translation.width) * 1.25 else { return }
                    dismiss()
                }
        )
        .sheet(isPresented: $showComments) {
            if let track = session.currentTrack {
                APKCommentsScreen(track: track)
                    .environmentObject(session)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.hidden)
            }
        }
        .sheet(isPresented: $showQueue) {
            APKQueueSheet()
                .environmentObject(session)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTrackActions) {
            if let track = session.currentTrack {
                APKTrackActionsSheet(track: track)
                    .environmentObject(session)
            }
        }
        .overlay(alignment: .bottom) {
            if session.waveIsLoading {
                APKWaveLoadingToast(coverURL: session.waveSourceCoverURL)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
            }
        }
        .alert("Wave", isPresented: Binding(
            get: { session.waveError != nil },
            set: { if !$0 { session.waveError = nil } }
        )) {
            Button("OK", role: .cancel) { session.waveError = nil }
        } message: {
            Text(session.waveError ?? "Could not create a wave.")
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 40, height: 40)
            }

            Spacer()

            VStack(spacing: 1) {
                Text("PLAYING FROM")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(playerSource)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 220)
            }

            Spacer()

            Button {
                showTrackActions = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
        }
        .buttonStyle(.plain)
    }

    private var playerSource: String {
        guard let refID = session.currentTrack?.refID, !refID.isEmpty else { return "Lane" }

        if refID == "lane_likes" { return "Liked tracks" }
        if refID.hasPrefix("album:") {
            let id = String(refID.dropFirst("album:".count))
            let album = (session.serverAlbums + session.searchAlbums).first { $0.id == id }
            return album?.name.map { "Album \"\($0)\"" } ?? "Album"
        }
        if refID.hasPrefix("artist:") {
            let id = String(refID.dropFirst("artist:".count))
            let artist = (session.serverArtists + session.searchArtists).first { $0.id == id }
            return artist?.name ?? "Artist"
        }
        if let playlist = (session.serverPlaylists + session.searchPlaylists).first(where: { $0.playlistId == refID }) {
            return playlist.playlistName.map { "Playlist \"\($0)\"" } ?? "Playlist"
        }
        return "Lane"
    }

    @ViewBuilder
    private func lyricsPanel(_ track: TrackCandidate) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.30))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }

            if let lyrics = session.currentLyrics, !lyrics.lines.isEmpty {
                ScrollViewReader { reader in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                                let active = index == activeLyricsIndex(in: lyrics)

                                Button {
                                    let seconds = Double(line.startMilliseconds) / 1000.0
                                    session.seek(to: seconds)
                                } label: {
                                    Text(line.words.isEmpty ? "♪" : line.words)
                                        .font(.system(size: active ? 21 : 17, weight: active ? .bold : .semibold))
                                        .foregroundStyle(active ? Color.white : Color.white.opacity(0.43))
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .scaleEffect(active ? 1.02 : 1.0, anchor: .leading)
                                }
                                .buttonStyle(.plain)
                                .id(line.id)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 26)
                    }
                    .onChange(of: activeLyricsIndex(in: lyrics)) { index in
                        guard lyrics.lines.indices.contains(index) else { return }
                        withAnimation(.easeOut(duration: 0.30)) {
                            reader.scrollTo(lyrics.lines[index].id, anchor: .center)
                        }
                    }
                }
            } else if !session.lyricsError.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)

                    Text("Lyrics unavailable")
                        .font(.headline)

                    Text(session.lyricsError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                }
                .padding(24)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading lyrics…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onAppear {
                    if session.currentLyrics == nil {
                        session.loadLyrics(track)
                    }
                }
            }
        }
    }

    private func activeLyricsIndex(in lyrics: LaneTrackLyrics) -> Int {
        guard !lyrics.lines.isEmpty else { return 0 }

        let currentMs = Int64(max(0, session.playbackPosition * 1000))
        var result = 0

        for (index, line) in lyrics.lines.enumerated() {
            if line.startMilliseconds <= currentMs {
                result = index
            } else {
                break
            }
        }

        return result
    }

    private func progress(_ track: TrackCandidate) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let fraction = draggingProgress
                    ? draggedValue
                    : (session.playbackDuration > 0
                        ? session.playbackPosition / session.playbackDuration
                        : 0)
                let clamped = min(max(fraction, 0), 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.24))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.white)
                        .frame(width: geometry.size.width * CGFloat(clamped), height: 4)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .offset(x: geometry.size.width * CGFloat(clamped) - 6)
                }
                .frame(height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard session.playbackDuration > 0 else { return }
                            draggingProgress = true
                            draggedValue = Double(min(max(value.location.x / max(geometry.size.width, 1), 0), 1))
                        }
                        .onEnded { value in
                            guard session.playbackDuration > 0 else { return }
                            let position = min(max(value.location.x / max(geometry.size.width, 1), 0), 1)
                            session.seek(to: Double(position) * session.playbackDuration)
                            draggingProgress = false
                        }
                )
            }
            .frame(height: 28)
            .accessibilityElement()
            .accessibilityLabel("Playback position")
            .accessibilityValue(formatTime(session.playbackPosition))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    session.seek(to: min(session.playbackPosition + 10, session.playbackDuration))
                case .decrement:
                    session.seek(to: max(session.playbackPosition - 10, 0))
                @unknown default:
                    break
                }
            }

            HStack {
                Text(formatTime(draggingProgress ? draggedValue * session.playbackDuration : session.playbackPosition))
                Spacer()
                Text("-" + formatTime(max(0, session.playbackDuration - (draggingProgress ? draggedValue * session.playbackDuration : session.playbackPosition))))
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
    }

    private func playbackControls(_ track: TrackCandidate) -> some View {
        HStack {
            Button {
                session.toggleShuffle()
            } label: {
                APKTemplateIcon(
                    name: "shuffle",
                    size: 24,
                    color: session.shuffleEnabled ? apkPink : .white
                )
            }

            Spacer()

            Button { session.previous() } label: {
                APKTemplateIcon(name: "skip_backward", size: 32, color: .white)
            }

            Spacer()

            Button {
                session.togglePlayback()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 60, height: 60)

                    if session.isBuffering {
                        ProgressView()
                            .tint(.black)
                    } else {
                        APKTemplateIcon(
                            name: session.isPlaying ? "baseline_pause_24" : "baseline_play_arrow_24",
                            size: 34,
                            color: .black
                        )
                    }
                }
            }

            Spacer()

            Button { session.next() } label: {
                APKTemplateIcon(name: "skip_forward", size: 32, color: .white)
            }

            Spacer()

            Button {
                session.cycleRepeatMode()
            } label: {
                APKTemplateIcon(
                    name: session.repeatMode == 2 ? "repeat_1" : "repeat",
                    size: 24,
                    color: session.repeatMode == 0 ? .white : apkPink
                )
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 17)
        .background(
            Color(red: 17.0 / 255.0, green: 17.0 / 255.0, blue: 17.0 / 255.0)
                .opacity(0.20),
            in: RoundedRectangle(cornerRadius: 32, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func actionBar(_ track: TrackCandidate) -> some View {
        HStack {
            HStack(spacing: 24) {
                actionCount(
                    asset: session.isFavorite(track) ? "like" : "heart",
                    value: compactCount(session.trackStats?.likesCount ?? 0),
                    active: session.isFavorite(track)
                ) {
                    session.toggleFavorite(track)
                    session.loadTrackStats(track)
                }

                actionCount(
                    asset: "comment",
                    value: compactCount(session.trackStats?.commentsCount ?? 0),
                    active: false
                ) {
                    session.loadComments(for: track)
                    showComments = true
                }
            }

            Spacer()

            HStack(spacing: 20) {
                Button {
                    session.downloadTrack(track)
                } label: {
                    APKTemplateIcon(
                        name: "ic_download",
                        size: 22,
                        color: session.isDownloaded(track) ? apkPink : .white
                    )
                }

                Button {
                    showQueue = true
                } label: {
                    APKTemplateIcon(name: "queue", size: 24, color: .white)
                        .offset(y: 2)
                }
            }
        }
        .frame(height: 40)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            Color(red: 17.0 / 255.0, green: 17.0 / 255.0, blue: 17.0 / 255.0)
                .opacity(0.20),
            in: RoundedRectangle(cornerRadius: 27, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .buttonStyle(.plain)
    }


    private func actionCount(
        asset: String,
        value: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                APKTemplateIcon(
                    name: asset,
                    size: 22,
                    color: active ? Color(red: 233.0 / 255.0, green: 30.0 / 255.0, blue: 99.0 / 255.0) : .white
                )
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
            }
            .scaleEffect(active ? 1.2 : 1.0)
            .foregroundStyle(
                active
                    ? Color(red: 233.0 / 255.0, green: 30.0 / 255.0, blue: 99.0 / 255.0)
                    : .white
            )
        }
        .buttonStyle(.plain)
    }

    private func compactCount(_ count: Int64) -> String {
        if count >= 1_000_000 {
            let value = Double(count) / 1_000_000.0
            return value >= 10 ? String(format: "%.0fM", value) : String(format: "%.1fM", value)
        }
        if count >= 1_000 {
            let value = Double(count) / 1_000.0
            return value >= 10 ? String(format: "%.0fK", value) : String(format: "%.1fK", value)
        }
        return "\(count)"
    }

    private func playerAction(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                Text(title)
                    .font(.system(size: 10))
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct APKQueueSheet: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss

    private var current: TrackCandidate? {
        if let index = session.currentIndex, session.queue.indices.contains(index) {
            return session.queue[index]
        }
        return session.currentTrack
    }

    private var upNext: [(offset: Int, element: TrackCandidate)] {
        let start = min((session.currentIndex ?? -1) + 1, session.queue.count)
        return Array(session.queue.enumerated().dropFirst(start))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(0.32))
                        .frame(width: 42, height: 5)
                        .padding(.top, 8)
                        .padding(.bottom, 18)

                    HStack {
                        Text("Queue")
                            .font(.system(size: 22, weight: .bold))
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.075), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                    queueContextHeader

                    if let current {
                        sectionHeader("Now playing")

                        queueRow(
                            track: current,
                            active: true,
                            dragHandle: false,
                            onTap: {}
                        )
                    }

                    if !upNext.isEmpty {
                        sectionHeader("Next in queue")

                        ForEach(upNext, id: \.element.id) { entry in
                            queueRow(
                                track: entry.element,
                                active: false,
                                dragHandle: true,
                                onTap: {
                                    session.currentIndex = entry.offset
                                    session.requestStream(for: entry.element)
                                    dismiss()
                                }
                            )
                            .draggable(entry.element.id)
                            .dropDestination(for: String.self) { identifiers, _ in
                                guard let sourceID = identifiers.first else { return false }
                                return moveQueueItem(sourceID: sourceID, before: entry.element.id)
                            }
                        }
                    } else if current != nil {
                        Text("Nothing else in the queue")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(apkBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var queueContextHeader: some View {
        if let refID = session.currentTrack?.refID,
           !refID.isEmpty {
            let info = contextInfo(refID)

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.065))

                        APKTemplateIcon(
                            name: info.icon,
                            size: 18,
                            color: apkPink
                        )
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Playing from")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.55))

                        Text(info.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .frame(maxWidth: 140, alignment: .leading)
                    }

                    Spacer()
                }
                .padding(10)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                }

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
    }

    private func queueRow(
        track: TrackCandidate,
        active: Bool,
        dragHandle: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    APKRemoteImage(url: track.coverURL, cornerRadius: 5)
                        .frame(width: 50, height: 50)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(active ? apkPink : .white)
                            .lineLimit(1)

                        HStack(spacing: 5) {
                            APKPlatformIcon(platform: track.platform, size: 9)
                            Text(track.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .disabled(active)

            if active {
                Image(systemName: session.isPlaying ? "waveform" : "pause.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(apkPink)
                    .frame(width: 30)
            } else if dragHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .frame(width: 30, height: 50)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            active ? Color.white.opacity(0.045) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .padding(.horizontal, 6)
    }

    private func contextInfo(_ refID: String) -> (title: String, icon: String) {
        if refID.hasPrefix("album:") {
            return ("Album", "album")
        }
        if refID.hasPrefix("artist:") {
            return ("Artist", "artist")
        }
        if refID.hasPrefix("history:") {
            return ("Listening history", "history")
        }
        if refID.hasPrefix("playlist:") {
            return ("Playlist", "playlist")
        }
        return ("Lane", "lane")
    }

    private func moveQueueItem(sourceID: String, before destinationID: String) -> Bool {
        guard sourceID != destinationID,
              let from = session.queue.firstIndex(where: { $0.id == sourceID }),
              let to = session.queue.firstIndex(where: { $0.id == destinationID }) else {
            return false
        }

        let item = session.queue.remove(at: from)
        let target = from < to ? max(0, to - 1) : to
        session.queue.insert(item, at: target)

        if let current = session.currentTrack {
            session.currentIndex = session.queue.firstIndex(of: current)
        }

        return true
    }
}


// MARK: - Android Lane home feed parity

struct APKHomeFeedView: View {
    @EnvironmentObject private var session: LaneSession
    let sections: [LaneHomeSection]
    @Binding var showPlayer: Bool

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(sections) { section in
                APKHomeSectionView(section: section, showPlayer: $showPlayer)
            }
        }
    }
}

private struct APKHomeSectionView: View {
    @EnvironmentObject private var session: LaneSession
    let section: LaneHomeSection
    @Binding var showPlayer: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if section.title != nil || section.subtitle != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let title = section.title, !title.isEmpty {
                        Text(displayTitle(title))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    if let subtitle = section.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.56))
                    }
                }
                .padding(.horizontal, 16)
            }

            switch section.renderType {
            case .horizontalList:
                horizontalContent

            case .grid2x2:
                gridContent

            case .fullWidth:
                fullWidthContent

            case .verticalList:
                verticalContent
            }
        }
    }

    private var horizontalContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(section.content) { item in
                    switch item.kind {
                    case .playlist:
                        if let playlist = item.playlist {
                            NavigationLink {
                                PlaylistDetailScreen(playlist: playlist, showPlayer: $showPlayer)
                            } label: {
                                APKHomePlaylistCard(playlist: playlist)
                            }
                            .buttonStyle(.plain)
                        }

                    case .chart:
                        if let playlist = item.playlist {
                            APKHomeChartCard(playlist: playlist, showPlayer: $showPlayer)
                                .frame(width: 330)
                        }

                    case .banner:
                        if let banner = item.banner {
                            APKHomeBannerCard(banner: banner)
                                .frame(width: 320)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var gridContent: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            ForEach(section.content) { item in
                switch item.kind {
                case .playlist:
                    if let playlist = item.playlist {
                        NavigationLink {
                            PlaylistDetailScreen(playlist: playlist, showPlayer: $showPlayer)
                        } label: {
                            APKHomePlaylistCard(playlist: playlist, compact: true)
                        }
                        .buttonStyle(.plain)
                    }

                case .chart:
                    if let playlist = item.playlist {
                        APKHomeChartCard(playlist: playlist, showPlayer: $showPlayer, compact: true)
                    }

                case .banner:
                    if let banner = item.banner {
                        APKHomeBannerCard(banner: banner, compact: true)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var fullWidthContent: some View {
        VStack(spacing: 12) {
            ForEach(section.content) { item in
                switch item.kind {
                case .playlist:
                    if let playlist = item.playlist {
                        NavigationLink {
                            PlaylistDetailScreen(playlist: playlist, showPlayer: $showPlayer)
                        } label: {
                            APKHomeFullWidthPlaylistCard(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }

                case .chart:
                    if let playlist = item.playlist {
                        APKHomeChartCard(playlist: playlist, showPlayer: $showPlayer)
                    }

                case .banner:
                    if let banner = item.banner {
                        APKHomeBannerCard(banner: banner)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var verticalContent: some View {
        VStack(spacing: 8) {
            ForEach(section.content) { item in
                switch item.kind {
                case .playlist:
                    if let playlist = item.playlist {
                        NavigationLink {
                            PlaylistDetailScreen(playlist: playlist, showPlayer: $showPlayer)
                        } label: {
                            APKHomePlaylistRow(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }

                case .chart:
                    if let playlist = item.playlist {
                        APKHomeChartCard(playlist: playlist, showPlayer: $showPlayer)
                    }

                case .banner:
                    if let banner = item.banner {
                        APKHomeBannerCard(banner: banner)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func displayTitle(_ raw: String) -> String {
        guard section.type == .chart else { return raw }

        let pieces = raw.split(separator: " ")
        guard let last = pieces.last,
              last.count == 2,
              last.allSatisfy({ $0.isLetter }) else {
            return raw
        }

        let code = String(last).uppercased()
        let base = pieces.dropLast().joined(separator: " ")
        let flag = code.unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            UnicodeScalar(127397 + Int(scalar.value))
        }.map(String.init).joined()

        return base.isEmpty ? flag : "\(base) \(flag)"
    }
}

private struct APKHomePlaylistCard: View {
    let playlist: LanePlaylist
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            APKRemoteImage(url: playlist.playlistImageUrl, cornerRadius: 10)
                .aspectRatio(1, contentMode: .fill)
                .frame(width: compact ? 150 : 158, height: compact ? 150 : 158)
                .clipped()

            Text(playlist.playlistName ?? "Playlist")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            let count = playlist.tracksCount ?? playlist.playlistTracks?.count ?? 0
            Text(count == 1 ? "1 track" : "\(count) tracks")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
        }
        .frame(width: compact ? 150 : 158, alignment: .leading)
    }
}

private struct APKHomePlaylistRow: View {
    let playlist: LanePlaylist

    var body: some View {
        HStack(spacing: 12) {
            APKRemoteImage(url: playlist.playlistImageUrl, cornerRadius: 8)
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.playlistName ?? "Playlist")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                let count = playlist.tracksCount ?? playlist.playlistTracks?.count ?? 0
                Text(count == 1 ? "1 track" : "\(count) tracks")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(8)
        .background(apkSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct APKHomeFullWidthPlaylistCard: View {
    let playlist: LanePlaylist

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            APKRemoteImage(url: playlist.playlistImageUrl, cornerRadius: 12)
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.84)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.playlistName ?? "Playlist")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                if let description = playlist.playlistDescription, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(2)
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
    }
}

private struct APKHomeChartCard: View {
    @EnvironmentObject private var session: LaneSession
    let playlist: LanePlaylist
    @Binding var showPlayer: Bool
    var compact = false

    private var tracks: [TrackCandidate] {
        let context = playlist.playlistId
        return (playlist.playlistTracks ?? []).map { TrackCandidate($0, refID: context) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                APKRemoteImage(url: playlist.playlistImageUrl, cornerRadius: 8)
                    .frame(width: compact ? 48 : 58, height: compact ? 48 : 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.playlistName ?? "Chart")
                        .font(.system(size: compact ? 14 : 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    let count = playlist.tracksCount ?? playlist.playlistTracks?.count ?? 0
                    Text("\(count) tracks")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.55))
                }

                Spacer()
            }

            if tracks.isEmpty {
                Text("Open chart")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(apkPink)
            } else {
                ForEach(Array(tracks.prefix(compact ? 2 : 4).enumerated()), id: \.element.id) { index, track in
                    Button {
                        session.queue = tracks
                        session.currentIndex = index
                        session.requestStream(for: track)
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.45))
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                Text(track.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.white.opacity(0.50))
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.white.opacity(0.70))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(apkSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct APKHomeBannerCard: View {
    @Environment(\.openURL) private var openURL
    let banner: LaneHomeBanner
    var compact = false

    var body: some View {
        Button {
            if let url = URL(string: banner.actionURL) {
                openURL(url)
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color(from: banner.backgroundColor))

                APKRemoteImage(url: banner.imageURL, cornerRadius: 14)
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 145 : 180)
                    .clipped()
                    .opacity(0.86)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.82)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(banner.title)
                        .font(.system(size: compact ? 16 : 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(banner.description)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(2)

                    if let button = banner.buttonText, !button.isEmpty {
                        Text(button)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Color.white, in: Capsule())
                            .padding(.top, 4)
                    }
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 145 : 180)
        }
        .buttonStyle(.plain)
    }

    private func color(from value: String) -> Color {
        let clean = value
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count == 6, let rgb = UInt64(clean, radix: 16) else {
            return apkSurface
        }

        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}
