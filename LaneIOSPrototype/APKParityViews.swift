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
                Image(uiImage: image.withRenderingMode(.alwaysOriginal))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Text("LANE")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .tracking(-0.5)
            }
        }
        .frame(width: 104, height: 22, alignment: .leading)
        .clipped()
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

private struct APKRemoteImage: View {
    let url: String?
    var cornerRadius: CGFloat = 8
    var circle = false

    var body: some View {
        AsyncImage(url: URL(string: url ?? "")) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Color.white.opacity(0.07)
                    Image(systemName: circle ? "person.fill" : "music.note")
                        .foregroundStyle(.secondary)
                }
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
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.blue)
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
}


struct APKArtistDetailScreen: View {
    @EnvironmentObject private var session: LaneSession
    let seed: LaneArtist

    @State private var artist: LaneArtist?
    @State private var loading = true

    private var value: LaneArtist { artist ?? seed }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    APKRemoteImage(url: value.headerUrl ?? value.avatarUrl, cornerRadius: 0)
                        .frame(maxWidth: .infinity)
                        .frame(height: 250)
                        .clipped()
                        .overlay {
                            LinearGradient(
                                colors: [.clear, apkBackground.opacity(0.35), apkBackground],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }

                    HStack(alignment: .bottom, spacing: 16) {
                        APKRemoteImage(url: value.avatarUrl, circle: true)
                            .frame(width: 96, height: 96)
                            .overlay(Circle().stroke(apkBackground, lineWidth: 4))

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text(value.name ?? "Artist")
                                    .font(.system(size: 28, weight: .bold))
                                if value.verified == true {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.blue)
                                }
                            }

                            Text(value.platform ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
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

                    if let description = value.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }

                    if let biography = value.biography, !biography.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About")
                                .font(.title3.bold())
                            Text(biography)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let albums = value.albums, !albums.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Albums")
                                .font(.title3.bold())

                            ForEach(Array(albums.enumerated()), id: \.offset) { _, album in
                                APKAlbumCardRow(album: album)
                            }
                        }
                    }

                    if let related = value.relatedArtists, !related.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Related artists")
                                .font(.title3.bold())

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(Array(related.enumerated()), id: \.offset) { _, relatedArtist in
                                        VStack(spacing: 8) {
                                            APKRemoteImage(url: relatedArtist.avatarUrl, circle: true)
                                                .frame(width: 92, height: 92)
                                            Text(relatedArtist.name ?? "Artist")
                                                .font(.system(size: 13, weight: .semibold))
                                                .lineLimit(1)
                                                .frame(width: 100)
                                        }
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
            artist = await session.fetchArtistDetail(seed)
            loading = false
        }
    }
}

struct APKCommentsScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss

    let track: TrackCandidate
    @State private var text = ""

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

                                            if (comment.repliesCount ?? 0) > 0 {
                                                Label("\(comment.repliesCount ?? 0)", systemImage: "arrowshape.turn.up.left")
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .font(.caption)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                Divider()
                                    .padding(.leading, 67)
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    TextField("Write a comment…", text: $text, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))

                    Button {
                        let outgoing = text
                        text = ""
                        session.sendComment(outgoing, for: track)
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

struct APKFullPlayerView: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss

    @State private var showQueue = false
    @State private var showComments = false
    @State private var draggingProgress = false
    @State private var draggedValue: Double = 0

    private var progressBinding: Binding<Double> {
        Binding(
            get: {
                if draggingProgress { return draggedValue }
                guard session.playbackDuration > 0 else { return 0 }
                return min(max(session.playbackPosition / session.playbackDuration, 0), 1)
            },
            set: { newValue in
                draggingProgress = true
                draggedValue = newValue
            }
        )
    }

    var body: some View {
        ZStack {
            apkBackground.ignoresSafeArea()

            if let track = session.currentTrack {
                GeometryReader { proxy in
                    ZStack {
                        AsyncImage(url: URL(string: track.coverURL ?? "")) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                                    .blur(radius: 40)
                                    .scaleEffect(1.25)
                                    .opacity(0.42)
                            }
                        }

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

                            APKRemoteImage(url: track.coverURL, cornerRadius: 14)
                                .aspectRatio(1, contentMode: .fit)
                                .frame(maxWidth: min(proxy.size.width - 32, 430))
                                .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
                                .padding(.horizontal, 8)

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
                Text("NOW PLAYING")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Lane")
                    .font(.system(size: 13, weight: .semibold))
            }

            Spacer()

            Menu {
                if let track = session.currentTrack {
                    Button("Play next", systemImage: "text.insert") { session.playNext(track) }
                    Button("Add to queue", systemImage: "text.badge.plus") { session.addToQueue(track) }
                    Button("Download", systemImage: "arrow.down.circle") { session.downloadTrack(track) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
        }
        .buttonStyle(.plain)
    }

    private func progress(_ track: TrackCandidate) -> some View {
        VStack(spacing: 4) {
            Slider(value: progressBinding, in: 0...1, onEditingChanged: { editing in
                if !editing {
                    let seconds = draggedValue * max(session.playbackDuration, 0)
                    session.seek(to: seconds)
                    draggingProgress = false
                } else {
                    draggingProgress = true
                    draggedValue = session.playbackDuration > 0
                        ? session.playbackPosition / session.playbackDuration
                        : 0
                }
            })
            .tint(.white)

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

    private func secondaryControls(_ track: TrackCandidate) -> some View {
        HStack {
            Button {
                session.toggleShuffle()
            } label: {
                APKTemplateIcon(
                    name: "shuffle",
                    size: 22,
                    color: session.shuffleEnabled ? apkPink : .white
                )
            }

            Spacer()

            Button {
                session.cycleRepeatMode()
            } label: {
                APKTemplateIcon(
                    name: session.repeatMode == 2 ? "repeat_1" : "repeat",
                    size: 22,
                    color: session.repeatMode == 0 ? .white : apkPink
                )
            }

            Spacer()

            Button {
                session.output = "Track effects"
            } label: {
                APKTemplateIcon(name: "ic_track_effect", size: 22, color: .white)
            }

            Spacer()

            Button {
                session.loadLyrics(track)
            } label: {
                APKTemplateIcon(name: "text", size: 22, color: .white)
            }
        }
        .font(.system(size: 22, weight: .medium))
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

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(session.queue.enumerated()), id: \.element.id) { index, track in
                    Button {
                        session.currentIndex = index
                        session.requestStream(for: track)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            APKRemoteImage(url: track.coverURL, cornerRadius: 6)
                                .frame(width: 50, height: 50)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(track.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if index == session.currentIndex {
                                Image(systemName: "waveform")
                                    .foregroundStyle(apkPink)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(apkBackground)
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
