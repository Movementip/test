import SwiftUI

/// APK's shared-content card: sender, cover, content and explicit Open action.
/// A bad/stale link is a retryable screen, not a broken navigation stack.
struct LaneIncomingShareScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss
    let share: LaneIncomingShare
    @State private var item: LaneOpenShareItem?
    @State private var message: String?
    @State private var loading = false
    @State private var showPlayer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if loading { ProgressView().padding(40) }
                    if let item {
                        HStack(spacing: 10) {
                            APKRemoteImage(url: item.userAvatarUrl, cornerRadius: 22).frame(width: 44, height: 44)
                            Text("\(item.userName) shared a \(item.shareContentType)")
                                .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        APKRemoteImage(url: item.shareCoverUrl, cornerRadius: 20)
                            .frame(width: 260, height: 260).clipped()
                        Text(item.title).font(.title2.bold()).multilineTextAlignment(.center)
                        if let artist = item.artistName, item.shareContentType != "artist" {
                            Text(artist).foregroundStyle(.secondary)
                        }
                        if session.isGuest {
                            Text("Sign in to Lane to open this music. The link will stay available here.")
                                .multilineTextAlignment(.center)
                            NavigationLink("Sign in") { TelegramLoginScreen() }
                        } else {
                            openAction(item).accessibilityIdentifier("share.open")
                        }
                    }
                    if let message {
                        Text(message).foregroundStyle(.pink).multilineTextAlignment(.center)
                        Button("Try again") { Task { await load() } }.disabled(loading)
                            .accessibilityIdentifier("share.retry")
                    }
                }
                .frame(maxWidth: .infinity).padding(24)
            }
            .background(Color(red: 14/255, green: 14/255, blue: 14/255))
            .navigationTitle("Shared with you").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }.accessibilityIdentifier("share.close")
                }
            }
            .task(id: share.id) { await load() }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showPlayer) { APKFullPlayerView().environmentObject(session) }
    }

    @ViewBuilder private func openAction(_ item: LaneOpenShareItem) -> some View {
        switch item.shareContentType {
        case "artist":
            NavigationLink("Open artist") {
                APKArtistDetailScreen(seed: LaneArtist(name: item.artistName, id: item.shareItemId,
                                                       avatarUrl: item.shareCoverUrl))
            }
        case "album":
            NavigationLink("Open album") {
                APKAlbumDetailScreen(seed: LaneAlbum(name: item.albumName, id: item.shareItemId,
                                                     coverUrl: item.shareCoverUrl, artistsDisplayedName: item.artistName))
            }
        case "playlist":
            NavigationLink("Open playlist") {
                PlaylistDetailScreen(playlist: LanePlaylist(playlistId: item.shareItemId,
                    playlistImageUrl: item.shareCoverUrl, playlistName: item.playlistName), showPlayer: $showPlayer)
            }
        default:
            Button("Play track") {
                Task {
                    loading = true
                    defer { loading = false }
                    let tracks = await session.resolveTracksByIDs([item.shareItemId], refID: "share:\(share.id)")
                    guard let track = tracks.first else {
                        message = session.trackResolveMessage.isEmpty ? "Lane could not load the shared track." : session.trackResolveMessage
                        return
                    }
                    session.queue = [track]; session.currentIndex = 0
                    session.requestStream(for: track); showPlayer = true
                }
            }.disabled(loading)
        }
    }

    private func load() async {
        loading = true; message = nil
        defer { loading = false }
        do { item = try await session.resolveShare(share) }
        catch is CancellationError { }
        catch { message = error.localizedDescription }
    }
}
