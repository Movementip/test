import Foundation
import CryptoKit
import Network
import Security
import SwiftUI
import UIKit

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

    static func data(for request: URLRequest, timeout: TimeInterval = 12) async throws -> Response {
        guard let url = request.url,
              url.scheme?.lowercased() == "https",
              let host = url.host else {
            throw URLError(.badURL)
        }

        let addresses = try await resolve(host: host)
        var lastError: Error = URLError(.cannotFindHost)
        let isBNITSigned = request.value(forHTTPHeaderField: "X-Core-Token") != nil
        let attemptAddresses = isBNITSigned ? Array(addresses.prefix(1)) : addresses

        // A BNIT signature is single-use. If an edge receives the request but
        // the response is lost, sending the same bytes to another resolved IP
        // triggers REPLAY_ATTACK_DETECTED. Safe API retries are re-signed by
        // LaneAPI instead; mutations remain single-shot.
        for address in attemptAddresses {
            do {
                return try await DirectHTTPSOperation.run(
                    request: request,
                    originalHost: host,
                    address: address,
                    timeout: timeout
                )
            } catch {
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
            let direct = try await data(for: request, timeout: 5)
            guard (200..<300).contains(direct.response.statusCode),
                  !direct.data.isEmpty else {
                throw URLError(.badServerResponse)
            }
            return direct.data
        }
    }

    private static func resolve(host: String) async throws -> [String] {
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

                    guard let (data, response) = try? await URLSession.shared.data(for: request),
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
                for value in values where !resolved.contains(value) {
                    resolved.append(value)
                }
            }
        }

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
    private let queue = DispatchQueue(label: "lane.android-dns.transport")
    private let lock = NSLock()

    private var connection: NWConnection?
    private var continuation: CheckedContinuation<AndroidNetworkTransport.Response, Error>?
    private var received = Data()
    private var finished = false

    private init(request: URLRequest, originalHost: String, address: String, timeout: TimeInterval) {
        self.request = request
        self.originalHost = originalHost
        self.address = address
        self.timeout = timeout
    }

    static func run(
        request: URLRequest,
        originalHost: String,
        address: String,
        timeout: TimeInterval
    ) async throws -> AndroidNetworkTransport.Response {
        let operation = DirectHTTPSOperation(
            request: request,
            originalHost: originalHost,
            address: address,
            timeout: timeout
        )
        return try await operation.start()
    }

    private func start() async throws -> AndroidNetworkTransport.Response {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, originalHost)
            sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")

            let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
            let port = NWEndpoint.Port(rawValue: UInt16(request.url?.port ?? 443)) ?? .https
            let connection = NWConnection(host: NWEndpoint.Host(address), port: port, using: parameters)
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

            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(.failure(URLError(.timedOut)))
            }
            connection.start(queue: queue)
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

/// Exact CdnUrlInterceptor routing recovered from Lane Android 1.4.7.
func laneRoutedMediaURL(_ rawValue: String?) -> URL? {
    guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else { return nil }

    let russianZones: Set<String> = [
        "Europe/Kaliningrad", "Europe/Moscow", "Europe/Simferopol", "Europe/Kirov",
        "Europe/Astrakhan", "Europe/Volgograd", "Europe/Saratov", "Europe/Ulyanovsk",
        "Europe/Samara", "Asia/Yekaterinburg", "Asia/Omsk", "Asia/Novosibirsk",
        "Asia/Barnaul", "Asia/Tomsk", "Asia/Novokuznetsk", "Asia/Krasnoyarsk",
        "Asia/Irkutsk", "Asia/Chita", "Asia/Yakutsk", "Asia/Khandyga",
        "Asia/Vladivostok", "Asia/Ust-Nera", "Asia/Magadan", "Asia/Sakhalin",
        "Asia/Srednekolymsk", "Asia/Kamchatka", "Asia/Anadyr"
    ]

    guard russianZones.contains(TimeZone.current.identifier) else {
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

private final class LaneImageMemoryCache {
    static let shared = LaneImageMemoryCache()
    private let images = NSCache<NSString, UIImage>()

    private init() {
        images.totalCostLimit = 64 * 1024 * 1024
    }

    func image(for key: String) -> UIImage? {
        images.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, for key: String) {
        let decodedBytes = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        images.setObject(image, forKey: key as NSString, cost: decodedBytes)
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
    private(set) var loadedValue: String?

    func load(_ rawValue: String?) async {
        guard let url = laneRoutedMediaURL(rawValue) else { return }
        let key = url.absoluteString
        if let cached = LaneImageMemoryCache.shared.image(for: key) {
            image = cached
            loadedValue = rawValue
            return
        }
        guard rawValue != loadedValue else { return }
        if image != nil { image = nil }

        if let diskData = await LaneImageDiskCache.shared.data(for: key),
           !Task.isCancelled,
           let decoded = UIImage(data: diskData) {
            LaneImageMemoryCache.shared.store(decoded, for: key)
            image = decoded
            loadedValue = rawValue
            return
        }

        guard !Task.isCancelled,
              let data = try? await AndroidNetworkTransport.imageData(from: url),
              !Task.isCancelled,
              let decoded = UIImage(data: data) else { return }
        LaneImageMemoryCache.shared.store(decoded, for: key)
        image = decoded
        loadedValue = rawValue
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
                .flatMap({ LaneImageMemoryCache.shared.image(for: $0) })
                ?? (loader.loadedValue == url ? loader.image : nil) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loader.load(url)
        }
    }
}
