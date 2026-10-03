import SwiftUI
import WebKit

struct LaneYandexAccountImportScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = LaneYandexAccountBrowser()
    @State private var confirmSignOut = false
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }.accessibilityIdentifier("yandex.close").accessibilityLabel("Close Yandex sign-in")
                VStack(spacing: 2) {
                    Text("Yandex Music").font(.headline)
                    Text(browser.visibleHost).font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
                Button { confirmSignOut = true } label: {
                    Image(systemName: "person.crop.circle.badge.xmark").frame(width: 44, height: 44)
                }.accessibilityLabel("Switch Yandex account")
            }.padding(.horizontal, 8)
            HStack {
                Button("Back") { browser.goBack() }.disabled(!browser.canGoBack)
                Spacer()
                Button("My collection") { browser.openCollection() }
                    .accessibilityIdentifier("yandex.collection")
                Button { browser.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Reload Yandex page")
            }.font(.subheadline).padding(.horizontal, 16).padding(.bottom, 10)
            if browser.loading { ProgressView().frame(maxWidth: .infinity).padding(4) }
            if let error = browser.error {
                Text(error).font(.caption).foregroundStyle(.pink).padding(12)
                    .accessibilityIdentifier("yandex.error")
            }
            LaneYandexWebView(browser: browser).frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 10) {
                Text(browser.playlistID == nil
                     ? "Sign in and open your collection. Your password stays on the Yandex page."
                     : "Your favorite playlist is ready. Only its identifier is sent to Lane, not your password or cookies.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Import favorite tracks") {
                    guard let id = browser.playlistID else { return }
                    onSelect(id)
                }.buttonStyle(.borderedProminent).tint(.pink)
                    .disabled(browser.playlistID == nil)
                    .accessibilityIdentifier("yandex.continue")
            }.frame(maxWidth: .infinity).padding(16)
        }
        .background(Color.black).foregroundStyle(.white).preferredColorScheme(.dark)
        .alert("Switch Yandex account?", isPresented: $confirmSignOut) {
            Button("Sign out of Yandex", role: .destructive) { browser.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes Yandex website data from Lane's browser. Your Lane account and imported songs stay unchanged.")
        }
        .onDisappear { browser.close() }
    }
}

private struct LaneYandexWebView: UIViewRepresentable {
    let browser: LaneYandexAccountBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

/// WKWebView owns sign-in cookies. Native code reads only one approved playlist
/// anchor, in the top-level music.yandex.ru collection, just like the APK.
@MainActor
private final class LaneYandexAccountBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    @Published var playlistID: String?
    @Published var visibleHost = "passport.yandex.ru"
    @Published var loading = true
    @Published var canGoBack = false
    @Published var error: String?
    let webView: WKWebView
    private var closed = false
    private let messageName = "laneYandexPlaylist"
    private let fixture: Bool

    override init() {
        let configuration = WKWebViewConfiguration()
        #if DEBUG
        fixture = ProcessInfo.processInfo.arguments.contains("--lane-yandex-account-fixture")
        if fixture {
            configuration.websiteDataStore = .nonPersistent()
        } else { configuration.websiteDataStore = .default() }
        #else
        fixture = false
        configuration.websiteDataStore = .default()
        #endif
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        configuration.userContentController.add(LaneWeakYandexScriptHandler(self), name: messageName)
        configuration.userContentController.addUserScript(WKUserScript(source: collectionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        loadLogin()
    }

    private var collectionScript: String {
        // No fetch interception, cookie access, password fields or tokens.
        // MutationObserver covers asynchronous/SPA collection rendering.
        let allowed = fixture ? "location.protocol === 'http:' && location.hostname === '127.0.0.1' && location.pathname === '/yandex-account-fixture'" : "location.protocol === 'https:' && location.hostname === 'music.yandex.ru' && (/^\\/collection(?:\\/|$)/.test(location.pathname) || /^\\/playlists\\/lk[.]/.test(location.pathname))"
        return """
        (() => {
          if (!(\(allowed)) || window.__laneYandexObserver) return;
          let last = '';
          function findPlaylist() {
            for (const anchor of document.querySelectorAll('a[href*="/playlists/lk."]')) {
              let url; try { url = new URL(anchor.getAttribute('href'), 'https://music.yandex.ru/collection'); } catch (_) { continue; }
              if (url.origin !== 'https://music.yandex.ru' || !/^\\/playlists\\/lk[.][A-Za-z0-9-]+$/.test(url.pathname)) continue;
              if (url.pathname !== last) {
                last = url.pathname;
                window.webkit.messageHandlers.laneYandexPlaylist.postMessage(url.href);
              }
              return;
            }
          }
          const observer = new MutationObserver(findPlaylist);
          observer.observe(document.documentElement, {childList:true, subtree:true, attributes:true, attributeFilter:['href']});
          window.__laneYandexObserver = observer;
          findPlaylist();
        })();
        """
    }

    private func loadLogin() {
        guard !closed else { return }
        playlistID = nil; error = nil
        #if DEBUG
        if fixture {
            Task { @MainActor [weak self] in
                for _ in 0..<40 {
                    guard let self, !self.closed else { return }
                    if let url = LaneUITestAudioServer.shared.yandexFixtureURL {
                        self.webView.load(URLRequest(url: url))
                        return
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                self?.loading = false
                self?.error = "The local Yandex fixture could not start."
            }
            return
        }
        #endif
        webView.load(URLRequest(url: YandexAccountImportSource.loginURL))
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !closed, message.name == messageName, message.frameInfo.isMainFrame,
              let href = message.body as? String,
              let id = YandexAccountImportSource.likedPlaylistID(from: href) else { return }
        let origin = message.frameInfo.securityOrigin
        var allowed = origin.protocol == "https" && origin.host == "music.yandex.ru" &&
            (origin.port == 0 || origin.port == 443) &&
            webView.url.map(YandexAccountImportSource.isCollectionOrigin) == true
        #if DEBUG
        if fixture, let expected = LaneUITestAudioServer.shared.yandexFixtureURL {
            allowed = origin.protocol == "http" && origin.host == "127.0.0.1" &&
                origin.port == expected.port && webView.url == expected
        }
        #endif
        guard allowed else { return }
        playlistID = id
    }

    func goBack() { if webView.canGoBack { webView.goBack() } }
    func reload() { error = nil; webView.reload() }
    func openCollection() {
        error = nil
        #if DEBUG
        if fixture { loadLogin(); return }
        #endif
        webView.load(URLRequest(url: YandexAccountImportSource.collectionURL))
    }

    func signOut() {
        playlistID = nil
        let store = webView.configuration.websiteDataStore
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { [weak self] records in
            let yandex = records.filter { record in
                let domain = record.displayName.lowercased()
                return domain == "yandex.ru" || domain.hasSuffix(".yandex.ru") ||
                    domain == "yandex.com" || domain.hasSuffix(".yandex.com")
            }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: yandex) { [weak self] in
                Task { @MainActor in self?.loadLogin() }
            }
        }
    }

    func close() {
        closed = true
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: messageName)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    func webView(_ view: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true; error = nil
        playlistID = nil
        visibleHost = view.url?.host ?? "passport.yandex.ru"
    }
    func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false; canGoBack = view.canGoBack
        visibleHost = view.url?.host ?? "passport.yandex.ru"
    }
    func webView(_ view: WKWebView, didFail navigation: WKNavigation!, withError failure: Error) { failed(failure) }
    func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError failure: Error) { failed(failure) }
    private func failed(_ failure: Error) {
        guard !closed, (failure as NSError).code != NSURLErrorCancelled else { return }
        loading = false
        error = "Yandex sign-in could not load. Check your connection and reload the page."
    }
    func webViewWebContentProcessDidTerminate(_ view: WKWebView) {
        playlistID = nil; loading = false
        error = "The Yandex page stopped. Reload it to continue."
    }
    func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        var allowed = url.scheme == "https" || url.absoluteString == "about:blank"
        #if DEBUG
        if fixture, url == LaneUITestAudioServer.shared.yandexFixtureURL { allowed = true }
        #endif
        // No certificate overrides, custom auth injection or automatic launch
        // of arbitrary URL schemes from an authentication page.
        decisionHandler(allowed ? .allow : .cancel)
    }
    func webView(_ view: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil, action.request.url?.scheme == "https" { view.load(action.request) }
        return nil
    }
}

private final class LaneWeakYandexScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?
    init(_ target: any WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

#if DEBUG
/// Exercises real WebKit against a loopback HTTP page, with delayed DOM
/// discovery and an untrusted subframe. Never included in Release.
enum LaneYandexFixturePage {
    static let html = """
        <html><meta name="viewport" content="width=device-width,initial-scale=1"><body style="background:#171717;color:white;font:20px sans-serif;padding:24px">
        <h2>Yandex sign-in fixture</h2>
        <a href="https://music.yandex.ru.evil.test/playlists/lk.spoof">Untrusted anchor</a>
        <iframe style="height:1px" srcdoc="&lt;script&gt;window.webkit.messageHandlers.laneYandexPlaylist.postMessage('https://music.yandex.ru/playlists/lk.iframe-spoof');&lt;/script&gt;"></iframe>
        <button style="font-size:22px;margin:24px" onclick="this.disabled=true;setTimeout(()=>{let a=document.createElement('a');a.href='https://music.yandex.ru/playlists/lk.fixture-account?ref_id=tracking';a.textContent='My favorite tracks';document.body.append(a)},1500)">Sign in fixture</button>
        </body></html>
        """
}
#endif
