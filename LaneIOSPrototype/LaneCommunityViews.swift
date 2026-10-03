import SwiftUI
import UIKit
import ImageIO

private let communityPink = Color(red: 1, green: 130.0 / 255, blue: 132.0 / 255)
private let communityBackground = Color(red: 14.0 / 255, green: 14.0 / 255, blue: 14.0 / 255)

private func communityDate(_ timestamp: Int64) -> Date {
    Date(timeIntervalSince1970: Double(timestamp) / 1_000)
}

struct LaneBadgeImage: View {
    let badge: LaneBadgeDefinition
    var size: CGFloat = 28
    var body: some View {
        APKRemoteImage(url: badge.imageUrl)
            .frame(width: size, height: size).clipped()
            .accessibilityLabel(badge.name)
    }
}

struct LaneBadgesSection: View {
    let badges: [LaneUserBadge]
    let own: Bool
    @State private var detail: LaneUserBadge?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Badges").font(.title3.bold())
            Text(own ? "List of rewards you have received" : "List of rewards the user has received")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(badges) { badge in
                        Button { detail = badge } label: {
                            VStack(spacing: 6) {
                                LaneBadgeImage(badge: badge.definition, size: 64)
                                Text(badge.definition.name).font(.caption).lineLimit(2)
                            }.frame(width: 88).padding(8)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain).accessibilityIdentifier("badge.details.\(badge.id)")
                    }
                }
            }
        }
        .sheet(item: $detail) { badge in
            NavigationStack { LaneBadgeDetailsScreen(badge: badge) }
                .preferredColorScheme(.dark)
        }
    }
}

struct LaneBadgeDetailsScreen: View {
    @Environment(\.dismiss) private var dismiss
    let badge: LaneUserBadge
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LaneBadgeImage(badge: badge.definition, size: 140)
                Text(badge.definition.name).font(.title2.bold())
                Text(badge.definition.description.localized()).multilineTextAlignment(.center)
                VStack(spacing: 4) {
                    Text("Date earned:").foregroundStyle(.secondary)
                    Text(communityDate(badge.earnedAt), style: .date)
                }.font(.callout)
            }.frame(maxWidth: .infinity).padding(24)
        }
        .background(communityBackground)
        .navigationTitle("Badge").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
    }
}

struct LaneBadgeSelectionScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss
    @State private var profile: UserInfoDTO?
    @State private var chosenID: String?
    @State private var detail: LaneUserBadge?
    @State private var loading = false
    @State private var saving = false
    @State private var error: String?
    @State private var saved = false
    @State private var generation = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if loading { ProgressView("Loading badges…").frame(maxWidth: .infinity) }
                if let profile {
                    Text("Current badge").font(.headline)
                    Text(profile.equippedBadge?.definition.name ?? "Not selected").foregroundStyle(.secondary)
                        .accessibilityIdentifier("badge.current")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                        Button { chosenID = nil; saved = false } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "minus.circle").font(.system(size: 36)).frame(height: 64)
                                Text("Not selected").font(.caption)
                            }.frame(maxWidth: .infinity).padding(10)
                                .background(tileColor(nil), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityIdentifier("badge.none")
                        ForEach(profile.badges ?? []) { badge in
                            VStack(spacing: 4) {
                                Button { chosenID = badge.id; saved = false } label: {
                                    VStack(spacing: 6) {
                                        LaneBadgeImage(badge: badge.definition, size: 64)
                                        Text(badge.definition.name).font(.caption).lineLimit(2)
                                    }.frame(maxWidth: .infinity).padding(10)
                                }.buttonStyle(.plain).accessibilityIdentifier("badge.select.\(badge.id)")
                                Button("Details") { detail = badge }.font(.caption).padding(.bottom, 8)
                            }.background(tileColor(badge.id), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.disabled(saving || loading)
                    if profile.badges?.isEmpty != false {
                        Text("No badges earned yet.").foregroundStyle(.secondary)
                    }
                    Button {
                        saving = true; saved = false; error = nil
                        let operation = generation
                        let selected = chosenID
                        Task {
                            defer { if operation == generation { saving = false } }
                            do {
                                let confirmed = try await session.equipBadgeConfirmed(selected)
                                guard operation == generation else { return }
                                self.profile = confirmed; self.chosenID = confirmed.equippedBadgeId; saved = true
                            } catch is CancellationError {} catch {
                                guard operation == generation else { return }
                                self.error = error.localizedDescription
                            }
                        }
                    } label: {
                        Text(saving ? "Saving…" : "Set").font(.headline).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).padding(15)
                            .background(communityPink, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).disabled(loading || saving)
                        .accessibilityIdentifier("badge.save")
                    if saved {
                        Text("Badge saved on Lane").foregroundStyle(.secondary).accessibilityIdentifier("badge.saved")
                    }
                }
                if let error {
                    Text(error).font(.callout).foregroundStyle(communityPink).accessibilityIdentifier("badge.error")
                    Button("Refresh badges") { Task { await load() } }.disabled(saving || loading)
                }
            }.padding(18)
        }
        .background(communityBackground)
        .navigationTitle("Your badges").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar).tint(.white).laneIOSBackSwipe()
        .navigationBarBackButtonHidden(true)
        .toolbar { ToolbarItem(placement: .navigationBarLeading) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Back").accessibilityIdentifier("badge.back")
        } }
        .task(id: session.token) {
            generation = UUID(); profile = nil; error = nil; loading = false; saving = false; saved = false
            await load()
        }
        .sheet(item: $detail) { badge in NavigationStack { LaneBadgeDetailsScreen(badge: badge) } }
    }

    private func tileColor(_ id: String?) -> Color {
        chosenID == id ? communityPink.opacity(0.26) : Color.white.opacity(0.06)
    }

    private func load() async {
        guard !loading, !saving else { return }
        let operation = generation
        loading = true; error = nil
        defer { if operation == generation { loading = false } }
        do {
            let value = try await session.fetchOwnBadgeProfile()
            guard operation == generation, !Task.isCancelled else { return }
            profile = value; chosenID = value.equippedBadgeId
        } catch is CancellationError {} catch {
            guard operation == generation else { return }
            self.error = error.localizedDescription
        }
    }
}

// The same original animation used by Android's memorial screen, not an SF Symbol.
private struct LaneMemorialCross: View {
    private static let data = Bundle.main.url(forResource: "amen", withExtension: "gif").flatMap { try? Data(contentsOf: $0) }
    var body: some View {
        if let data = Self.data { LaneAnimatedImage(data: data, contentMode: .fit) }
    }
}

struct LaneMemorialScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.dismiss) private var dismiss
    let artist: LaneArtist
    @State private var candles: [LaneArtistCandle] = []
    @State private var count: Int64?
    @State private var nextPage = 1
    @State private var hasMore = true
    @State private var loading = false
    @State private var saving = false
    @State private var composing = false
    @State private var message = ""
    @State private var ownCandle: LaneArtistCandle?
    @State private var error: String?
    @State private var generation = UUID()
    @State private var accountIdentity: String?
    @State private var memoryPage = 0
    @FocusState private var messageFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 22) {
                    if let ownCandle {
                        Text("You honored the memory").font(.title2.bold())
                            .accessibilityIdentifier("memorial.confirmed")
                        candle(ownCandle)
                    } else if composing {
                        APKBundleImage(name: "candle").frame(height: 120)
                        TextField("Leave a message", text: $message, axis: .vertical)
                            .lineLimit(3...6).padding(16)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("memorial.message")
                            .focused($messageFocused)
                        Text("\(message.utf16.count) / 200").font(.caption).foregroundStyle(.secondary)
                        Button {
                            submit()
                        } label: { actionLabel(saving ? "Sending…" : "Leave a candle") }
                            .buttonStyle(.plain).disabled(saving || loading || !LaneCandleText.isValid(message) || session.isGuest)
                            .accessibilityIdentifier("memorial.submit")
                    } else {
                        LaneMemorialCross().frame(width: 190, height: 190)
                        Text(artist.name ?? "Artist").font(LaneTypography.memorial(25)).multilineTextAlignment(.center)
                            .shadow(color: .white.opacity(0.45), radius: 10)
                        if let info = artist.custom?.ripInfo {
                            HStack(spacing: 6) {
                                Text(communityDate(info.startDate), style: .date)
                                Text("–")
                                Text(communityDate(info.endDate), style: .date)
                            }.font(LaneTypography.light(16)).foregroundStyle(.secondary)
                            if let text = info.additionalText, !text.isEmpty { Text(text).font(.callout).multilineTextAlignment(.center) }
                        }
                        Text("Eternal memory").font(LaneTypography.light(16)).foregroundStyle(.secondary)
                        Button { composing = true; error = nil } label: { actionLabel("Leave a candle") }
                            .buttonStyle(.plain).disabled(session.isGuest || artist.id == nil)
                            .accessibilityIdentifier("memorial.compose")
                        if session.isGuest { Text("Sign in to leave a candle.").font(.caption).foregroundStyle(.secondary) }
                    }
                    if let count {
                        Text("\(count) candles").font(.headline).accessibilityIdentifier("memorial.count")
                    }
                    if let error {
                        Text(error).font(.callout).foregroundStyle(communityPink).accessibilityIdentifier("memorial.error")
                        Button("Refresh candles") { Task { await reload() } }.disabled(loading || saving)
                            .accessibilityIdentifier("memorial.retry")
                    }
                    if !composing || ownCandle != nil {
                        Text("Candles from other users").font(.headline)
                        let memories = candles.filter { $0.id != ownCandle?.id }
                        if !memories.isEmpty {
                            VStack(spacing: 8) {
                                TabView(selection: $memoryPage) {
                                    ForEach(Array(memories.enumerated()), id: \.element.id) { index, value in
                                        ScrollView { candle(value).padding(.vertical, 14) }
                                            .frame(width: max(0, geometry.size.width - 36), height: 350)
                                            .rotationEffect(.degrees(-90))
                                            .frame(width: 350, height: max(0, geometry.size.width - 36))
                                            .tag(index)
                                    }
                                }
                                .tabViewStyle(.page(indexDisplayMode: .never))
                                .frame(width: 350, height: max(0, geometry.size.width - 36))
                                .rotationEffect(.degrees(90))
                                .frame(width: max(0, geometry.size.width - 36), height: 350)
                                .accessibilityIdentifier("memorial.pager")
                                HStack {
                                    Button("Previous memory") { withAnimation { memoryPage = max(0, memoryPage - 1) } }.disabled(memoryPage == 0)
                                    Spacer()
                                    Text("\(memoryPage + 1) / \(memories.count)").font(.caption).accessibilityIdentifier("memorial.page")
                                    Spacer()
                                    Button("Next memory") { withAnimation { memoryPage = min(memories.count - 1, memoryPage + 1) } }.disabled(memoryPage >= memories.count - 1)
                                }.font(.caption)
                                Text("Swipe up or down to browse memories").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        if hasMore {
                            Button("Load more candles") { Task { await loadMore() } }
                                .disabled(loading || saving).accessibilityIdentifier("memorial.more")
                        }
                        if candles.isEmpty, !loading, error == nil { Text("No candles yet.").foregroundStyle(.secondary) }
                    }
                    if loading { ProgressView("Loading candles…") }
                }.frame(width: max(0, geometry.size.width - 36)).padding(.horizontal, 18).padding(.vertical, 24)
            }
        }
        .background {
            APKRemoteImage(url: artist.headerUrl ?? artist.avatarUrl, cornerRadius: 0)
                .blur(radius: 10).overlay(Color.black.opacity(0.84)).ignoresSafeArea()
        }
        .navigationTitle("Eternal memory").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true).toolbar(.visible, for: .navigationBar).tint(.white).laneIOSBackSwipe()
        .toolbar { ToolbarItem(placement: .navigationBarLeading) {
            Button {
                if composing { composing = false; error = nil } else { dismiss() }
            } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Back").accessibilityIdentifier("memorial.back")
        } }
        .toolbar { ToolbarItemGroup(placement: .keyboard) {
            Spacer(); Button("Done") { messageFocused = false }
        } }
        .onChange(of: candles.count) { _ in memoryPage = min(memoryPage, max(0, candles.filter { $0.id != ownCandle?.id }.count - 1)) }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: ownCandle?.id)
        .task(id: session.token) {
            if accountIdentity != session.token {
                accountIdentity = session.token
                generation = UUID(); loading = false; saving = false; candles = []; count = nil
                ownCandle = nil; composing = false; message = ""; nextPage = 1; hasMore = true
                await reload()
            } else if count == nil && candles.isEmpty && error == nil {
                // Restart a cancelled initial read, but preserve the draft,
                // pagination and confirmed candle when returning from a profile.
                await reload()
            }
        }
    }

    private func actionLabel(_ title: String) -> some View {
        Text(title).font(.headline).foregroundStyle(.black).frame(maxWidth: .infinity).padding(15)
            .background(communityPink, in: RoundedRectangle(cornerRadius: 12))
    }

    private func candle(_ value: LaneArtistCandle) -> some View {
        VStack(spacing: 14) {
            APKBundleImage(name: "candle").frame(height: 100)
                .accessibilityLabel("Candle").accessibilityIdentifier("memorial.candle.\(value.id)")
            Text(value.text).multilineTextAlignment(.center).font(.title3)
            if let user = value.author, let id = user.laneId, !id.isEmpty {
                NavigationLink { LaneUserProfileScreen(laneID: id) } label: {
                    HStack(spacing: 8) {
                        APKRemoteImage(url: user.avatarUrl, circle: true).frame(width: 30, height: 30)
                        Text(user.displayedName ?? user.userName ?? "Lane user").font(.callout)
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("memorial.author.\(value.id)")
            } else if let user = value.author { Text(user.displayedName ?? "Lane user").font(.callout).foregroundStyle(.secondary) }
            Text(communityDate(value.timestamp), style: .date).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(20)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
    }

    private func reload() async {
        guard !loading, !saving, let id = artist.id else { return }
        let operation = generation
        loading = true; error = nil
        defer { if operation == generation { loading = false } }
        // Count errors remain visible; a failed read must not silently become 0.
        do {
            async let countValue = session.fetchArtistCandleCount(id)
            async let pageValue = session.fetchArtistCandles(id, page: 1)
            let (newCount, firstPage) = try await (countValue, pageValue)
            guard operation == generation, !Task.isCancelled else { return }
            count = newCount; candles = unique(firstPage.items); nextPage = 2
            hasMore = firstPage.totalPages.map { $0 > 1 } ?? (firstPage.items.count == 20)
        } catch is CancellationError {} catch {
            guard operation == generation else { return }
            self.error = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !loading, !saving, hasMore, let id = artist.id else { return }
        let operation = generation
        loading = true; error = nil
        defer { if operation == generation { loading = false } }
        do {
            let page = try await session.fetchArtistCandles(id, page: nextPage)
            guard operation == generation, !Task.isCancelled else { return }
            candles = unique(candles + page.items)
            hasMore = page.totalPages.map { nextPage < $0 } ?? (page.items.count == 20)
            nextPage += 1
        } catch is CancellationError {} catch {
            guard operation == generation else { return }
            self.error = error.localizedDescription
        }
    }

    private func unique(_ values: [LaneArtistCandle]) -> [LaneArtistCandle] {
        var seen = Set<String>()
        return values.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    }

    private func submit() {
        guard !saving, !loading, LaneCandleText.isValid(message), let id = artist.id else { return }
        saving = true; error = nil
        messageFocused = false
        let operation = generation
        let text = message
        Task {
            defer { if operation == generation { saving = false } }
            do {
                let value = try await session.placeArtistCandle(id, text: text)
                guard operation == generation else { return }
                ownCandle = value; composing = false; candles = unique([value] + candles)
                if let previous = count { count = previous + 1 }
                // POST returns a real server candle. A count/read failure does
                // not undo that confirmation or trigger another POST.
                do {
                    let confirmed = try await session.fetchArtistCandleCount(id)
                    guard operation == generation else { return }
                    count = confirmed
                } catch is CancellationError {} catch {
                    guard operation == generation else { return }
                    self.error = "Candle saved. Could not refresh the count: " + error.localizedDescription
                }
            } catch is CancellationError {} catch {
                guard operation == generation else { return }
                self.error = error.localizedDescription
            }
        }
    }
}
