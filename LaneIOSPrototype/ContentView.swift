import SwiftUI
import PhotosUI
import UIKit

private let lanePink = Color(red: 1.0, green: 130.0 / 255.0, blue: 132.0 / 255.0)
private let laneBackground = Color(red: 14.0 / 255.0, green: 14.0 / 255.0, blue: 14.0 / 255.0)
private let laneCard = Color.white.opacity(0.07)
private let laneBottomSurface = Color(red: 21.0 / 255.0, green: 21.0 / 255.0, blue: 21.0 / 255.0)

private struct LaneInteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        LaneInteractivePopController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let controller = uiViewController as? LaneInteractivePopController else { return }
        controller.activateLaneInteractivePop()
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: ()) {
        (uiViewController as? LaneInteractivePopController)?.restoreDelegate()
    }
}

private final class LaneInteractivePopController: UIViewController, UIGestureRecognizerDelegate {
    private weak var laneNavigationController: UINavigationController?
    private weak var previousDelegate: UIGestureRecognizerDelegate?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        activateLaneInteractivePop()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        activateLaneInteractivePop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        activateLaneInteractivePop()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        restoreDelegate()
    }

    func restoreDelegate() {
        if let gesture = laneNavigationController?.interactivePopGestureRecognizer,
           gesture.delegate === self {
            gesture.delegate = previousDelegate
        }
    }

    func activateLaneInteractivePop() {
        // SwiftUI updates its navigation/gesture delegate after the child is
        // mounted. Install on the following run-loop, not before that update.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.view.window != nil else { return }
            let nativeGesture = self.navigationController?.interactivePopGestureRecognizer
            if let navigation = self.navigationController, let nativeGesture,
               navigation.viewControllers.count > 1 {
                self.laneNavigationController = navigation
                if nativeGesture.delegate !== self {
                    self.previousDelegate = nativeGesture.delegate
                    nativeGesture.delegate = self
                }
                nativeGesture.isEnabled = true
            }
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigation = laneNavigationController else { return false }
        // Keep the native interactive transition, including cancellation, and
        // never start a pop at the root or during another push/pop transition.
        return navigation.viewControllers.count > 1 && navigation.transitionCoordinator == nil
    }

}

private struct LaneBackSwipeModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @State private var isVisible = false
    let onBack: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background(
                LaneInteractivePopGestureEnabler()
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            )
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onEnded { value in
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("--lane-ui-test") {
                            NotificationCenter.default.post(name: Notification.Name("LaneEdgeSwipeUIProbe"), object:
                                "visible=\(isVisible), start=\(value.startLocation), move=\(value.translation)")
                        }
                        #endif
                        guard isVisible, value.startLocation.x >= 0, value.startLocation.x < 24,
                              value.translation.width > 80,
                              value.translation.width > abs(value.translation.height) * 1.25,
                              !hasNativeInteractiveTransition() else { return }
                        if let onBack { onBack() } else { dismiss() }
                    }
            )
    }

    // If UIKit is already performing the interactive pop, leave that native
    // transition in charge; the fallback must not dismiss a second screen.
    private func hasNativeInteractiveTransition() -> Bool {
        func transitioning(_ controller: UIViewController) -> Bool {
            if controller.transitionCoordinator?.isInteractive == true { return true }
            if controller.children.contains(where: transitioning) { return true }
            return controller.presentedViewController.map(transitioning) ?? false
        }
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).compactMap(\.rootViewController).contains(where: transitioning)
    }
}

extension View {
    func laneIOSBackSwipe(action: (() -> Void)? = nil) -> some View {
        modifier(LaneBackSwipeModifier(onBack: action))
    }
}

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
    @State private var homeRootID = UUID()
    @State private var searchRootID = UUID()
    @State private var libraryRootID = UUID()
    @State private var showPlayer = false
    @State private var displayedWavePlaylist: LanePlaylist?

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                HomeScreen(showPlayer: $showPlayer)
                    .id(homeRootID)
                    .opacity(selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 0 && displayedWavePlaylist == nil)
                    .accessibilityHidden(selectedTab != 0 || displayedWavePlaylist != nil)

                SearchScreen(showPlayer: $showPlayer, isActive: selectedTab == 1)
                    .id(searchRootID)
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 1 && displayedWavePlaylist == nil)
                    .accessibilityHidden(selectedTab != 1 || displayedWavePlaylist != nil)

                LibraryScreen(showPlayer: $showPlayer, onSearch: { selectTab(1) })
                    .id(libraryRootID)
                    .opacity(selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 2 && displayedWavePlaylist == nil)
                    .accessibilityHidden(selectedTab != 2 || displayedWavePlaylist != nil)

                if let displayedWavePlaylist {
                    PlaylistDetailScreen(
                        playlist: displayedWavePlaylist,
                        showPlayer: $showPlayer,
                        onBack: closeWave
                    )
                    .background(laneBackground)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 30)
                            .onEnded { value in
                                guard value.startLocation.x < 32,
                                      value.translation.width > 100,
                                      abs(value.translation.width) > abs(value.translation.height) * 1.3 else { return }
                                closeWave()
                            }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, session.currentTrack == nil ? 48 : 108)

            VStack(spacing: 0) {
                if session.currentTrack != nil {
                    MiniPlayerView(showPlayer: $showPlayer)
                        .padding(.horizontal, 5)
                        .padding(.bottom, 2)
                }

                LaneBottomBar(selection: $selectedTab, onSelect: selectTab)
            }

            if session.waveIsLoading {
                APKWaveLoadingToast(coverURL: session.waveSourceCoverURL)
                    .padding(.horizontal, 24)
                    .padding(.bottom, session.currentTrack == nil ? 62 : 126)
                    .transition(.opacity)
            }
        }
        .background(laneBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showPlayer) {
            APKFullPlayerView()
                .environmentObject(session)
        }
        .onChange(of: session.wavePlaylist) { playlist in
            guard let playlist else {
                displayedWavePlaylist = nil
                return
            }
            showPlayer = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard session.wavePlaylist?.playlistId == playlist.playlistId else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    displayedWavePlaylist = playlist
                }
            }
        }
        .alert("Wave", isPresented: Binding(
            get: { session.waveError != nil && !showPlayer },
            set: { if !$0 { session.waveError = nil } }
        )) {
            Button("OK", role: .cancel) { session.waveError = nil }
        } message: {
            Text(session.waveError ?? "Could not create a wave.")
        }
        .task {
            if !session.isGuest && session.homeTracks.isEmpty {
                await session.refreshAfterLogin()
            }
        }
    }

    private func selectTab(_ index: Int) {
        closeWave()

        if selectedTab == index {
            // Match the APK and standard tab-bar behaviour: tapping the
            // already selected item returns that tab to its root screen.
            switch index {
            case 0: homeRootID = UUID()
            case 1: searchRootID = UUID()
            case 2: libraryRootID = UUID()
            default: break
            }
            return
        }

        withAnimation(.spring(response: 0.20, dampingFraction: 0.50)) {
            selectedTab = index
        }
    }

    private func closeWave() {
        withAnimation(.easeOut(duration: 0.2)) {
            displayedWavePlaylist = nil
            session.wavePlaylist = nil
        }
    }
}

private struct LaneBottomBar: View {
    @Binding var selection: Int
    let onSelect: (Int) -> Void

    private let selectedColor = Color.white
    private let unselectedColor = Color(red: 102.0 / 255.0, green: 102.0 / 255.0, blue: 102.0 / 255.0)

    var body: some View {
        HStack(spacing: 64) {
            bottomButton(
                index: 0,
                asset: selection == 0 ? "bottom_main" : "bottom_main_unselected",
                size: 23
            )
            bottomButton(index: 1, asset: "bottom_search", size: 23)
            bottomButton(index: 2, asset: "bottom_library", size: 28)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(laneBottomSurface)

                // Continue the control surface through the home-indicator area
                // while the buttons themselves remain inside the safe area.
                Rectangle()
                    .fill(laneBottomSurface)
                    .frame(height: 48)
                    .offset(y: 48)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.30), radius: 8, y: 2)
    }

    private func bottomButton(index: Int, asset: String, size: CGFloat) -> some View {
        let active = selection == index

        return Button {
            onSelect(index)
        } label: {
            APKTemplateIcon(
                name: asset,
                size: size,
                color: active ? selectedColor : unselectedColor
            )
            .scaleEffect(active ? 1.10 : 1.0)
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(index == 0 ? "Home" : index == 1 ? "Search" : "Library")
    }
}

// MARK: - Home

private struct HomeScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Binding var showPlayer: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HomeHeader()
                    .padding(.bottom, 24)
                    .background(laneBackground)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
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
                                    ServerPlaylistShelf(
                                        title: "Your playlists",
                                        playlists: session.serverPlaylists,
                                        showPlayer: $showPlayer
                                    )
                                }
                            }
                        }
                    }
                    .padding(.bottom, 22)
                }
                .refreshable {
                    if !session.isGuest {
                        await session.refreshAfterLogin()
                    }
                }
            }
            .background(laneBackground)
            .toolbar(.hidden, for: .navigationBar)
        }
        .laneIOSBackSwipe()
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

                        if session.unreadNotificationCount > 0 {
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
        .task(id: session.token) { await session.refreshUnreadNotifications() }
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
    let isActive: Bool

    @State private var query = ""
    @State private var selectedFilter: SearchFilter = .all
    @FocusState private var isSearchFocused: Bool

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
                            .focused($isSearchFocused)
                            .onSubmit { isSearchFocused = false }

                        if !query.isEmpty {
                            Button {
                                query = ""
                                selectedFilter = .all
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

                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
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
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchHistoryContent
                } else if session.searchIsLoading {
                    Spacer()
                    ProgressView()
                        .tint(lanePink)
                    Spacer()
                } else if hasFilteredSearchResults {
                    searchResults
                } else {
                    Spacer()
                    EmptyLaneView(
                        icon: "magnifyingglass",
                        title: "Nothing found",
                        subtitle: session.searchMessage.isEmpty
                            ? "Try another query or filter."
                            : session.searchMessage
                    )
                    Spacer()
                }
            }
            .background(laneBackground)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: query) {
                let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if clean.isEmpty {
                    session.search("")
                } else {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    session.search(clean)
                }
            }
            .task(id: isActive && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                if isActive && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await session.loadSearchHistory()
                }
            }
            .onChange(of: isActive) { active in
                if !active { isSearchFocused = false }
            }
        }
        .laneIOSBackSwipe()
    }

    @ViewBuilder
    private var searchHistoryContent: some View {
        if session.searchHistoryIsLoading && session.searchHistoryItems.isEmpty {
            Spacer()
            ProgressView().tint(lanePink)
            Spacer()
        } else if session.searchHistoryItems.isEmpty {
            Spacer()
            EmptyLaneView(
                icon: "magnifyingglass",
                title: session.searchHistoryMessage.isEmpty ? "What are we looking for today?" : "Recent searches unavailable",
                subtitle: session.searchHistoryMessage.isEmpty
                    ? "A track, artist, or album?"
                    : session.searchHistoryMessage
            )
            if !session.searchHistoryMessage.isEmpty {
                Button("Retry") {
                    Task { await session.loadSearchHistory() }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(lanePink)
            }
            Spacer()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text("Recent searches")
                        .font(.system(size: 17, weight: .bold))
                        .padding(.vertical, 12)

                    ForEach(Array(session.searchHistoryItems.prefix(20))) { item in
                        historyRow(item)
                    }

                    if !session.searchHistoryMessage.isEmpty {
                        Text(session.searchHistoryMessage)
                            .font(.caption)
                            .foregroundStyle(lanePink)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable {
                await session.loadSearchHistory()
            }
        }
    }

    private func historyRow(_ item: LaneSearchHistoryItem) -> some View {
        HStack(spacing: 0) {
            Group {
                if let track = item.track {
                    Button {
                        let context = "history:\(UUID().uuidString)"
                        let historyTracks = session.searchHistoryItems.compactMap { $0.track }.map {
                            TrackCandidate($0, refID: context)
                        }
                        let candidate = historyTracks.first { $0.trackID == track.songId }
                            ?? TrackCandidate(track, refID: context)
                        session.queue = historyTracks.isEmpty ? [candidate] : historyTracks
                        session.currentIndex = session.queue.firstIndex(of: candidate)
                        session.requestStream(for: candidate)
                        Task { await session.bumpSearchHistoryItem(item) }
                    } label: {
                        historyRowLabel(item)
                    }
                } else if let artist = item.artist {
                    NavigationLink {
                        APKArtistDetailScreen(seed: artist)
                            .task { await session.bumpSearchHistoryItem(item) }
                    } label: {
                        historyRowLabel(item)
                    }
                } else if let album = item.album {
                    NavigationLink {
                        APKAlbumDetailScreen(seed: album)
                            .task { await session.bumpSearchHistoryItem(item) }
                    } label: {
                        historyRowLabel(item)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                Task { await session.deleteSearchHistoryItem(item) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, height: 58)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item.title) from recent searches")
        }
        .frame(height: 64)
    }

    private func historyRowLabel(_ item: LaneSearchHistoryItem) -> some View {
        HStack(spacing: 14) {
            APKRemoteImage(url: item.imageURL, circle: item.artist != nil)
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    APKPlatformIcon(platform: item.platform, size: 10)
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 58)
        .contentShape(Rectangle())
    }

    private var hasSearchResults: Bool {
        !session.searchResultItems.isEmpty ||
        !session.searchTracks.isEmpty ||
        !session.searchArtists.isEmpty ||
        !session.searchAlbums.isEmpty ||
        !session.searchPlaylists.isEmpty
    }

    private var hasFilteredSearchResults: Bool {
        switch selectedFilter {
        case .all:
            return hasSearchResults
        case .spotify:
            return session.searchResultItems.contains { matchesPlatform($0, "spotify") }
        case .soundcloud:
            return session.searchResultItems.contains { matchesPlatform($0, "soundcloud") }
        case .tracks:
            return !session.searchTracks.isEmpty
        case .playlists:
            return !session.searchPlaylists.isEmpty
        case .albums:
            return !session.searchAlbums.isEmpty
        }
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
                                }
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
                            }
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
    case artists = "Artists"
    case albums = "Albums"

    var id: String { rawValue }
}

private enum LibraryEntry: Identifiable {
    case playlist(LanePlaylist)
    case local(LocalPlaylist)
    case artist(LaneArtist)
    case album(LaneAlbum)

    var id: String {
        switch self {
        case .playlist(let value): return "playlist:\(value.playlistId ?? value.playlistName ?? "unknown")"
        case .local(let value): return "local:\(value.id.uuidString)"
        case .artist(let value): return "artist:\(value.id ?? value.name ?? "unknown")"
        case .album(let value): return "album:\(value.id ?? value.name ?? "unknown")"
        }
    }

    func matches(_ filter: LibraryFilter) -> Bool {
        switch (self, filter) {
        case (_, .all), (.playlist, .playlists), (.local, .playlists),
             (.artist, .artists), (.album, .albums): return true
        default: return false
        }
    }
}

private struct LibraryScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Binding var showPlayer: Bool
    let onSearch: () -> Void

    @State private var filter: LibraryFilter = .all
    @State private var showCreatePlaylist = false
    @State private var pinnedLibraryIDs = Set(
        UserDefaults.standard.stringArray(forKey: "lane.libraryPinnedIDs") ?? []
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    LibraryHeader(showCreatePlaylist: $showCreatePlaylist, onSearch: onSearch)
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
                            ImportTracksScreen()
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
        .laneIOSBackSwipe()
    }

    private var libraryEntries: [LibraryEntry] {
        let entries: [LibraryEntry] =
            session.serverPlaylists
                .filter { $0.playlistId != "lane_likes" }
                .map(LibraryEntry.playlist) +
            session.localPlaylists.map(LibraryEntry.local) +
            session.serverArtists.map(LibraryEntry.artist) +
            session.serverAlbums.map(LibraryEntry.album)
        return entries.filter { pinnedLibraryIDs.contains($0.id) } +
            entries.filter { !pinnedLibraryIDs.contains($0.id) }
    }

    @ViewBuilder
    private var libraryContents: some View {
        if filter == .all || filter == .playlists {
            NavigationLink {
                FavoriteTracksScreen(showPlayer: $showPlayer)
            } label: {
                APKFavoritePlaylistCard(trackCount: session.favorites.count)
            }
            .buttonStyle(.plain)
        }

        ForEach(libraryEntries.filter { $0.matches(filter) }) { entry in
            libraryEntryRow(entry)
                .contextMenu {
                    Button(
                        pinnedLibraryIDs.contains(entry.id) ? "Unpin" : "Pin to top",
                        systemImage: pinnedLibraryIDs.contains(entry.id) ? "pin.slash" : "pin"
                    ) {
                        togglePinned(entry.id)
                    }
                }
        }

        if filter != .all && filter != .playlists &&
            libraryEntries.allSatisfy({ !$0.matches(filter) }) {
            EmptyLaneView(
                icon: "square.stack",
                title: "Your Library",
                subtitle: "Saved music and playlists will appear here."
            )
            .padding(.top, 30)
        }
    }

    @ViewBuilder
    private func libraryEntryRow(_ entry: LibraryEntry) -> some View {
        switch entry {
        case .playlist(let playlist):
            NavigationLink {
                PlaylistDetailScreen(playlist: playlist, showPlayer: $showPlayer)
            } label: {
                PlaylistRow(playlist: playlist)
            }
            .buttonStyle(.plain)

        case .local(let playlist):
            NavigationLink {
                LocalPlaylistDetailScreen(playlist: playlist, showPlayer: $showPlayer)
            } label: {
                LocalPlaylistRow(playlist: playlist)
            }
            .buttonStyle(.plain)

        case .artist(let artist):
            ArtistRow(artist: artist)

        case .album(let album):
            AlbumRow(album: album)
        }
    }

    private func togglePinned(_ id: String) {
        if pinnedLibraryIDs.contains(id) {
            pinnedLibraryIDs.remove(id)
        } else {
            pinnedLibraryIDs.insert(id)
        }
        UserDefaults.standard.set(Array(pinnedLibraryIDs), forKey: "lane.libraryPinnedIDs")
    }
}
private struct LibraryHeader: View {
    @EnvironmentObject private var session: LaneSession
    @Binding var showCreatePlaylist: Bool
    let onSearch: () -> Void

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

            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

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

    @State private var cardColor = Color(red: 0.12, green: 0.12, blue: 0.12)
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        if let track = session.currentTrack {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(cardColor)

                HStack(spacing: 0) {
                    Button {
                        showPlayer = true
                    } label: {
                        HStack(spacing: 8) {
                            ArtworkView(url: track.coverURL, size: 46, radius: 5)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.92)

                                Text(track.subtitle)
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(Color.white.opacity(0.70))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 58)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("player.mini.open")
                    .padding(.leading, 10)

                    Button {
                        session.togglePlayback()
                    } label: {
                        ZStack {
                            if session.isBuffering {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 28, weight: .regular))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 50, height: 58)
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 58)

                GeometryReader { proxy in
                    let fraction: CGFloat = {
                        guard session.playbackDuration > 0 else { return 0 }
                        return CGFloat(min(max(session.playbackPosition / session.playbackDuration, 0), 1))
                    }()

                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.30))

                        Rectangle()
                            .fill(Color.white)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: 1)
                .clipShape(Capsule())
            }
            .frame(height: 58)
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            }
            .offset(x: dragOffset)
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { value in
                        dragOffset = value.translation.width * 0.30
                    }
                    .onEnded { value in
                        let threshold: CGFloat = 70

                        if value.translation.width <= -threshold {
                            session.next()
                        } else if value.translation.width >= threshold {
                            session.previous()
                        }

                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            dragOffset = 0
                        }
                    }
            )
            .task(id: track.coverURL) {
                await updateMiniPlayerColor(from: track.coverURL)
            }
            .animation(.easeInOut(duration: 0.24), value: cardColor)
        }
    }

    @MainActor
    private func updateMiniPlayerColor(from rawURL: String?) async {
        let fallback = UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)

        guard let url = laneRoutedMediaURL(rawURL) else {
            cardColor = Color(uiColor: fallback)
            return
        }

        do {
            let data = try await AndroidNetworkTransport.imageData(from: url)
            guard let image = UIImage(data: data),
                  let sampled = Self.averageColor(of: image) else {
                cardColor = Color(uiColor: fallback)
                return
            }

            // Lane Android blends its selected Palette swatch into the current
            // Material surface color at 20%.
            let blended = Self.blend(base: fallback, accent: sampled, fraction: 0.20)
            cardColor = Color(uiColor: blended)
        } catch {
            cardColor = Color(uiColor: fallback)
        }
    }

    private static func averageColor(of image: UIImage) -> UIColor? {
        guard let cgImage = image.cgImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        return UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
    }

    private static func blend(base: UIColor, accent: UIColor, fraction: CGFloat) -> UIColor {
        var br: CGFloat = 0
        var bg: CGFloat = 0
        var bb: CGFloat = 0
        var ba: CGFloat = 0
        var ar: CGFloat = 0
        var ag: CGFloat = 0
        var ab: CGFloat = 0
        var aa: CGFloat = 0

        base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        accent.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)

        let t = min(max(fraction, 0), 1)
        return UIColor(
            red: br + (ar - br) * t,
            green: bg + (ag - bg) * t,
            blue: bb + (ab - bb) * t,
            alpha: ba + (aa - ba) * t
        )
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
                                session.startWave(from: track)
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
    let playbackQueue: [TrackCandidate]

    var body: some View {
        HStack(spacing: 12) {
            Button {
                session.startPlayback(track, in: playbackQueue)
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
            .accessibilityIdentifier("track.row.\(track.trackID ?? track.id)")

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
            session.startPlayback(track, in: playbackQueue)
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

                let count = playlist.effectiveTrackCount
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

private struct LocalPlaylistRow: View {
    @EnvironmentObject private var session: LaneSession
    let playlist: LocalPlaylist

    private var tracks: [TrackCandidate] {
        session.tracks(in: playlist)
    }

    var body: some View {
        HStack(spacing: 16) {
            if let first = tracks.first {
                ArtworkView(url: first.coverURL, size: 64, radius: 5)
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "iphone")
                        .foregroundStyle(lanePink)
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("\(tracks.count) tracks · On this iPhone")
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
    @Environment(\.dismiss) private var dismiss
    let playlist: LanePlaylist
    @Binding var showPlayer: Bool
    var onBack: (() -> Void)? = nil

    @State private var tracks: [TrackCandidate] = []
    @State private var loading = true
    @State private var confirmDelete = false
    @State private var confirmClear = false
    @State private var clearCompleted = 0
    @State private var clearTotal = 0
    @State private var didClear = false
    @State private var actionTrack: TrackCandidate?
    @State private var showPlaylistActions = false
    @State private var showEditPlaylist = false
    @State private var showReorderPlaylist = false
    @State private var showCollaborators = false
    @State private var showInvitePlaylist = false
    @State private var shareItem: LaneShareURL?
    @State private var actionError: String?
    @State private var editedName: String?
    @State private var editedDescription: String?
    @State private var editedVisibility: String?

    private var isOwner: Bool {
        if playlist.playlistId == "lane_likes" { return false }
        guard let creator = playlist.creatorLid,
              let accountID = session.account?.laneId else { return false }
        return creator == accountID
    }

    private var isSaved: Bool {
        session.serverPlaylists.contains { $0.playlistId == playlist.playlistId }
    }

    private var canClear: Bool { isOwner || (playlist.playlistId == "lane_likes" && !session.isGuest) }
    private var isClearing: Bool { session.clearingPlaylistIDs.contains(playlist.playlistId ?? "") }

    private var visibleName: String {
        if playlist.playlistId == "lane_likes" { return "Liked Songs" }
        return editedName ?? playlist.playlistName ?? "Playlist"
    }

    private var visibleDescription: String? {
        editedDescription ?? playlist.playlistDescription
    }

    private var visibleVisibility: String {
        editedVisibility ?? playlist.visibility ?? "public"
    }

    private var downloadState: LanePlaylistDownloadState? {
        guard let id = playlist.playlistId else { return nil }
        return session.playlistDownloads[id]
    }

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
                    Text(visibleName)
                        .font(.system(size: 25, weight: .bold))
                        .lineLimit(2)

                    if let description = visibleDescription, !description.isEmpty {
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

                        let count = didClear ? tracks.count : max(tracks.count, playlist.effectiveTrackCount)
                        Text(count == 1 ? "1 track" : "\(count) tracks")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.52))
                    }

                    HStack(spacing: 16) {
                        Button {
                            if let id = playlist.playlistId {
                                if downloadState?.isRunning == true {
                                    session.cancelPlaylistDownload(id)
                                } else {
                                    session.downloadPlaylistTracks(tracks, playlistID: id)
                                }
                            }
                        } label: {
                            Group {
                                if downloadState?.isRunning == true {
                                    ProgressView().tint(lanePink)
                                } else {
                                    APKTemplateIcon(
                                        name: "download_playlist",
                                        size: 28,
                                        color: Color.white.opacity(0.82)
                                    )
                                }
                            }
                            .frame(width: 34, height: 40)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(downloadState?.isRunning == true
                            ? "Stop playlist download" : "Download playlist")
                        .disabled(tracks.isEmpty)

                        Button {
                            showPlaylistActions = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .rotationEffect(.degrees(90))
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.82))
                                .frame(width: 34, height: 40)
                        }
                        .accessibilityIdentifier("playlist.actions")
                        .disabled(isClearing)

                        Spacer()

                        Button {
                            guard !tracks.isEmpty else { return }
                            let list = tracks.shuffled()
                            session.queue = list
                            session.currentIndex = 0
                            session.requestStream(for: list[0])
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

                    if let downloadState {
                        Text(downloadState.isRunning
                            ? "Saving \(downloadState.completed)/\(downloadState.total) tracks…"
                            : "Saved \(downloadState.completed - downloadState.failed)/\(downloadState.total) tracks" +
                                (downloadState.failed == 0 ? "" : " · \(downloadState.failed) failed"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(downloadState.failed == 0 ? Color.white.opacity(0.55) : lanePink)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)

                if let actionError {
                    Text(actionError)
                        .font(.system(size: 13))
                        .foregroundStyle(lanePink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                if isClearing {
                    ProgressView(session.playlistClearStages[playlist.playlistId ?? ""] ?? "Removing \(clearCompleted)/\(clearTotal) tracks…")
                    Button("Остановить удаление") { session.stopClearingPlaylist(playlist.playlistId ?? "") }
                        .accessibilityIdentifier("playlist.clear.stop")
                        .tint(lanePink).padding()
                }

                if loading {
                    HStack {
                        Spacer()
                        ProgressView().tint(lanePink)
                        Spacer()
                    }
                    .padding(.vertical, 32)
                } else if tracks.isEmpty {
                    if let message = session.playlistLoadMessages[playlist.playlistId ?? ""] {
                        VStack(spacing: 12) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 31))
                                .foregroundStyle(.secondary)
                            Text(message)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Try again") { reloadTracks() }
                                .buttonStyle(.bordered)
                                .tint(lanePink)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .padding(.horizontal, 20)
                    } else {
                        APKPlaylistEmptyState()
                            .padding(.top, 18)
                    }
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            HStack(spacing: 0) {
                                Button {
                                    session.queue = tracks
                                    session.currentIndex = index
                                    session.requestStream(for: track)
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
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    actionTrack = track
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(Color.white.opacity(0.62))
                                        .frame(width: 40, height: 58)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.leading, 16)
                            .padding(.trailing, 10)
                            .frame(minHeight: 64)

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
        .toolbar(.hidden, for: .navigationBar)
        .laneIOSBackSwipe()
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 0) {
                APKImportBackButton {
                    if let onBack { onBack() } else { dismiss() }
                }

                Text(visibleName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                Color.clear
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 8)
            .frame(height: 52)
            .background(laneBackground.opacity(0.96))
        }
        .onAppear { reloadTracks() }
        .alert("Удалить все треки?", isPresented: $confirmClear) {
            Button("Удалить все треки", role: .destructive) {
                Task {
                    actionError = nil
                    do {
                        try await session.clearPlaylistTracks(playlist) { completed, total in
                            clearCompleted = completed; clearTotal = total
                        }
                        tracks = []; didClear = true
                    } catch {
                        actionError = error.localizedDescription
                        reloadTracks()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Все треки будут удалены из «\(visibleName)» на сервере Lane. Сам плейлист и скачанные файлы останутся. Это действие нельзя отменить.")
        }
        .alert(isOwner ? "Delete playlist?" : "Remove from Library?", isPresented: $confirmDelete) {
            Button(isOwner ? "Delete" : "Remove", role: .destructive) {
                Task {
                    do {
                        try await session.deleteServerPlaylist(playlist)
                        if let onBack { onBack() } else { dismiss() }
                    } catch {
                        actionError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(isOwner
                ? "This action cannot be undone."
                : "The playlist will be removed from your Library.")
        }
        .sheet(item: $actionTrack) { track in
            APKTrackActionsSheet(track: track)
        }
        .sheet(isPresented: $showPlaylistActions) {
            APKPlaylistActionsSheet(
                playlist: playlist,
                creatorName: isOwner
                    ? (session.account?.displayedName ?? session.account?.userName ?? "Lane")
                    : (playlist.platform ?? "Lane"),
                isOwner: isOwner,
                isSaved: isSaved,
                canClear: canClear && !isClearing,
                visibility: visibleVisibility,
                onEdit: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showEditPlaylist = true
                    }
                },
                onReorder: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showReorderPlaylist = true
                    }
                },
                onCollaborators: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showCollaborators = true
                    }
                },
                onInvite: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showInvitePlaylist = true
                    }
                },
                onShare: { sharePlaylist() },
                onToggleVisibility: { togglePlaylistVisibility() },
                onSave: { savePlaylist() },
                onClear: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { confirmClear = true }
                },
                onDelete: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        confirmDelete = true
                    }
                }
            )
        }
        .sheet(isPresented: $showEditPlaylist) {
            APKEditPlaylistSheet(
                name: visibleName,
                description: visibleDescription ?? "",
                onSave: { name, description in
                    try await session.editServerPlaylist(
                        playlist, name: name, description: description
                    )
                    editedName = name
                    editedDescription = description
                }
            )
        }
        .sheet(isPresented: $showReorderPlaylist) {
            APKPlaylistOrderSheet(
                playlist: playlist,
                initialTracks: tracks,
                onChange: { updated in
                    tracks = updated
                }
            )
            .environmentObject(session)
        }
        .sheet(isPresented: $showCollaborators) {
            APKPlaylistCollaboratorsSheet(playlist: playlist)
                .environmentObject(session)
        }
        .sheet(isPresented: $showInvitePlaylist) {
            APKInvitePlaylistUsersSheet(playlist: playlist)
                .environmentObject(session)
        }
        .sheet(item: $shareItem) { item in
            LaneShareActivitySheet(url: item.url)
        }
    }

    private func reloadTracks() {
        loading = tracks.isEmpty
        session.loadPlaylistTracks(playlist) { loaded in
            tracks = loaded
            loading = false
        }
    }

    private func sharePlaylist() {
        Task {
            do {
                let url = try await session.sharePlaylist(playlist)
                shareItem = LaneShareURL(url: url)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func togglePlaylistVisibility() {
        let next = visibleVisibility.lowercased() == "public" ? "private" : "public"
        Task {
            do {
                try await session.setPlaylistVisibility(playlist, visibility: next)
                editedVisibility = next
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func savePlaylist() {
        Task {
            do {
                try await session.savePlaylistToLibrary(playlist)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
}

private struct APKEditPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String
    @State private var saving = false
    @State private var errorMessage: String?
    let onSave: (String, String) async throws -> Void

    init(name: String, description: String, onSave: @escaping (String, String) async throws -> Void) {
        _name = State(initialValue: name)
        _description = State(initialValue: description)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Playlist name")
                    .font(.system(size: 14, weight: .semibold))
                TextField("Name", text: $name)
                    .padding(14)
                    .background(laneCard, in: RoundedRectangle(cornerRadius: 12))

                Text("Description")
                    .font(.system(size: 14, weight: .semibold))
                TextEditor(text: $description)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(height: 130)
                    .background(laneCard, in: RoundedRectangle(cornerRadius: 12))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(lanePink)
                }

                Button {
                    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanName.isEmpty else { return }
                    saving = true
                    Task {
                        defer { saving = false }
                        do {
                            try await onSave(cleanName, description)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if saving { ProgressView().tint(.black) }
                        Text("Save changes")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(.black)
                    .background(lanePink, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }
            .padding(20)
            .background(laneBackground.ignoresSafeArea())
            .navigationTitle("Edit playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }
}

private struct APKPlaylistOrderSheet: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss

    let playlist: LanePlaylist
    let onChange: ([TrackCandidate]) -> Void

    @State private var tracks: [TrackCandidate]
    @State private var editMode: EditMode = .active
    @State private var saving = false
    @State private var removingIDs: Set<String> = []
    @State private var errorMessage: String?

    init(
        playlist: LanePlaylist,
        initialTracks: [TrackCandidate],
        onChange: @escaping ([TrackCandidate]) -> Void
    ) {
        self.playlist = playlist
        self.onChange = onChange
        _tracks = State(initialValue: initialTracks)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        ArtworkView(url: track.coverURL, size: 44, radius: 5)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            Text(track.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if let id = track.trackID, removingIDs.contains(id) {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            remove(track)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                .onMove { source, destination in
                    tracks.move(fromOffsets: source, toOffset: destination)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(lanePink)
                }
            }
            .environment(\.editMode, $editMode)
            .scrollContentBackground(.hidden)
            .background(laneBackground)
            .navigationTitle("Track order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        save()
                    }
                    .disabled(saving || !removingIDs.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    private func save() {
        guard !saving else { return }
        saving = true
        errorMessage = nil

        Task {
            defer { saving = false }
            do {
                try await session.reorderPlaylistTracks(tracks, in: playlist)
                onChange(tracks)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func remove(_ track: TrackCandidate) {
        guard let id = track.trackID, !removingIDs.contains(id) else { return }
        removingIDs.insert(id)
        errorMessage = nil

        Task {
            defer { removingIDs.remove(id) }
            do {
                try await session.removeTrack(track, from: playlist)
                tracks.removeAll { $0.trackID == id }
                onChange(tracks)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct APKPlaylistCollaboratorsSheet: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss

    let playlist: LanePlaylist

    @State private var collaborators: [UserInfoDTO] = []
    @State private var loading = true
    @State private var showInvite = false
    @State private var removingIDs: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Button {
                    showInvite = true
                } label: {
                    Label("Add member", systemImage: "person.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 52)
                        .padding(.horizontal, 18)
                        .background(laneCard, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(16)

                if loading {
                    Spacer()
                    ProgressView().tint(lanePink)
                    Spacer()
                } else if collaborators.isEmpty {
                    Spacer()
                    EmptyLaneView(
                        icon: "person.2",
                        title: "No collaborators",
                        subtitle: "Invite people to edit this playlist together."
                    )
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(collaborators.enumerated()), id: \.offset) { _, user in
                                HStack(spacing: 12) {
                                    AvatarView(url: user.avatarUrl, size: 46)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(user.displayedName ?? user.userName ?? "Lane user")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.white)
                                        if let name = user.userName, !name.isEmpty {
                                            Text("@\(name)")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    if let id = user.laneId, removingIDs.contains(id) {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(.white)
                                            .frame(width: 42)
                                    } else {
                                        Button(role: .destructive) {
                                            remove(user)
                                        } label: {
                                            Image(systemName: "person.badge.minus")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundStyle(.red)
                                                .frame(width: 42, height: 42)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 18)
                                .frame(minHeight: 64)

                                Divider()
                                    .padding(.leading, 76)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(lanePink)
                        .multilineTextAlignment(.center)
                        .padding(16)
                }
            }
            .background(laneBackground.ignoresSafeArea())
            .navigationTitle("Collaborators")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await reload() }
            .sheet(isPresented: $showInvite, onDismiss: {
                Task { await reload() }
            }) {
                APKInvitePlaylistUsersSheet(playlist: playlist)
                    .environmentObject(session)
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    @MainActor
    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            collaborators = try await session.playlistCollaborators(for: playlist)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ user: UserInfoDTO) {
        guard let id = user.laneId, !removingIDs.contains(id) else { return }
        removingIDs.insert(id)
        errorMessage = nil

        Task {
            defer { removingIDs.remove(id) }
            do {
                try await session.removePlaylistCollaborator(user, from: playlist)
                collaborators.removeAll { $0.laneId == id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct APKInvitePlaylistUsersSheet: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss
    let playlist: LanePlaylist

    @State private var query = ""
    @State private var results: [UserInfoDTO] = []
    @State private var selectedIDs: Set<String> = []
    @State private var searching = false
    @State private var submitting = false
    @State private var errorMessage: String?
    @State private var shareItem: LaneShareURL?

    private var people: [UserInfoDTO] {
        let source = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? session.friends : results
        let excluded = Set(playlist.collaboratorIds ?? [])
        return source.filter { user in
            guard let id = user.laneId else { return false }
            return id != session.account?.laneId && !excluded.contains(id)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search people", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(laneCard, in: RoundedRectangle(cornerRadius: 14))
                .padding(16)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        Button {
                            Task {
                                do {
                                    let url = try await session.sharePlaylist(playlist)
                                    shareItem = LaneShareURL(url: url)
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        } label: {
                            Label("Invite by link", systemImage: "link")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 52)
                        }
                        .buttonStyle(.plain)

                        if searching {
                            ProgressView().tint(lanePink).padding(.vertical, 20)
                        }

                        ForEach(Array(people.enumerated()), id: \.offset) { _, user in
                            if let id = user.laneId {
                                Button {
                                    if selectedIDs.contains(id) {
                                        selectedIDs.remove(id)
                                    } else {
                                        selectedIDs.insert(id)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        AvatarView(url: user.avatarUrl, size: 46)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(user.displayedName ?? user.userName ?? "Lane user")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(.white)
                                            if let name = user.userName {
                                                Text("@\(name)")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: selectedIDs.contains(id)
                                            ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 23))
                                            .foregroundStyle(selectedIDs.contains(id)
                                                ? lanePink : Color.white.opacity(0.45))
                                    }
                                    .frame(height: 60)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(lanePink)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }

                Button {
                    guard !selectedIDs.isEmpty else { return }
                    submitting = true
                    Task {
                        defer { submitting = false }
                        do {
                            try await session.invitePlaylistUsers(Array(selectedIDs), to: playlist)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if submitting { ProgressView().tint(.black) }
                        Text("Invite \(selectedIDs.count)")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(.black)
                    .background(lanePink, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(selectedIDs.isEmpty || submitting)
                .padding(16)
            }
            .background(laneBackground.ignoresSafeArea())
            .navigationTitle("Add member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: query) {
                let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else {
                    results = []
                    searching = false
                    return
                }
                searching = true
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                do {
                    let found = try await session.searchPlaylistInviteUsers(clean)
                    guard !Task.isCancelled else { return }
                    results = found
                    errorMessage = nil
                } catch {
                    guard !Task.isCancelled else { return }
                    results = []
                    errorMessage = error.localizedDescription
                }
                searching = false
            }
            .sheet(item: $shareItem) { item in
                LaneShareActivitySheet(url: item.url)
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }
}

struct LaneShareURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct LaneShareActivitySheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
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
                    Button("Recommendations") { session.startWave(from: track) }
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
    @State private var showPremiumQualityNotice = false
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
                    LaneResilientImage(url: profileHeader) {
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

                            if let badge = session.publicProfile?.equippedBadge {
                                NavigationLink { LaneBadgeSelectionScreen() } label: {
                                    LaneBadgeImage(badge: badge.definition, size: 24)
                                }.buttonStyle(.plain)
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
                            NavigationLink {
                                LanePeopleListScreen(laneID: session.account?.laneId ?? session.publicProfile?.laneId ?? "", following: false)
                            } label: { profileStat(value: session.publicProfile?.followersCount ?? 0, title: "Followers") }
                            .buttonStyle(.plain)

                            Rectangle()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 1, height: 28)

                            NavigationLink {
                                LanePeopleListScreen(laneID: session.account?.laneId ?? session.publicProfile?.laneId ?? "", following: true)
                            } label: { profileStat(value: session.publicProfile?.followingCount ?? 0, title: "Following") }
                            .buttonStyle(.plain)
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

                        NavigationLink { LaneBadgeSelectionScreen() } label: {
                            Label("Your badges", systemImage: "rosette").font(.headline)
                        }.buttonStyle(.plain).accessibilityIdentifier("profile.badges")
                        if let badges = session.publicProfile?.badges, !badges.isEmpty {
                            LaneBadgesSection(badges: badges, own: true).padding(.horizontal, 16)
                        }

                        if let statusTrack = session.publicProfile?.statusTrack {
                            let track = TrackCandidate(statusTrack)
                            Button {
                                session.requestStream(for: track)
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
                            NavigationLink {
                                PrivacySettingsScreen()
                            } label: {
                                profileMenuRow(icon: "lock.shield", title: "Privacy", subtitle: "Playlists, followers and following")
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.leading, 58)

                            NavigationLink {
                                DownloadsScreen(showPlayer: $showPlayer)
                            } label: {
                                profileMenuRow(icon: "arrow.down.circle", title: "Downloads", subtitle: "Music saved on this iPhone")
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.leading, 58)

                            profileMenuRow(
                                icon: "waveform",
                                title: "Audio quality",
                                subtitle: AudioQualityChoice(rawValue: session.streamQuality)?.detail ?? session.streamQuality
                            )

                            Divider().padding(.leading, 58)

                            NavigationLink {
                                ImportTracksScreen()
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

                        HStack(spacing: 0) {
                            ForEach(AudioQualityChoice.allCases) { quality in
                                let locked = quality != .basic && !session.hasPremiumAccess
                                Button {
                                    if locked || !session.selectStreamQuality(quality) {
                                        showPremiumQualityNotice = true
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        if locked { Image(systemName: "lock.fill").font(.system(size: 10)) }
                                        Text("\(quality.title) · \(quality.detail)")
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                    .foregroundStyle(locked ? Color.white.opacity(0.45) : .white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 35)
                                    .background(
                                        session.streamQuality == quality.rawValue
                                            ? Color.white.opacity(0.2) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 7)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(3)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                        .padding(.horizontal, 16)

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
        .alert("Lane Premium required", isPresented: $showPremiumQualityNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("High and Ultra quality require an active Lane subscription. Basic quality remains available.")
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

struct TelegramLoginScreen: View {
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

struct EditProfileSheet: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var username = ""
    @State private var statusText = ""
    @State private var avatarURL = ""
    @State private var headerURL = ""
    @State private var avatarSelection: PhotosPickerItem?
    @State private var headerSelection: PhotosPickerItem?
    @State private var saving = false
    @State private var uploading = false
    @State private var errorMessage: String?
    @State private var loadedInitialProfile = false
    @FocusState private var profileFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile images") {
                    PhotosPicker(selection: $avatarSelection, matching: .images) {
                        HStack {
                            AvatarView(url: avatarURL, size: 60)
                            Text("Change avatar")
                        }
                    }
                    PhotosPicker(selection: $headerSelection, matching: .images) {
                        VStack(alignment: .leading) {
                            APKRemoteImage(url: headerURL).frame(height: 110)
                            Text("Change profile header")
                        }
                    }
                    if uploading { ProgressView("Uploading image…") }
                }
                .disabled(saving || uploading)
                Section("Profile") {
                    TextField("Name", text: $name).accessibilityIdentifier("profile.name").focused($profileFieldFocused)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .focused($profileFieldFocused)
                    TextField("About me", text: $statusText, axis: .vertical)
                        .focused($profileFieldFocused)
                }
                .disabled(saving || uploading)
                Section("Current badge") {
                    NavigationLink { LaneBadgeSelectionScreen() } label: {
                        HStack {
                            if let badge = session.publicProfile?.equippedBadge {
                                LaneBadgeImage(badge: badge.definition)
                                Text(badge.definition.name)
                            } else { Text("Not selected") }
                        }
                    }.accessibilityIdentifier("profile.badges")
                }.disabled(saving || uploading)
                if let errorMessage { Text(errorMessage).foregroundStyle(lanePink) }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Profile")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { profileFieldFocused = false }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(saving || uploading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        errorMessage = nil
                        Task {
                            defer { saving = false }
                            do {
                                try await session.saveProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                                              username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                                                              statusText: statusText, avatarURL: avatarURL, headerURL: headerURL)
                                dismiss()
                            } catch { errorMessage = error.localizedDescription }
                        }
                    }
                    .disabled(saving || uploading || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("profile.save")
                }
            }
            .onAppear {
                guard !loadedInitialProfile else { return }
                loadedInitialProfile = true
                name = session.account?.displayedName ?? ""
                username = session.account?.userName ?? ""
                statusText = session.account?.statusText ?? ""
                avatarURL = session.account?.avatarUrl ?? ""
                headerURL = session.account?.headerUrl ?? ""
            }
            .onChange(of: avatarSelection) { selection in Task { await upload(selection, target: "avatar") } }
            .onChange(of: headerSelection) { selection in Task { await upload(selection, target: "header") } }
        }
        .interactiveDismissDisabled(saving || uploading)
    }

    private func upload(_ selection: PhotosPickerItem?, target: String) async {
        guard let selection, !uploading else { return }
        uploading = true
        errorMessage = nil
        defer { uploading = false }
        do {
            guard let original = try await selection.loadTransferable(type: Data.self) else { throw LaneAPIError.emptyResponse }
            let isGIF = original.starts(with: Data("GIF8".utf8))
            let data: Data
            if isGIF { data = original }
            else {
                guard let image = UIImage(data: original) else { throw LaneAPIError.decoding("Could not open this image.") }
                let maximum: CGFloat = target == "avatar" ? 800 : 1800
                let scale = min(1, maximum / max(image.size.width, image.size.height))
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                guard let jpeg = rendered.jpegData(compressionQuality: 0.82) else { throw LaneAPIError.emptyResponse }
                data = jpeg
            }
            let url = try await session.uploadProfileImage(data, target: target, isGIF: isGIF)
            if target == "avatar" { avatarURL = url } else { headerURL = url }
        } catch { errorMessage = error.localizedDescription }
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
        .toolbar(.visible, for: .navigationBar)
        .laneIOSBackSwipe()
        .onAppear {
            session.refreshFriends()
        }
    }
}

private struct UserRow: View {
    @EnvironmentObject private var session: LaneSession
    let user: UserInfoDTO
    @State private var saving = false
    @State private var error: String?
    @State private var confirmedUser: UserInfoDTO?

    private var displayedUser: UserInfoDTO { confirmedUser ?? user }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if let id = user.laneId, !id.isEmpty {
                    NavigationLink { LaneUserProfileScreen(laneID: id) } label: { identity }
                        .buttonStyle(.plain)
                } else { identity }
                if let laneId = user.laneId, laneId != session.account?.laneId {
                    Button(saving ? "Saving…" : (displayedUser.isFollowing == true ? "Following" : "Follow")) {
                        saving = true; error = nil
                        Task {
                            defer { saving = false }
                            do { confirmedUser = try await session.setFollowingConfirmed(displayedUser, follow: displayedUser.isFollowing != true) }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                    .buttonStyle(.bordered).controlSize(.small).disabled(saving || session.isGuest).id(laneId)
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(lanePink) }
        }
    }

    private var identity: some View {
        HStack(spacing: 12) {
            AvatarView(url: user.avatarUrl, size: 46)
            VStack(alignment: .leading) {
                Text(user.displayedName ?? user.userName ?? "Lane user").font(.subheadline.weight(.semibold))
                if let username = user.userName, !username.isEmpty {
                    Text("@\(username)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

struct LaneUserProfileScreen: View {
    @EnvironmentObject private var session: LaneSession
    let laneID: String
    @State private var user: UserInfoDTO?
    @State private var loading = false
    @State private var saving = false
    @State private var error: String?
    @State private var showPlayer = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let user {
                    GeometryReader { geometry in
                        ArtworkView(url: user.headerUrl, size: geometry.size.width, radius: 0)
                            .frame(width: geometry.size.width, height: 170).clipped()
                    }.frame(height: 170)
                    AvatarView(url: user.avatarUrl, size: 90).padding(.top, -58)
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Text(user.displayedName ?? user.userName ?? "Lane user").font(.title2.bold())
                                .accessibilityIdentifier("user.name")
                            if let badge = user.equippedBadge { LaneBadgeImage(badge: badge.definition, size: 24) }
                        }
                        if let name = user.userName, !name.isEmpty { Text("@\(name)").foregroundStyle(.secondary) }
                        if let status = user.statusText, !status.isEmpty { Text(status).font(.callout).multilineTextAlignment(.center) }
                    }.padding(.horizontal, 20)
                    HStack(spacing: 40) {
                        if (laneID == session.account?.laneId || user.privacySettings?.showFollowers != false), let count = user.followersCount {
                            NavigationLink { LanePeopleListScreen(laneID: laneID, following: false) } label: {
                                VStack { Text("\(count)").font(.headline); Text("Followers").font(.caption).foregroundStyle(.secondary) }
                            }.accessibilityIdentifier("user.followers")
                        }
                        if (laneID == session.account?.laneId || user.privacySettings?.showFollowing != false), let count = user.followingCount {
                            NavigationLink { LanePeopleListScreen(laneID: laneID, following: true) } label: {
                                VStack { Text("\(count)").font(.headline); Text("Following").font(.caption).foregroundStyle(.secondary) }
                            }.accessibilityIdentifier("user.following")
                        }
                    }.buttonStyle(.plain)
                    if !session.isGuest, laneID != session.account?.laneId {
                        Button {
                            saving = true; error = nil
                            Task {
                                defer { saving = false }
                                do { self.user = try await session.setFollowingConfirmed(user, follow: user.isFollowing != true) }
                                catch { self.error = error.localizedDescription }
                            }
                        } label: {
                            Text(saving ? "Saving…" : (user.isFollowing == true ? "Following" : "Follow"))
                                .font(.headline).foregroundStyle(.black).frame(maxWidth: .infinity).padding(15)
                                .background(lanePink, in: Capsule())
                        }.buttonStyle(.plain).disabled(saving).padding(.horizontal, 24)
                            .accessibilityIdentifier("user.follow")
                    }
                    if let error {
                        Text(error).font(.callout).foregroundStyle(lanePink).padding(.horizontal, 20)
                        Button("Refresh profile") { Task { await load() } }.disabled(loading || saving)
                    }
                    if let badges = user.badges, !badges.isEmpty {
                        LaneBadgesSection(badges: badges, own: laneID == session.account?.laneId).padding(.horizontal, 16)
                    }
                    if let status = user.statusTrack {
                        Button {
                            let track = TrackCandidate(status)
                            session.queue = [track]; session.currentIndex = 0
                            session.requestStream(for: track); showPlayer = true
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkView(url: status.coverUrl, size: 50, radius: 8)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(status.title ?? "Status track").font(.headline)
                                    Text(status.artistsDisplayedName ?? "").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: "play.fill")
                            }.padding(12).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain).padding(.horizontal, 16)
                    }
                    if (laneID == session.account?.laneId || user.privacySettings?.showPlaylists != false), let playlists = user.publicPlaylists, !playlists.isEmpty {
                        Text("Public playlists").font(.title3.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
                        ForEach(Array(playlists.enumerated()), id: \.offset) { _, playlist in
                            NavigationLink { PlaylistDetailScreen(playlist: playlist, showPlayer: $showPlayer) } label: { PlaylistRow(playlist: playlist) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if loading { ProgressView("Loading profile…") }
                if let error, user == nil {
                    Text(error).font(.callout).foregroundStyle(lanePink).padding(.horizontal, 20)
                    Button("Try again") { Task { await load() } }.disabled(loading || saving)
                }
            }.padding(.bottom, 24)
        }
        .background(laneBackground)
        .navigationTitle("Profile").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .tint(.white)
        .laneIOSBackSwipe()
        .task(id: laneID) { await load() }
        .refreshable { await load() }
        .fullScreenCover(isPresented: $showPlayer) { APKFullPlayerView().environmentObject(session) }
    }

    private func load() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do { user = try await session.fetchUserProfile(laneID) }
        catch { self.error = error.localizedDescription }
    }
}

struct LanePeopleListScreen: View {
    @EnvironmentObject private var session: LaneSession
    let laneID: String
    let following: Bool
    @State private var users: [UserInfoDTO] = []
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            ForEach(Array(users.enumerated()), id: \.offset) { _, user in
                if let id = user.laneId {
                    NavigationLink { LaneUserProfileScreen(laneID: id) } label: {
                        HStack(spacing: 12) {
                            AvatarView(url: user.avatarUrl, size: 46)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(user.displayedName ?? user.userName ?? "Lane user").font(.headline)
                                if let name = user.userName { Text("@\(name)").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }.accessibilityIdentifier("people.\(id)")
                }
            }
            if loading { ProgressView() }
            if !loading && users.isEmpty && error == nil { Text(following ? "Not following anyone yet" : "No followers yet").foregroundStyle(.secondary) }
            if hasMore { Button("Load more") { Task { await load(reset: false) } }.disabled(loading) }
            if let error { Text(error).foregroundStyle(lanePink); Button("Try again") { Task { await load(reset: users.isEmpty) } }.disabled(loading) }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).background(laneBackground)
        .navigationTitle(following ? "Following" : "Followers").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar).tint(.white).laneIOSBackSwipe()
        // NavigationStack starts view tasks again after returning from a
        // profile. Keep already loaded pages/scroll position on that return;
        // pull-to-refresh is the explicit server reset.
        .task { if users.isEmpty { await load(reset: true) } }
        .refreshable { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        guard !loading, !laneID.isEmpty else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let next = reset ? 0 : page
            let result = try await session.fetchPeople(laneID, following: following, page: next)
            let all = (reset ? [] : users) + result.items
            var seen = Set<String>()
            users = all.filter { $0.laneId.map { seen.insert($0).inserted } ?? false }
            page = next + 1
            hasMore = result.totalPages.map { page < $0 } ?? (result.items.count == 30)
        } catch { self.error = error.localizedDescription }
    }
}

struct PrivacySettingsScreen: View {
    @EnvironmentObject private var session: LaneSession
    @State private var settings = LanePrivacySettings()
    @State private var loaded = false
    @State private var saving = false
    @State private var error: String?
    @State private var saved = false

    var body: some View {
        Form {
            Section("Visible on your profile") {
                if loaded {
                    Toggle("Show playlists", isOn: $settings.showPlaylists).accessibilityIdentifier("privacy.playlists")
                    Toggle("Show followers", isOn: $settings.showFollowers)
                    Toggle("Show following", isOn: $settings.showFollowing)
                } else { ProgressView("Loading privacy settings…") }
            }
            .disabled(!loaded || saving)
            Section {
                Button(saving ? "Saving…" : "Save privacy settings") {
                    saving = true
                    saved = false
                    error = nil
                    Task {
                        defer { saving = false }
                        do { try await session.savePrivacySettings(settings); saved = true }
                        catch { self.error = error.localizedDescription }
                    }
                }
                .disabled(!loaded || saving)
                .accessibilityIdentifier("privacy.save")
                if saved { Text("Privacy settings saved to Lane").foregroundStyle(.green) }
                if let error { Text(error).foregroundStyle(lanePink) }
                if !loaded {
                    Button("Load settings") { Task { await load() } }
                }
            }
        }
        .tint(lanePink)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .laneIOSBackSwipe()
        .task { loaded = false; await load() }
        .onDisappear { loaded = false }
    }

    private func load() async {
        do { settings = try await session.loadPrivacySettings(); loaded = true; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct NotificationsScreen: View {
    @EnvironmentObject private var session: LaneSession
    @State private var filter = "All"
    @State private var actionError: String?
    @State private var commentTrack: TrackCandidate?
    @State private var selectedArtist: LaneArtist?
    @State private var selectedPlaylist: LanePlaylist?
    @State private var selectedUserID: String?
    @State private var showPlayer = false

    private var filtered: [LaneNotification] {
        session.notifications.filter {
            filter == "All" || (filter == "Comments" && $0.type.hasPrefix("COMMENT_")) ||
                (filter == "Subscriptions" && ["NEW_RELEASE", "NEW_FOLLOWER"].contains($0.type))
        }
    }

    var body: some View {
        List {
            Picker("Notifications", selection: $filter) {
                ForEach(["All", "Comments", "Subscriptions"], id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            if filtered.isEmpty && !session.notificationsLoading {
                EmptyLaneView(icon: "bell", title: "No notifications", subtitle: "Updates from Lane will appear here.")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(filtered) { item in
                    VStack(alignment: .leading, spacing: 12) {
                        Button { open(item) } label: {
                            HStack(spacing: 12) {
                                ArtworkView(url: item.imageURL, size: 46, radius: 23)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                                    if let timestamp = item.timestamp {
                                        Text(Date(timeIntervalSince1970: Double(timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp)), style: .relative)
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                if item.read != true { Circle().fill(lanePink).frame(width: 7, height: 7) }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("notification.\(item.id)")
                        if item.type == "PLAYLIST_INVITATION", item.invitationId != nil {
                            HStack {
                                invitationButton("Accept", item: item, accept: true)
                                invitationButton("Decline", item: item, accept: false)
                            }
                            .disabled(session.notificationMutations.contains(item.id))
                        }
                    }
                    .swipeActions {
                        if item.read != true {
                            Button("Mark read") { Task { await markRead(item) } }.tint(lanePink)
                        }
                    }
                }
            }
            if session.notificationsLoading { ProgressView().tint(lanePink) }
            if session.notificationsHaveMore {
                Button("Load more") { Task { await session.loadNotifications() } }
                    .disabled(session.notificationsLoading)
            }
            if let error = actionError ?? session.notificationsError { Text(error).foregroundStyle(lanePink) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(laneBackground)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Read all") {
                    Task {
                        do { try await session.markAllNotificationsRead(); actionError = nil }
                        catch { actionError = error.localizedDescription }
                    }
                }
                .disabled(session.unreadNotificationCount == 0)
            }
        }
        .laneIOSBackSwipe()
        .task { await session.loadNotifications(reset: true) }
        .refreshable { await session.loadNotifications(reset: true) }
        .sheet(item: $commentTrack) { track in APKCommentsScreen(track: track).environmentObject(session) }
        .navigationDestination(isPresented: Binding(get: { selectedArtist != nil }, set: { if !$0 { selectedArtist = nil } })) {
            if let artist = selectedArtist { APKArtistDetailScreen(seed: artist) }
        }
        .navigationDestination(isPresented: Binding(get: { selectedPlaylist != nil }, set: { if !$0 { selectedPlaylist = nil } })) {
            if let playlist = selectedPlaylist { PlaylistDetailScreen(playlist: playlist, showPlayer: $showPlayer) }
        }
        .navigationDestination(isPresented: Binding(get: { selectedUserID != nil }, set: { if !$0 { selectedUserID = nil } })) {
            if let id = selectedUserID { LaneUserProfileScreen(laneID: id) }
        }
        .fullScreenCover(isPresented: $showPlayer) { APKFullPlayerView().environmentObject(session) }
    }

    private func markRead(_ item: LaneNotification) async {
        do { try await session.markNotificationRead(item); actionError = nil }
        catch { actionError = error.localizedDescription }
    }

    private func invitationButton(_ title: String, item: LaneNotification, accept: Bool) -> some View {
        Button(title) {
            Task {
                do { try await session.respondToInvitation(item, accept: accept); actionError = nil }
                catch { actionError = error.localizedDescription }
            }
        }
        .buttonStyle(.bordered)
        .tint(accept ? lanePink : .gray)
        .accessibilityIdentifier("invitation.\(accept ? "accept" : "decline").\(item.id)")
    }

    private func open(_ item: LaneNotification) {
        Task {
            await markRead(item)
            if let id = item.trackId {
                let tracks = await session.resolveTracksByIDs([id])
                commentTrack = tracks.first
                if commentTrack == nil { actionError = "Lane could not load the track. Please try again." }
            } else if let id = item.playlistId {
                selectedPlaylist = LanePlaylist(playlistId: id, playlistImageUrl: item.playlistCoverUrl, playlistName: item.playlistName)
            } else if let artist = item.artistInfo, let id = artist.id {
                selectedArtist = LaneArtist(name: artist.name, id: id, avatarUrl: artist.avatarUrl)
            } else if let id = item.actorInfo?.laneId {
                selectedUserID = id
            }
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

private struct LocalPlaylistDetailScreen: View {
    @EnvironmentObject private var session: LaneSession
    let playlist: LocalPlaylist
    @Binding var showPlayer: Bool

    private var tracks: [TrackCandidate] {
        session.tracks(in: playlist)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    if let first = tracks.first {
                        ArtworkView(url: first.coverURL, size: 72, radius: 10)
                    } else {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(lanePink)
                            .frame(width: 72, height: 72)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(playlist.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text("\(tracks.count) tracks · On this iPhone")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        guard let first = tracks.first else { return }
                        session.queue = tracks
                        session.currentIndex = 0
                        session.requestStream(for: first)
                    } label: {
                        Image(systemName: "play.fill")
                            .foregroundStyle(.black)
                            .frame(width: 48, height: 48)
                            .background(Color.white, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(tracks.isEmpty)
                }
                .padding(.vertical, 6)
            }

            if tracks.isEmpty {
                EmptyLaneView(
                    icon: "music.note.list",
                    title: "Empty playlist",
                    subtitle: "Import tracks to fill this playlist."
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track: track, showPlayer: $showPlayer, playbackQueue: tracks)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                session.queue = tracks
                                session.currentIndex = index
                                session.requestStream(for: track)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            .tint(lanePink)
                        }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(laneBackground)
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FavoriteTracksScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss
    @Binding var showPlayer: Bool
    @State private var confirmClear = false
    @State private var showActions = false
    @State private var clearAfterActions = false
    @State private var clearCompleted = 0
    @State private var clearTotal = 0
    @State private var clearError: String?

    private var tracks: [TrackCandidate] {
        var seen = Set<String>()
        return session.likedTracks.filter {
            guard session.isFavorite($0) else { return false }
            let key = $0.trackID ?? $0.id
            return seen.insert(key).inserted
        }
    }

    var body: some View {
        List {
            if let stage = session.playlistImportStages["lane_likes"] {
                ProgressView(stage)
                    .accessibilityIdentifier("playlist.import.progress")
                Text("You can leave this screen. The selected order is confirmed after all batches are saved.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = session.playlistImportErrors["lane_likes"] {
                Text(error).foregroundStyle(lanePink)
            }
            if session.clearingPlaylistIDs.contains("lane_likes") {
                ProgressView(session.playlistClearStages["lane_likes"] ?? "Removing \(clearCompleted)/\(clearTotal) tracks…")
                    .accessibilityIdentifier("playlist.clear.progress")
                Button("Остановить удаление") { session.stopClearingPlaylist("lane_likes") }
                    .accessibilityIdentifier("playlist.clear.stop")
            }
            if let clearError { Text(clearError).foregroundStyle(lanePink) }
            if tracks.isEmpty {
                EmptyLaneView(icon: "heart", title: "Favorite Tracks", subtitle: "Tap the heart on a track to save it.")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track: track, showPlayer: $showPlayer, playbackQueue: tracks)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                session.toggleFavorite(track)
                            } label: {
                                Label("Unlike", systemImage: "heart.slash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                session.queue = tracks
                                session.currentIndex = index
                                session.requestStream(for: track)
                                showPlayer = true
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            .tint(lanePink)
                        }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(laneBackground)
        // The library root hides UINavigationBar. Adding a native toolbar on
        // this child left a ghost menu under the status bar on iPhone 13.
        // Use the same safe-area header as the APK-style playlist cards.
        .toolbar(.hidden, for: .navigationBar)
        .laneIOSBackSwipe()
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 0) {
                APKImportBackButton { dismiss() }
                    .accessibilityIdentifier("liked.back")
                Text("Liked tracks")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                Button { showActions = true } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("playlist.actions")
                .accessibilityLabel("Playlist actions")
            }
            .padding(.horizontal, 8)
            .frame(height: 52)
            .background(laneBackground.opacity(0.96))
        }
        .sheet(isPresented: $showActions, onDismiss: {
            if clearAfterActions { clearAfterActions = false; confirmClear = true }
        }) {
            VStack(spacing: 18) {
                Text("Liked tracks").font(.headline)
                if let order = session.playlistImportOrderTitle("lane_likes") {
                    Text("Import order: \(order)").font(.caption).foregroundStyle(.secondary)
                    Button("Use server order") {
                        session.useServerPlaylistOrder("lane_likes")
                        showActions = false
                    }.accessibilityIdentifier("playlist.order.server")
                        .disabled(session.importingPlaylistIDs.contains("lane_likes") || session.clearingPlaylistIDs.contains("lane_likes"))
                }
                Button(role: .destructive) {
                    clearAfterActions = true
                    showActions = false
                } label: {
                    Label("Удалить все треки", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("playlist.clear")
                .disabled(session.isGuest || session.clearingPlaylistIDs.contains("lane_likes") || session.importingPlaylistIDs.contains("lane_likes"))
                Button("Cancel") { showActions = false }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(laneBackground)
            .presentationDetents([.height(session.playlistImportOrderTitle("lane_likes") == nil ? 210 : 290)])
            .presentationDragIndicator(.visible)
        }
        .alert("Удалить все лайкнутые треки?", isPresented: $confirmClear) {
            Button("Удалить все треки", role: .destructive) {
                Task {
                    clearError = nil
                    do {
                        try await session.clearPlaylistTracks(LanePlaylist(playlistId: "lane_likes")) { completed, total in
                            clearCompleted = completed; clearTotal = total
                        }
                    } catch is CancellationError { clearError = "Удаление остановлено. Уже удалённые треки не возвращаются; повтор продолжит с оставшихся." }
                    catch { clearError = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Лайки будут удалены на сервере Lane и пропадут на всех устройствах. Скачанные файлы останутся. Это действие нельзя отменить.")
        }
        .refreshable {
            session.refreshLibrary()
        }
    }
}

struct DownloadsScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Binding var showPlayer: Bool

    private var downloaded: [TrackCandidate] {
        session.downloadedTracks
    }

    var body: some View {
        List {
            if downloaded.isEmpty {
                EmptyLaneView(icon: "arrow.down.circle", title: "Downloads", subtitle: "Save tracks to listen offline.")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(Array(downloaded.enumerated()), id: \.element.id) { index, track in
                    APKSearchTrackRow(track: track) {
                        session.queue = downloaded
                        session.currentIndex = index
                        session.requestStream(for: track)
                        showPlayer = true
                    }
                    .swipeActions {
                        Button("Remove download", role: .destructive) {
                            do { try session.removeDownload(track) }
                            catch { session.output = error.localizedDescription }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(laneBackground)
        .navigationTitle("Downloads")
        .toolbar(.visible, for: .navigationBar)
        .laneIOSBackSwipe()
    }
}

struct CreatePlaylistSheet: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss

    let initialTrackIDs: [String]
    let onCreated: (LanePlaylist) -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var saving = false
    @State private var errorMessage: String?

    init(
        initialTrackIDs: [String] = [],
        onCreated: @escaping (LanePlaylist) -> Void = { _ in }
    ) {
        self.initialTrackIDs = initialTrackIDs
        self.onCreated = onCreated
    }

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
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(lanePink)
                }
            }
            .navigationTitle("Create Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        guard !saving else { return }
                        saving = true
                        errorMessage = nil
                        Task {
                            do {
                                let playlist = try await session.createServerPlaylist(
                                    name: name,
                                    description: description,
                                    trackIDs: initialTrackIDs
                                )
                                onCreated(playlist)
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            saving = false
                        }
                    }
                    .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private enum MusicImportPlatform: String, CaseIterable, Identifiable {
    case spotify = "Spotify"
    case soundCloud = "SoundCloud"
    case telegram = "Telegram"
    case yandex = "Yandex"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .spotify: return "music.note"
        case .soundCloud: return "cloud.fill"
        case .telegram: return "paperplane.fill"
        case .yandex: return "waveform"
        }
    }

    var asset: String {
        switch self {
        case .spotify: return "ic_spotify"
        case .soundCloud: return "ic_soundcloud"
        case .telegram: return "telegram"
        case .yandex: return "ic_yandex_music"
        }
    }

    var displayName: String {
        self == .yandex ? "Yandex Music" : rawValue
    }

    var accent: Color {
        switch self {
        case .spotify: return Color(red: 0.12, green: 0.84, blue: 0.38)
        case .soundCloud: return Color(red: 1.0, green: 0.33, blue: 0.0)
        case .telegram: return Color(red: 0.12, green: 0.65, blue: 0.92)
        case .yandex: return Color(red: 1.0, green: 0.76, blue: 0.05)
        }
    }
}

private enum MusicImportKind: String, CaseIterable, Identifiable {
    case playlist = "Playlist"
    case liked = "Liked tracks"

    var id: String { rawValue }
}

private enum MusicImportStep: Equatable {
    case platforms
    case options
    case input
    case preview
}

struct ImportTracksScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var step: MusicImportStep = .platforms
    @State private var platform: MusicImportPlatform = .spotify
    @State private var importKind: MusicImportKind = .playlist
    @State private var sourceValue = ""
    @State private var spotifyBearerToken = ""
    @State private var spotifyClientToken = ""
    @State private var telegramCode = ""
    @State private var preview: LanePlaylist?
    @State private var previewTracks: [TrackCandidate] = []
    @State private var targetPlaylistID = ""
    @State private var message = ""
    @State private var loading = false
    @State private var localSaving = false
    @State private var importCompleted = 0
    @State private var importTotal = 0
    @State private var importStage = ""
    @State private var importTask: Task<Void, Never>?
    @State private var yandexTracks: [YandexImportTrack] = []
    @State private var importedTrackIDs: [String] = []
    @State private var importSort: LaneMusicImportSort = .original
    @State private var yandexMetadataTask: Task<[YandexImportTrack], Never>?
    @State private var previewRequestID = UUID()

    init() {}

    #if DEBUG
    init(fixture: LanePlaylist, source: [YandexImportTrack]) {
        _preview = State(initialValue: fixture)
        _yandexTracks = State(initialValue: source)
        _platform = State(initialValue: .yandex)
        _step = State(initialValue: .preview)
        _targetPlaylistID = State(initialValue: "lane_likes")
    }
    #endif

    var body: some View {
        ZStack {
            laneBackground.ignoresSafeArea()

            RadialGradient(
                colors: [platform.accent.opacity(step == .platforms ? 0.05 : 0.18), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                importTopBar

                ScrollView {
                    Group {
                        switch step {
                        case .platforms:
                            platformSelection
                        case .options:
                            importOptions
                        case .input:
                            platformInput
                        case .preview:
                            if let preview {
                                importPreview(preview)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
        }
        .onAppear {
            if targetPlaylistID.isEmpty {
                targetPlaylistID = session.serverPlaylists.first?.playlistId ?? ""
            }
        }
        // This unstructured task finishes its read-back/reorder even when the
        // user returns to Library. Leaving a screen is not a cancellation of
        // the already accepted server writes. Account changes still cancel it.
        .toolbar(.hidden, for: .navigationBar)
        .laneIOSBackSwipe()
    }

    private var importTopBar: some View {
        HStack {
            APKImportBackButton(action: navigateBack)
                .accessibilityIdentifier("import.back")

            Spacer()

            if step == .preview {
                Text("Import preview")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
    }

    private var platformSelection: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 26)

            AvatarView(url: session.account?.avatarUrl, size: 80)

            Spacer().frame(height: 16)

            Text(session.account?.displayedName ?? "Lane")
                .font(.system(size: 20, weight: .bold))

            if let username = session.account?.userName, !username.isEmpty {
                Text("@\(username)")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .padding(.top, 2)
            }

            Spacer().frame(height: 54)

            Text("Import your tracks")
                .font(.system(size: 27, weight: .bold))
                .multilineTextAlignment(.center)

            Text("Music is always with you, regardless of the platform")
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            VStack(spacing: 16) {
                ForEach(MusicImportPlatform.allCases) { item in
                    APKImportPlatformButton(
                        title: item.displayName,
                        asset: item.asset
                    ) {
                        platform = item
                        importKind = .playlist
                        resetPreview()
                        step = .options
                    }
                }
            }
            .padding(.top, 32)
        }
        .frame(maxWidth: .infinity)
    }

    private var importOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 22)

            (Text("What do you want to\nimport from ") +
                Text(platform.displayName).foregroundColor(platform.accent) +
                Text("?"))
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(.white)

            VStack(spacing: 24) {
                if platform == .telegram {
                    APKImportOptionButton(
                        icon: "music.note.list",
                        title: "Tracks",
                        subtitle: "Transfer your tracks via the official Lane Telegram bot",
                        accent: platform.accent
                    ) {
                        importKind = .playlist
                        step = .input
                    }
                } else {
                    APKImportOptionButton(
                        icon: "heart",
                        title: "Favorite tracks",
                        subtitle: "Transfer your liked tracks",
                        accent: platform.accent
                    ) {
                        importKind = .liked
                        step = .input
                    }

                    APKImportOptionButton(
                        icon: "music.note.list",
                        title: "Playlist",
                        subtitle: platform == .soundCloud
                            ? "Add tracks from any SoundCloud playlist"
                            : "Add tracks from any playlist",
                        accent: platform.accent
                    ) {
                        importKind = .playlist
                        step = .input
                    }
                }
            }
            .padding(.top, 48)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var platformInput: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 22)

            Text(inputTitle)
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 38)

            if platform == .telegram {
                telegramImportControls
            } else {
                VStack(spacing: 14) {
                    if platform == .spotify, importKind == .liked {
                        tokenField("Spotify bearer token", text: $spotifyBearerToken)
                        tokenField("Spotify client token", text: $spotifyClientToken)

                        Text("Use the same Spotify session tokens as the Android importer.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField(sourcePlaceholder, text: $sourceValue)
                            .font(.system(size: 16, weight: .medium))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .background(Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(platform.accent.opacity(0.70), lineWidth: 1)
                            }
                    }

                    APKPrimaryButton(
                        title: loading ? "Loading preview…" : "Continue",
                        loading: loading,
                        enabled: canRequestPreview,
                        action: requestPreview
                    )
                }
            }

            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(lanePink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 20)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputTitle: String {
        if platform == .telegram {
            return "Transfer tracks with the Lane Telegram bot"
        }
        if importKind == .liked {
            switch platform {
            case .spotify: return "Connect Spotify to import your favorite tracks"
            case .soundCloud: return "Enter the URL of your SoundCloud profile"
            case .yandex: return "Enter the URL of your Yandex Music favorite playlist"
            case .telegram: return ""
            }
        }
        return "Enter the URL of the\n\(platform.displayName) playlist"
    }

    private func tokenField(_ title: String, text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .font(.system(size: 16, weight: .medium))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(platform.accent.opacity(0.70), lineWidth: 1)
            }
    }

    private var sourcePlaceholder: String {
        switch (platform, importKind) {
        case (.spotify, _): return "Spotify playlist link or ID"
        case (.soundCloud, .playlist): return "SoundCloud playlist link or ID"
        case (.soundCloud, .liked): return "SoundCloud profile link"
        case (.yandex, .playlist): return "Yandex playlist link or ID"
        case (.yandex, .liked): return "Yandex liked playlist link or ID"
        case (.telegram, _): return ""
        }
    }

    private var canRequestPreview: Bool {
        guard !session.isGuest else { return false }
        if platform == .spotify, importKind == .liked {
            return !spotifyBearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !spotifyClientToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !sourceValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var telegramImportControls: some View {
        if telegramCode.isEmpty {
            APKPrimaryButton(
                title: loading ? "Requesting code…" : "Get Telegram import code",
                loading: loading,
                enabled: !session.isGuest,
                action: startTelegramImport
            )
        } else {
            let command = "/import \(telegramCode)"

            Text("Send this command to the Lane bot:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text(command)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                Spacer()
                Button {
                    UIPasteboard.general.string = command
                    message = "Command copied."
                } label: {
                    Image(systemName: "doc.on.doc")
                }
            }
            .padding(12)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(platform.accent.opacity(0.45), lineWidth: 1)
            }

            HStack(spacing: 12) {
                Button {
                    if let url = URL(string: "https://t.me/lane_music_bot") {
                        openURL(url)
                    }
                } label: {
                    Text("Open bot")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.bordered)

                APKPrimaryButton(
                    title: loading ? "Checking…" : "I sent it",
                    loading: loading,
                    action: finishTelegramImport
                )
            }
        }
    }

    private func importPreview(_ playlist: LanePlaylist) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ArtworkView(url: playlist.playlistImageUrl, size: 64, radius: 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.playlistName ?? "Import preview")
                        .font(.headline)
                    Text("\(previewDisplayCount) tracks in Lane preview")
                        .accessibilityIdentifier("import.count")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Import order", selection: $importSort) {
                ForEach(LaneMusicImportSort.allCases) { option in Text(option.rawValue).tag(option) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("import.order")
            .disabled(loading)
            Text("This order will be saved in the Lane playlist. Existing unrelated tracks will be kept.")
                .font(.caption2).foregroundStyle(.secondary)
            if !importStage.isEmpty {
                Text(importStage).font(.caption).foregroundStyle(lanePink)
                    .accessibilityIdentifier("import.stage")
            }

            if !yandexTracks.isEmpty {
                if yandexTracks.count != importSourceCount {
                    Text("Yandex shows \(yandexTracks.count) tracks, but Lane returned \(importSourceCount) importable IDs. Only the Lane preview can be added to a Lane playlist.")
                        .font(.caption)
                        .foregroundStyle(lanePink)
                }

                ForEach(Array(sortedYandexTracks.prefix(8))) { track in
                    HStack(spacing: 10) {
                        ArtworkView(url: track.coverURL, size: 42, radius: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).lineLimit(1)
                            Text(track.artistText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } else {
                ForEach(Array(previewTracks.prefix(8))) { track in
                    HStack(spacing: 10) {
                        ArtworkView(url: track.coverURL, size: 42, radius: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).lineLimit(1)
                            Text(track.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            if session.serverPlaylists.isEmpty {
                Text("Create a Lane playlist first, then return here to import the tracks.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Add to", selection: $targetPlaylistID) {
                    ForEach(session.serverPlaylists, id: \.playlistId) { target in
                        Text(target.playlistName ?? "Playlist")
                            .tag(target.playlistId ?? "")
                    }
                }
                .pickerStyle(.menu)

                APKPrimaryButton(
                    title: loading && importTotal > 0
                        ? (importStage.isEmpty
                            ? "Importing \(importCompleted)/\(importTotal)…"
                            : importStage)
                        : importButtonTitle,
                    loading: loading,
                    enabled: !targetPlaylistID.isEmpty && importSourceCount > 0,
                    action: importPreviewTracks
                )
                .accessibilityIdentifier("import.start")
            }

            if !importedTrackIDs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("In Lane playlist · \(importedTrackIDs.count)")
                        .font(.system(size: 14, weight: .bold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(importedTrackIDs.suffix(12)), id: \.self) { id in
                                let track = session.cachedTracksForIDs([id]).first
                                VStack(alignment: .leading, spacing: 6) {
                                    ZStack(alignment: .bottomTrailing) {
                                        ArtworkView(url: track?.coverURL, size: 72, radius: 10)
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.green)
                                            .background(Color.black, in: Circle())
                                    }
                                    Text(track?.title ?? "Lane track")
                                        .font(.caption)
                                        .lineLimit(1)
                                        .frame(width: 72, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            }

            Button(action: saveAllOnDevice) {
                HStack(spacing: 10) {
                    if localSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "iphone.and.arrow.forward")
                    }

                    Text(localSaving ? "Saving all tracks…" : "Save all \(importSourceCount) on this iPhone")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(localSaving || loading || importSourceCount == 0)

            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(
                        message.hasPrefix("All") || message.hasPrefix("Saved")
                            ? Color.green
                            : lanePink
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .background(laneCard, in: RoundedRectangle(cornerRadius: 18))
    }

    private var importTrackIDs: [String] {
        // These are resolver input IDs. Each 15-track batch is converted to
        // canonical songIds immediately before the playlist write.
        preview?.importSourceIDs ?? []
    }

    private var importButtonTitle: String {
        "Import all \(importSourceCount) to Lane"
    }

    private var importSourceCount: Int {
        importTrackIDs.count
    }

    private var previewDisplayCount: Int {
        max(importSourceCount, preview?.effectiveTrackCount ?? 0)
    }

    private var sortedYandexTracks: [YandexImportTrack] {
        switch importSort {
        case .original:
            return yandexTracks.sorted { $0.originalIndex < $1.originalIndex }
        case .oldest:
            return yandexTracks.sorted { $0.originalIndex > $1.originalIndex }
        case .title:
            return yandexTracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist:
            return yandexTracks.sorted { $0.artistText.localizedStandardCompare($1.artistText) == .orderedAscending }
        }
    }

    private func resetPreview() {
        yandexMetadataTask?.cancel()
        yandexMetadataTask = nil
        preview = nil
        previewTracks = []
        yandexTracks = []
        importedTrackIDs = []
        importSort = .original
        message = ""
    }

    private func navigateBack() {
        switch step {
        case .platforms:
            dismiss()
        case .options:
            step = .platforms
        case .input:
            step = .options
        case .preview:
            step = .input
        }
    }

    private func acceptPreview(_ value: LanePlaylist) async {
        preview = value
        if targetPlaylistID.isEmpty {
            targetPlaylistID = session.serverPlaylists.first?.playlistId ?? ""
        }
        previewTracks = (value.playlistTracks ?? []).prefix(15).map { TrackCandidate($0) }
        step = .preview
        importTotal = value.effectiveTrackCount
        importStage = "Loading first 15 tracks…"
        defer {
            importStage = ""
            importTotal = 0
        }
        do {
            previewTracks = try await session.tracksForImportPreview(value)
            if previewTracks.isEmpty {
                message = "Lane did not resolve any importable tracks from this playlist."
            }
        } catch {
            message = friendlyImportError(error)
        }
    }

    private func requestPreview() {
        resetPreview()
        let requestID = UUID()
        previewRequestID = requestID
        loading = true
        let input = sourceValue.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            defer {
                if previewRequestID == requestID { loading = false }
            }
            do {
                let result = try await session.previewMusicImport(
                    platform: platform.rawValue,
                    spotifyBearerToken: platform == .spotify && importKind == .liked ? spotifyBearerToken : nil,
                    spotifyClientToken: platform == .spotify && importKind == .liked ? spotifyClientToken : nil,
                    spotifyPlaylistID: platform == .spotify && importKind == .playlist ? input : nil,
                    soundCloudPlaylistID: platform == .soundCloud && importKind == .playlist ? input : nil,
                    yandexPlaylistID: platform == .yandex ? input : nil,
                    soundCloudProfileURL: platform == .soundCloud && importKind == .liked ? input : nil
                )
                guard previewRequestID == requestID else { return }
                if platform == .yandex {
                    // Public Yandex metadata decorates the screen but does not
                    // delay or determine the Lane import ID list.
                    let metadata = Task { (try? await session.yandexPlaylistTracks(from: input)) ?? [] }
                    yandexMetadataTask = metadata
                    Task {
                        let tracks = await metadata.value
                        if step == .preview && previewRequestID == requestID {
                            yandexTracks = tracks
                        }
                    }
                }
                await acceptPreview(result)
            } catch {
                message = friendlyImportError(error)
            }
        }
    }

    private func startTelegramImport() {
        loading = true
        message = ""
        Task {
            defer { loading = false }
            do {
                telegramCode = try await session.beginTelegramMusicImport()
            } catch {
                message = friendlyImportError(error)
            }
        }
    }

    private func finishTelegramImport() {
        loading = true
        message = ""
        Task {
            defer { loading = false }
            do {
                let result = try await session.finishTelegramMusicImport()
                await acceptPreview(result)
            } catch {
                message = friendlyImportError(error)
            }
        }
    }

    private func importPreviewTracks() {
        performImport(importTrackIDs)
    }

    private func saveAllOnDevice() {
        guard let preview else { return }
        localSaving = true
        message = ""

        Task {
            defer { localSaving = false }
            let tracks = await session.tracksForLocalImport(preview)
            let saved = session.saveLocalImport(
                name: preview.playlistName ?? "Imported playlist",
                tracks: tracks
            )
            let expected = Set(importTrackIDs.filter { !$0.isEmpty }).count

            if saved >= expected, expected > 0 {
                message = "Saved all \(saved) tracks on this iPhone. The playlist is now in Library."
            } else if saved > 0 {
                message = "Saved \(saved) of \(expected) tracks. Tap again to retry the missing pages."
            } else {
                message = "Lane could not load the track details for local saving. Try again."
            }
        }
    }

    private func performImport(_ ids: [String]) {
        guard !session.importingPlaylistIDs.contains(targetPlaylistID) else {
            message = "This playlist is still importing and confirming its order. You can follow its progress in Library."
            return
        }
        let destination = targetPlaylistID
        let selectedSort = importSort
        let selectedPlatform = platform
        let metadataRequest = yandexMetadataTask
        let sourceReference = yandexTracks
        loading = true
        message = ""
        importCompleted = 0
        importTotal = Set(ids.filter { !$0.isEmpty }).count
        importStage = ""
        importedTrackIDs = []
        importTask = Task {
            defer {
                loading = false
                importStage = ""
                importTask = nil
            }
            do {
                // Public metadata loads alongside the first 15-row preview.
                // If Import is tapped immediately, await that existing request
                // rather than silently sending the unsorted resolver ID list.
                var reference = sourceReference
                if selectedPlatform == .yandex, reference.isEmpty, let metadata = metadataRequest {
                    importStage = "Loading Yandex playlist order…"
                    reference = await metadata.value
                    try Task.checkCancellation()
                }
                if selectedPlatform == .yandex, reference.isEmpty,
                   selectedSort == .original || selectedSort == .oldest {
                    throw LaneAPIError.decoding("The Yandex source order could not be loaded. Retry the preview; no tracks have been added by this attempt.")
                }
                let updateProgress: (Int, Int, String) -> Void = { completed, total, stage in
                    importCompleted = completed
                    importTotal = total
                    importStage = stage
                }
                let imported = try await session.importTracks(
                    ids,
                    into: destination,
                    resolvingSourceIDs: true,
                    sort: selectedSort,
                    orderReference: reference,
                    progress: updateProgress
                ) { batch in
                    importedTrackIDs = LaneTrackBatching.unique(importedTrackIDs + batch)
                }
                if imported >= importTotal {
                    message = "All \(imported) tracks are now in the Lane playlist."
                } else {
                    message = "Added \(imported) of \(importTotal) Lane preview tracks. Lane rejected \(importTotal - imported) IDs."
                }
            } catch {
                session.output = error is LaneImportConfirmationError ? error.localizedDescription : "Import error: \(error.localizedDescription)"
                let detail = friendlyImportError(error)
                if error is LaneImportConfirmationError {
                    message = error.localizedDescription
                } else if importCompleted > 0 {
                    message = "Processed \(importCompleted) of \(importTotal) tracks. Tap again to continue. \(detail)"
                } else {
                    message = detail
                }
            }
        }
    }

    private func friendlyImportError(_ error: Error) -> String {
        let detail = error.localizedDescription
        if detail.localizedCaseInsensitiveContains("timed out") {
            return "Lane is taking longer than usual. Check the link and try again."
        }
        if detail.localizedCaseInsensitiveContains("HTTP 5") ||
            detail.localizedCaseInsensitiveContains("DATA_ACCESS_ERROR") {
            return "The music service is temporarily unavailable. Please try again."
        }
        if detail.localizedCaseInsensitiveContains("INVALID_TRACK_IDS_BODY") {
            return "Lane could not resolve the tracks in this playlist. Please try again."
        }
        if detail.localizedCaseInsensitiveContains("PREMIUM_REQUIRED") {
            return "Lane refused the server import. You can still save the complete playlist on this iPhone."
        }
        let compact = detail
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return "Import failed: \(String(compact.prefix(280)))"
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
                    session.startWave(from: current)
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
                Picker(
                    "Quality",
                    selection: Binding(
                        get: { session.streamQuality },
                        set: { raw in
                            guard let quality = AudioQualityChoice(rawValue: raw) else { return }
                            _ = session.selectStreamQuality(quality)
                        }
                    )
                ) {
                    ForEach(AudioQualityChoice.allCases) { quality in
                        Text("\(quality.rawValue) · \(quality.detail)")
                            .tag(quality.rawValue)
                            .disabled(quality != .basic && !session.hasPremiumAccess)
                    }
                }

                LabeledContent(
                    "Active stream",
                    value: session.activeStreamQuality ?? "Not playing"
                )

                Text("The selected tier is fixed when a track starts. Playback does not downgrade to another quality automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Runtime network profile") {
                Picker("API host", selection: $session.diagnosticHostMode) {
                    Text("Auto").tag("auto")
                    Text("laneapi.com").tag("global")
                    Text("ru.laneapi.com").tag("ru")
                }

                Picker("Transport", selection: $session.diagnosticTransportMode) {
                    Text("System URLSession").tag("system")
                    Text("Auto fallback").tag("auto")
                    Text("Direct TLS/DoH").tag("direct")
                }

                Picker("Media URLs", selection: $session.diagnosticMediaRoute) {
                    Text("Original URLs").tag("original")
                    Text("APK RU CDN rewrite").tag("apk")
                }

                Picker("/user/tracks body", selection: $session.diagnosticTrackBodyMode) {
                    Text("TrackIds object").tag("object")
                    Text("Raw array").tag("raw")
                    Text("Auto-detect").tag("auto")
                }

                Picker("add-tracks body", selection: $session.diagnosticAddBodyMode) {
                    Text("Raw array").tag("raw")
                    Text("TrackIds object").tag("object")
                    Text("Auto-detect").tag("auto")
                }

                Button("Restore stable profile") {
                    session.resetDiagnosticProfileToStable()
                }

                Text("These switches apply immediately. You can test server/transport/body combinations without reinstalling the IPA.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Self-test") {
                Button(session.diagnosticsRunning ? "Running diagnostics…" : "Auto-tune this network") {
                    session.autoTuneLaneNetwork()
                }
                .disabled(session.diagnosticsRunning)

                Button(session.diagnosticsRunning ? "Running diagnostics…" : "Run safe diagnostics") {
                    session.runLaneDiagnostics()
                }
                .disabled(session.diagnosticsRunning || session.mutationDiagnosticsRunning)

                Button(session.mutationDiagnosticsRunning ? "Testing writes…" : "Test playlist writes and clean up") {
                    session.runLaneMutationDiagnostics()
                }
                .disabled(session.diagnosticsRunning || session.mutationDiagnosticsRunning)

                Text("Auto-tune tests the official Lane hosts/transports on this iPhone and selects the fastest working read profile. The write test creates a temporary diagnostic playlist, adds one already-known track, verifies it, and deletes the playlist again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal) {
                    Text(session.diagnosticReport.isEmpty ? "No diagnostics run yet." : session.diagnosticReport)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .frame(minHeight: 150)
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

            Section("Sanitized request trace") {
                HStack {
                    Button("Refresh trace") {
                        session.refreshDiagnosticTrace()
                    }
                    Spacer()
                    Button("Clear", role: .destructive) {
                        session.clearDiagnosticTrace()
                    }
                }

                ScrollView([.horizontal, .vertical]) {
                    Text(session.diagnosticTraceText.isEmpty ? "No trace yet." : session.diagnosticTraceText)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                }
                .frame(minHeight: 180)
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

private struct ServerPlaylistShelf: View {
    let title: String
    let playlists: [LanePlaylist]
    @Binding var showPlayer: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(playlists.enumerated()), id: \.offset) { _, playlist in
                        NavigationLink {
                            PlaylistDetailScreen(playlist: playlist, showPlayer: $showPlayer)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ArtworkView(url: playlist.playlistImageUrl, size: 148, radius: 15)
                                Text(playlist.playlistName ?? "Playlist")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(playlist.playlistDescription ?? "\(playlist.effectiveTrackCount) tracks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 148, alignment: .leading)
                        }
                        .buttonStyle(.plain)
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
        LaneResilientImage(url: url) {
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
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

private struct AvatarView: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        LaneResilientImage(url: url) {
            ZStack {
                Circle().fill(Color.white.opacity(0.10))
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
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
