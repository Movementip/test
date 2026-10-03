import SwiftUI

struct LaneFriendActivityScreen: View {
    @EnvironmentObject private var session: LaneSession
    @Environment(\.scenePhase) private var phase
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.red).accessibilityIdentifier("activity.error")
                Button("Try again") { Task { await refresh() } }.accessibilityIdentifier("activity.retry")
            }
            if loading { ProgressView("Loading activity…") }
            if session.isGuest { Text("Sign in to see friend activity.") }
            else if session.friendActivity.isEmpty, !loading, error == nil { Text("No friend activity yet.") }
            ForEach(session.friendActivity) { friend in
                VStack(alignment: .leading, spacing: 12) {
                    NavigationLink { LaneUserProfileScreen(laneID: friend.laneId) } label: {
                        HStack {
                            APKRemoteImage(url: friend.avatarUrl, circle: true).frame(width: 42, height: 42)
                            Text(friend.displayedName ?? friend.userName ?? "Lane user").font(LaneTypography.title(16))
                            Spacer()
                            Circle().fill(friend.isOnline == true ? Color.green : Color.gray).frame(width: 8, height: 8)
                                .accessibilityLabel(friend.isOnline == true ? "Online" : "Offline")
                        }
                    }.accessibilityIdentifier("activity.profile.\(friend.laneId)")
                    if let id = friend.trackId, !id.isEmpty {
                        Button {
                            let track = TrackCandidate(id: id, title: friend.trackTitle ?? "Lane track",
                                subtitle: friend.trackArtist ?? "", trackID: id, coverURL: friend.coverUrl)
                            session.startPlayback(track, in: [track])
                        } label: {
                            HStack {
                                APKRemoteImage(url: friend.coverUrl, cornerRadius: 8).frame(width: 46, height: 46)
                                VStack(alignment: .leading) {
                                    Text(friend.trackTitle ?? "Lane track")
                                    Text(friend.trackArtist ?? "").font(.caption).foregroundStyle(.secondary)
                                    Text(friend.isPaused == false ? "Listening now" : "Paused").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: "play.fill")
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("activity.track.\(friend.laneId)")
                    }
                }.padding(.vertical, 8)
            }
        }
        .navigationTitle("Friend activity").navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark).laneIOSBackSwipe()
        .refreshable { await refresh() }
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            }
        }
    }
    private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do { _ = try await session.fetchFriendActivity(); error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct LanePremiumScreen: View {
    @EnvironmentObject private var session: LaneSession
    @State private var pricing: LanePricing?
    @State private var loading = false
    @State private var cancelling = false
    @State private var confirmCancellation = false
    @State private var cancelled = false
    @State private var error: String?
    var body: some View {
        List {
            Section {
                APKBundleImage(name: "lane_pro_banner").frame(maxWidth: .infinity).frame(height: 90)
                Text("Lane Premium").font(LaneTypography.title(24))
                Text(session.hasPremiumAccess ? "Premium is active" : "Basic account")
                    .accessibilityIdentifier("premium.status")
                if let expiry = session.account?.premiumExpiresIn, expiry > 0 {
                    Text(Date(timeIntervalSince1970: Double(expiry > 10_000_000_000 ? expiry / 1000 : expiry)), style: .date)
                }
                Text("High and Ultra audio quality · Speed Up and Slowed effects")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if loading { ProgressView("Loading prices…") }
            if let pricing {
                Section("Plans · \(pricing.countryCode)") {
                    plan("Monthly", pricing.monthly)
                    plan("Yearly", pricing.yearly)
                    plan("Lifetime", pricing.lifetime)
                }
            }
            if let error {
                Text(error).foregroundStyle(.red).accessibilityIdentifier("premium.error")
                Button("Try again") { Task { await load() } }.accessibilityIdentifier("premium.retry")
            }
            Section("Subscription") {
                Text(session.account?.isAutoRenewalActive == true ? "Auto-renewal is on" : "Auto-renewal is off")
                    .accessibilityIdentifier("premium.renewal")
                if session.account?.isAutoRenewalActive == true {
                    Button(cancelling ? "Cancelling…" : "Cancel auto-renewal", role: .destructive) { confirmCancellation = true }
                        .disabled(cancelling).accessibilityIdentifier("premium.cancel")
                }
                if cancelled { Text("Cancellation confirmed by Lane").accessibilityIdentifier("premium.cancelled") }
                Button("Refresh subscription") { Task { await load() }; session.refreshAccount() }.disabled(cancelling)
                Text("Prices come from Lane. This iOS build does not take payments; your existing Lane subscription works after sign-in.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Lane Premium").navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark).laneIOSBackSwipe()
        .task { await load(); session.refreshAccount() }
        .confirmationDialog("Cancel Lane auto-renewal?", isPresented: $confirmCancellation, titleVisibility: .visible) {
            Button("Cancel auto-renewal", role: .destructive) {
                cancelling = true; error = nil
                Task {
                    defer { cancelling = false }
                    do { try await session.cancelSubscriptionConfirmed(); cancelled = true }
                    catch { self.error = error.localizedDescription }
                }
            }
        } message: { Text("Your current paid period remains active. No purchase will be made.") }
    }
    private func plan(_ label: String, _ value: LanePricePlan) -> some View {
        HStack { VStack(alignment: .leading) { Text(label); Text(value.periodName).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(value.displayPrice) }
            .accessibilityIdentifier("premium.plan.\(label)")
    }
    private func load() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do { pricing = try await session.fetchPricing() }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}
