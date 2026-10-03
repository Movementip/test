import Foundation
import CryptoKit
import Network
import Security
import SwiftUI
import UIKit
import ImageIO

/// Mirrors the Android client's fast-DNS idea for networks where the system
/// resolver is filtered. Normal URLSession remains the primary transport; this
/// client is only used after it fails and keeps TLS verification pinned to the
/// original hostname while connecting to an address returned by DNS-over-HTTPS.
enum AndroidNetworkTransport {
    struct Response {
        let data: Data
        let response: HTTPURLResponse
    }

    private actor DNSCache {
        static let shared = DNSCache()

        private var values: [String: (expires: Date, addresses: [String])] = [:]

        func addresses(for host: String) -> [String]? {
            guard let entry = values[host], entry.expires > Date() else {
                values.removeValue(forKey: host)
                return nil
            }
            return entry.addresses
        }

        func store(_ addresses: [String], for host: String) {
            values[host] = (Date().addingTimeInterval(300), addresses)
        }
    }

    static func data(for request: URLRequest, timeout: TimeInterval = 12, maximumResponseBytes: Int? = nil) async throws -> Response {
        try Task.checkCancellation()
        guard let url = request.url,
              url.scheme?.lowercased() == "https",
              let host = url.host else {
            throw URLError(.badURL)
        }

        let addresses = try await resolve(host: host)
        try Task.checkCancellation()
        var lastError: Error = URLError(.cannotFindHost)
        let isBNITSigned = request.value(forHTTPHeaderField: "X-Core-Token") != nil
        let attemptAddresses = isBNITSigned ? Array(addresses.prefix(1)) : addresses

        // A BNIT signature is single-use. If an edge receives the request but
        // the response is lost, sending the same bytes to another resolved IP
        // triggers REPLAY_ATTACK_DETECTED. Safe API retries are re-signed by
        // LaneAPI instead; mutations remain single-shot.
        for address in attemptAddresses {
            try Task.checkCancellation()
            do {
                return try await DirectHTTPSOperation.run(
                    request: request,
                    originalHost: host,
                    address: address,
                    timeout: timeout,
                    maximumResponseBytes: maximumResponseBytes
                )
            } catch {
                try Task.checkCancellation()
                lastError = error
            }
        }

        throw lastError
    }

    static func imageData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("LaneMusic/1.0 (Android; Mobile)", forHTTPHeaderField: "User-Agent")

        // Prefer URLSession so image loads reuse the system HTTP/2/TLS pool.
        // The previous direct-first path opened a fresh NWConnection for each
        // artwork and made artist/album grids visibly slower.
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  !data.isEmpty else {
                throw URLError(.badServerResponse)
            }
            return data
        } catch {
            try Task.checkCancellation()
            let direct = try await data(for: request, timeout: 5)
            guard (200..<300).contains(direct.response.statusCode),
                  !direct.data.isEmpty else {
                throw URLError(.badServerResponse)
            }
            return direct.data
        }
    }

    #if DEBUG
    static func debugResolvedAddresses(host: String,
        fetch: @escaping (URLRequest) async throws -> (Data, URLResponse)) async throws -> [String] {
        try await resolve(host: host, fetch: fetch)
    }
    #endif

    private static func resolve(host: String,
        fetch: @escaping (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }) async throws -> [String] {
        if IPv4Address(host) != nil || IPv6Address(host) != nil {
            return [host]
        }

        if let cached = await DNSCache.shared.addresses(for: host), !cached.isEmpty {
            return cached
        }

        let encodedHost = host.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? host
        let endpoints = [
            "https://1.1.1.1/dns-query?name=\(encodedHost)&type=A",
            "https://8.8.8.8/resolve?name=\(encodedHost)&type=A",
            "https://dns.google/resolve?name=\(encodedHost)&type=A"
        ]

        var resolved: [String] = []
        await withTaskGroup(of: [String].self) { group in
            for endpoint in endpoints {
                group.addTask {
                    guard let url = URL(string: endpoint) else { return [] }
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 4
                    request.setValue("application/dns-json", forHTTPHeaderField: "Accept")

                    guard let (data, response) = try? await fetch(request),
                          let http = response as? HTTPURLResponse,
                          (200..<300).contains(http.statusCode),
                          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let answers = object["Answer"] as? [[String: Any]] else {
                        return []
                    }

                    return answers.compactMap { answer in
                        guard (answer["type"] as? Int) == 1,
                              let value = answer["data"] as? String,
                              IPv4Address(value) != nil else { return nil }
                        return value
                    }
                }
            }

            for await values in group where !values.isEmpty {
                // The successful resolver already returned all of its usable
                // addresses. Do not delay TLS by waiting four seconds for an
                // unreachable alternative; preserve SNI/certificate checks.
                var seen = Set<String>()
                resolved = values.filter { seen.insert($0).inserted }
                group.cancelAll()
                break
            }
        }

        try Task.checkCancellation()
        // The RU edge is a dedicated Yandex Cloud address in the APK's current
        // server configuration. Keep it only as a last resort when every DoH
        // provider is blocked; normal DNS-over-HTTPS results always win.
        if resolved.isEmpty {
            switch host {
            case "ru.laneapi.com":
                resolved = ["158.160.143.196"]
            case "laneapi.com", "cdn.laneapi.com":
                resolved = ["104.21.55.74", "172.67.170.188"]
            default:
                break
            }
        }

        guard !resolved.isEmpty else { throw URLError(.cannotFindHost) }
        await DNSCache.shared.store(resolved, for: host)
        return resolved
    }
}

private final class DirectHTTPSOperation {
    private let request: URLRequest
    private let originalHost: String
    private let address: String
    private let timeout: TimeInterval
    private let maximumResponseBytes: Int?
    private let queue = DispatchQueue(label: "lane.android-dns.transport", qos: .userInitiated)
    private let lock = NSLock()

    private var connection: NWConnection?
    private var continuation: CheckedContinuation<AndroidNetworkTransport.Response, Error>?
    private var received = Data()
    private var finished = false

    private init(request: URLRequest, originalHost: String, address: String, timeout: TimeInterval, maximumResponseBytes: Int?) {
        self.request = request
        self.originalHost = originalHost
        self.address = address
        self.timeout = timeout
        self.maximumResponseBytes = maximumResponseBytes
    }

    static func run(
        request: URLRequest,
        originalHost: String,
        address: String,
        timeout: TimeInterval,
        maximumResponseBytes: Int? = nil
    ) async throws -> AndroidNetworkTransport.Response {
        let operation = DirectHTTPSOperation(
            request: request,
            originalHost: originalHost,
            address: address,
            timeout: timeout,
            maximumResponseBytes: maximumResponseBytes
        )
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await operation.start()
        } onCancel: {
            operation.queue.async { operation.finish(.failure(CancellationError())) }
        }
    }

    private func start() async throws -> AndroidNetworkTransport.Response {
        try await withCheckedThrowingContinuation { continuation in
            // Start and cancellation share a queue. Cancellation before this
            // continuation is installed must still resume it exactly once.
            queue.async {
            guard !self.finished else { continuation.resume(throwing: CancellationError()); return }
            self.continuation = continuation

            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, self.originalHost)
            sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")

            let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
            let port = NWEndpoint.Port(rawValue: UInt16(self.request.url?.port ?? 443)) ?? .https
            let connection = NWConnection(host: NWEndpoint.Host(self.address), port: port, using: parameters)
            self.connection = connection

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.sendRequest()
                case .failed(let error):
                    self.finish(.failure(error))
                case .cancelled:
                    self.finish(.failure(URLError(.cancelled)))
                default:
                    break
                }
            }

            self.queue.asyncAfter(deadline: .now() + self.timeout) { [weak self] in
                self?.finish(.failure(URLError(.timedOut)))
            }
            connection.start(queue: self.queue)
            }
        }
    }

    private func sendRequest() {
        guard let connection else { return }
        do {
            let payload = try makeHTTPRequest()
            connection.send(content: payload, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if let error {
                    self.finish(.failure(error))
                } else {
                    self.receiveNext()
                }
            })
        } catch {
            finish(.failure(error))
        }
    }

    private func receiveNext() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                // A CDN that ignores Range must not turn the streaming bridge
                // into an unbounded in-memory whole-file download.
                if let limit = self.maximumResponseBytes, data.count > limit - self.received.count {
                    self.finish(.failure(URLError(.dataLengthExceedsMaximum)))
                    return
                }
                self.received.append(data)
            }
            if let error {
                self.finish(.failure(error))
                return
            }
            if isComplete {
                do {
                    self.finish(.success(try self.parseHTTPResponse()))
                } catch {
                    self.finish(.failure(error))
                }
            } else {
                self.receiveNext()
            }
        }
    }

    private func makeHTTPRequest() throws -> Data {
        guard let url = request.url else { throw URLError(.badURL) }
        let method = request.httpMethod ?? "GET"
        var target = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty {
            target += "?\(query)"
        }

        var headers = request.allHTTPHeaderFields ?? [:]
        headers["Host"] = originalHost
        headers["Connection"] = "close"
        headers["Accept-Encoding"] = "identity"
        if let body = request.httpBody {
            headers["Content-Length"] = String(body.count)
        }

        var text = "\(method) \(target) HTTP/1.1\r\n"
        for key in headers.keys.sorted() {
            if let value = headers[key] {
                text += "\(key): \(value)\r\n"
            }
        }
        text += "\r\n"

        var data = Data(text.utf8)
        if let body = request.httpBody {
            data.append(body)
        }
        return data
    }

    private func parseHTTPResponse() throws -> AndroidNetworkTransport.Response {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let range = received.range(of: delimiter),
              let headerText = String(data: received[..<range.lowerBound], encoding: .isoLatin1) else {
            throw URLError(.badServerResponse)
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { throw URLError(.badServerResponse) }
        let statusParts = statusLine.split(separator: " ", maxSplits: 2)
        guard statusParts.count >= 2, let status = Int(statusParts[1]) else {
            throw URLError(.badServerResponse)
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        var body = Data(received[range.upperBound...])
        if headers.first(where: { $0.key.caseInsensitiveCompare("Transfer-Encoding") == .orderedSame })?
            .value.localizedCaseInsensitiveContains("chunked") == true {
            body = try decodeChunked(body)
        }

        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
              ) else {
            throw URLError(.badServerResponse)
        }
        return AndroidNetworkTransport.Response(data: body, response: response)
    }

    private func decodeChunked(_ input: Data) throws -> Data {
        var output = Data()
        var cursor = input.startIndex

        while cursor < input.endIndex {
            guard let lineEnd = input[cursor...].range(of: Data("\r\n".utf8)) else {
                throw URLError(.cannotDecodeContentData)
            }
            guard let sizeLine = String(data: input[cursor..<lineEnd.lowerBound], encoding: .ascii),
                  let sizeToken = sizeLine.split(separator: ";", maxSplits: 1).first,
                  let size = Int(sizeToken.trimmingCharacters(in: .whitespaces), radix: 16) else {
                throw URLError(.cannotDecodeContentData)
            }
            cursor = lineEnd.upperBound
            if size == 0 { break }

            guard let end = input.index(cursor, offsetBy: size, limitedBy: input.endIndex),
                  end <= input.endIndex else {
                throw URLError(.cannotDecodeContentData)
            }
            output.append(input[cursor..<end])
            cursor = end

            guard input.distance(from: cursor, to: input.endIndex) >= 2 else {
                throw URLError(.cannotDecodeContentData)
            }
            cursor = input.index(cursor, offsetBy: 2)
        }
        return output
    }

    private func finish(_ result: Result<AndroidNetworkTransport.Response, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        connection?.stateUpdateHandler = nil
        connection?.cancel()
        continuation?.resume(with: result)
    }
}

private let laneRussianMediaZones: Set<String> = [
    "Europe/Kaliningrad", "Europe/Moscow", "Europe/Simferopol", "Europe/Kirov",
    "Europe/Astrakhan", "Europe/Volgograd", "Europe/Saratov", "Europe/Ulyanovsk",
    "Europe/Samara", "Asia/Yekaterinburg", "Asia/Omsk", "Asia/Novosibirsk",
    "Asia/Barnaul", "Asia/Tomsk", "Asia/Novokuznetsk", "Asia/Krasnoyarsk",
    "Asia/Irkutsk", "Asia/Chita", "Asia/Yakutsk", "Asia/Khandyga",
    "Asia/Vladivostok", "Asia/Ust-Nera", "Asia/Magadan", "Asia/Sakhalin",
    "Asia/Srednekolymsk", "Asia/Kamchatka", "Asia/Anadyr"
]

/// Exact CdnUrlInterceptor rewrite recovered from Lane Android 1.4.7,
/// independent of the current diagnostics preference.
func laneAPKMediaURL(_ rawValue: String?) -> URL? {
    guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else { return nil }

    guard laneRussianMediaZones.contains(TimeZone.current.identifier) else {
        return URL(string: value)
    }

    let regionalCDN = "https://ru.laneapi.com/cdn"
    value = value.replacingOccurrences(of: "https://cdn.laneapi.com", with: regionalCDN)

    if let url = URL(string: value),
       url.host?.localizedCaseInsensitiveContains("sndcdn.com") == true,
       !url.lastPathComponent.isEmpty {
        value = "\(regionalCDN)/soundcloud/\(url.lastPathComponent)"
    }

    return URL(string: value)
}

/// Applies the currently selected media route. The app can switch between the
/// original Lane URL and the APK regional rewrite at runtime.
func laneRoutedMediaURL(_ rawValue: String?) -> URL? {
    guard let clean = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
          !clean.isEmpty else { return nil }

    let mediaRoute = UserDefaults.standard.string(forKey: "lane.diag.mediaRoute") ?? "original"
    if mediaRoute == "apk" {
        return laneAPKMediaURL(clean)
    }
    return URL(string: clean)
}

private final class LaneImageMemoryCache {
    static let shared = LaneImageMemoryCache()
    private let images = NSCache<NSString, UIImage>()
    private let gifs = NSCache<NSString, NSData>()

    private init() {
        images.totalCostLimit = 64 * 1024 * 1024
        gifs.totalCostLimit = 16 * 1024 * 1024
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [weak self] _ in
            self?.images.removeAllObjects()
            self?.gifs.removeAllObjects()
        }
    }

    func image(for key: String) -> UIImage? {
        images.object(forKey: key as NSString)
    }
    func gif(for key: String) -> Data? { gifs.object(forKey: key as NSString).map { $0 as Data } }
    func storeGIF(_ data: Data, for key: String) {
        if data.starts(with: Data("GIF8".utf8)), data.count <= 8 * 1024 * 1024 {
            gifs.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        }
    }

    func store(_ image: UIImage, for key: String) {
        let decodedBytes = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        images.setObject(image, forKey: key as NSString, cost: decodedBytes)
    }
}

/// Covers are displayed at iPhone resolution, not the server's original
/// poster resolution. Decode on a worker queue and bound the decoded surface
/// before inserting it in the cache (including the first frame of a GIF).
func laneDecodeArtwork(_ data: Data, maximumPixels: Int = 1280) async -> UIImage? {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let frame = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: min(1280, max(128, maximumPixels)),
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { continuation.resume(returning: nil); return }
            continuation.resume(returning: UIImage(cgImage: frame))
        }
    }
}

private actor LaneImageDiskCache {
    static let shared = LaneImageDiskCache()
    private let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LaneArtwork", isDirectory: true)
    private var writesSinceTrim = 0

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appendingPathComponent(digest).appendingPathExtension("img")
    }

    func data(for key: String) -> Data? {
        try? Data(contentsOf: fileURL(for: key))
    }

    func store(_ data: Data, for key: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL(for: key), options: .atomic)
            writesSinceTrim += 1
            if writesSinceTrim >= 32 {
                writesSinceTrim = 0
                trim()
            }
        } catch {
            // Artwork is optional; a full or unavailable cache must not block playback.
        }
    }

    private func trim() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        var total = 0
        let entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
                return nil
            }
            let size = values.fileSize ?? 0
            total += size
            return (url, size, values.contentModificationDate ?? .distantPast)
        }
        guard total > 200 * 1024 * 1024 else { return }
        for (url, size, _) in entries.sorted(by: { $0.2 < $1.2 }) {
            try? FileManager.default.removeItem(at: url)
            total -= size
            if total <= 160 * 1024 * 1024 { break }
        }
    }
}

@MainActor
final class LaneRemoteImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var gifData: Data?
    private(set) var loadedValue: String?
    private var loadedPixels: Int?

    func load(_ rawValue: String?, maximumPixels: Int = 1280) async {
        guard let url = laneRoutedMediaURL(rawValue) else { return }
        let key = url.absoluteString
        let imageKey = "\(key)#pixels=\(maximumPixels)"
        if let cached = LaneImageMemoryCache.shared.image(for: imageKey) {
            guard !Task.isCancelled else { return }
            image = cached
            gifData = LaneImageMemoryCache.shared.gif(for: key)
            if gifData == nil, let data = await LaneImageDiskCache.shared.data(for: key), !Task.isCancelled {
                LaneImageMemoryCache.shared.storeGIF(data, for: key)
                gifData = LaneImageMemoryCache.shared.gif(for: key)
            }
            guard !Task.isCancelled else { return }
            loadedValue = rawValue
            loadedPixels = maximumPixels
            return
        }
        guard rawValue != loadedValue || maximumPixels != loadedPixels else { return }
        if image != nil { image = nil }; gifData = nil

        if let diskData = await LaneImageDiskCache.shared.data(for: key),
           !Task.isCancelled,
           let decoded = await laneDecodeArtwork(diskData, maximumPixels: maximumPixels), !Task.isCancelled {
            LaneImageMemoryCache.shared.store(decoded, for: imageKey)
            LaneImageMemoryCache.shared.storeGIF(diskData, for: key)
            gifData = LaneImageMemoryCache.shared.gif(for: key)
            image = decoded
            loadedValue = rawValue
            loadedPixels = maximumPixels
            return
        }

        guard !Task.isCancelled,
              let data = try? await AndroidNetworkTransport.imageData(from: url),
              !Task.isCancelled,
              let decoded = await laneDecodeArtwork(data, maximumPixels: maximumPixels), !Task.isCancelled else { return }
        LaneImageMemoryCache.shared.store(decoded, for: imageKey)
        LaneImageMemoryCache.shared.storeGIF(data, for: key)
        gifData = LaneImageMemoryCache.shared.gif(for: key)
        image = decoded
        loadedValue = rawValue
        loadedPixels = maximumPixels
        await LaneImageDiskCache.shared.store(data, for: key)
    }
}

/// AsyncImage-compatible view that applies the APK CDN rewrite first and then
/// uses the Android-style DNS fallback when iOS cannot reach that hostname.
struct LaneResilientImage<Placeholder: View>: View {
    let url: String?
    var contentMode: ContentMode = .fill
    private let placeholder: () -> Placeholder

    @StateObject private var loader = LaneRemoteImageLoader()
    @State private var maximumPixels = 1280

    init(
        url: String?,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = url.flatMap({ laneRoutedMediaURL($0)?.absoluteString })
                .flatMap({ LaneImageMemoryCache.shared.image(for: "\($0)#pixels=\(maximumPixels)") })
                ?? (loader.loadedValue == url ? loader.image : nil) {
                if loader.loadedValue == url, let data = loader.gifData {
                    LaneAnimatedImage(data: data, contentMode: contentMode, maximumPixels: maximumPixels)
                        .aspectRatio(image.size.width / max(1, image.size.height), contentMode: contentMode)
                } else {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                }
            } else {
                placeholder()
            }
        }
        .background(GeometryReader { proxy in
            Color.clear.onAppear { updateResolution(proxy.size) }.onChange(of: proxy.size) { updateResolution($0) }
        })
        .task(id: "\(url ?? "")|\(maximumPixels)") {
            await loader.load(url, maximumPixels: maximumPixels)
        }
    }
    private func updateResolution(_ size: CGSize) {
        let pixels = max(size.width, size.height) * UIScreen.main.scale
        guard pixels.isFinite, pixels > 0 else { return }
        maximumPixels = [192, 384, 768, 1280].first(where: { CGFloat($0) >= pixels }) ?? 1280
    }
}
