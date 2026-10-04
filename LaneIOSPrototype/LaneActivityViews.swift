import SwiftUI
import SafariServices

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
    @Environment(\.scenePhase) private var phase
    @State private var pricing: LanePricing?
    @State private var loading = false
    @State private var cancelling = false
    @State private var confirmCancellation = false
    @State private var cancelled = false
    @State private var error: String?
    @State private var selectedPlan: LanePremiumPlan = .yearly
    @State private var confirmCheckout = false
    @State private var checkoutIdentity = ""
    @State private var checkout: LanePremiumCheckout?
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
                    plan(.monthly, pricing.monthly)
                    plan(.yearly, pricing.yearly)
                    plan(.lifetime, pricing.lifetime)
                    Button("Continue to Lane checkout") {
                        checkoutIdentity = session.token
                        confirmCheckout = true
                    }.disabled(session.isGuest || cancelling || loading).accessibilityIdentifier("premium.checkout")
                    Text("Payment opens on Lane's official website, using your Lane sign-in. No purchase is made until you confirm it there.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error {
                Text(error).foregroundStyle(.red).accessibilityIdentifier("premium.error")
                Button("Try again") { Task { await load() } }.accessibilityIdentifier("premium.retry")
            }
            Section("Subscription") {
                Text(session.account?.isAutoRenewalActive.map { $0 ? "Auto-renewal is on" : "Auto-renewal is off" } ?? "Auto-renewal status is not available")
                    .accessibilityIdentifier("premium.renewal")
                if session.account?.isAutoRenewalActive == true {
                    Button(cancelling ? "Cancelling…" : "Cancel auto-renewal", role: .destructive) { confirmCancellation = true }
                        .disabled(cancelling).accessibilityIdentifier("premium.cancel")
                }
                if cancelled { Text("Cancellation confirmed by Lane").accessibilityIdentifier("premium.cancelled") }
                Button("Refresh subscription") { Task { await load() }; session.refreshAccount() }.disabled(cancelling)
                Text("Closing checkout does not confirm payment. Premium is active only after Lane updates your account.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Lane Premium").navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark).laneIOSBackSwipe()
        .task { await load(); session.refreshAccount() }
        .onChange(of: session.token) { _ in
            checkout = nil; confirmCheckout = false; checkoutIdentity = ""; pricing = nil
            error = "Lane sign-in changed. Refresh the plans before continuing."
        }
        .onChange(of: phase) { value in
            if value == .active { session.refreshAccount() }
        }
        .sheet(item: $checkout, onDismiss: {
            checkoutIdentity = ""
            session.refreshAccount()
        }) { item in LanePremiumBrowser(url: item.url) }
        .confirmationDialog(confirmCheckout ? "Open Lane's \(selectedPlan.label.lowercased()) checkout?" : "Cancel Lane auto-renewal?",
            isPresented: Binding(get: { confirmCheckout || confirmCancellation }, set: { if !$0 { confirmCheckout = false; confirmCancellation = false } }), titleVisibility: .visible) {
            if confirmCheckout {
                Button("Continue to checkout") { openCheckout() }.accessibilityIdentifier("premium.confirmCheckout")
                Button("Cancel", role: .cancel) { checkoutIdentity = "" }
            } else {
                Button("Cancel auto-renewal", role: .destructive) {
                    cancelling = true; error = nil
                    Task {
                        defer { cancelling = false }
                        do { try await session.cancelSubscriptionConfirmed(); cancelled = true }
                        catch { self.error = error.localizedDescription }
                    }
                }.accessibilityIdentifier("premium.confirmCancellation")
            }
        } message: {
            Text(confirmCheckout ? "Lane's checkout receives your Lane sign-in. Confirm the price and purchase on that page; you can close it without paying." : "Your current paid period remains active. No purchase will be made.")
        }
    }
    private func plan(_ plan: LanePremiumPlan, _ value: LanePricePlan) -> some View {
        Button { selectedPlan = plan } label: {
            HStack {
                Image(systemName: selectedPlan == plan ? "checkmark.circle.fill" : "circle")
                VStack(alignment: .leading) { Text(plan.label); Text(value.periodName).font(.caption).foregroundStyle(.secondary) }
                Spacer(); Text(value.displayPrice)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("premium.plan.\(plan.label)")
            .accessibilityAddTraits(selectedPlan == plan ? .isSelected : [])
    }
    private func openCheckout() {
        guard let pricing, session.token == checkoutIdentity else { checkoutIdentity = ""; return }
        defer { checkoutIdentity = "" }
        do {
            let url = try pricing.checkoutURL(plan: selectedPlan, token: session.token)
            #if DEBUG
            // Automation must never send even a fixture token to a real
            // payment page, nor accidentally create a real checkout session.
            if ProcessInfo.processInfo.arguments.contains("--lane-ui-test") {
                throw LaneAPIError.decoding("Automated tests do not open payment pages.")
            }
            #endif
            checkout = LanePremiumCheckout(url: url)
        } catch { self.error = error.localizedDescription }
    }
    private func load() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do { pricing = try await session.fetchPricing() }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

private struct LanePremiumCheckout: Identifiable { let id = UUID(); let url: URL }
private struct LanePremiumBrowser: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let finish: () -> Void
        init(finish: @escaping () -> Void) { self.finish = finish }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { finish() }
    }
}
