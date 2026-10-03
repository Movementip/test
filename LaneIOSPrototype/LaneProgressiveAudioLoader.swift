import Foundation
import AVFoundation
import UniformTypeIdentifiers

/// Range-based AVFoundation bridge for the existing no-VPN TLS transport.
/// Never requests the whole audio file up front. Each response is delivered
/// to AVPlayer before fetching the next 64 KiB; seeking cancels old requests.
final class LaneProgressiveAudioLoader: NSObject, AVAssetResourceLoaderDelegate {
    typealias Fetch = (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let remoteURL: URL
    private let fetch: Fetch
    private let queue = DispatchQueue(label: "lane.progressive.audio", qos: .userInitiated)
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var contentLength: Int64?
    private var contentType: String?
    static let chunkSize = LaneAudioHTTPRange.chunkSize

    init(url: URL, fetch: @escaping Fetch = { request in
        let result = try await AndroidNetworkTransport.data(for: request, timeout: 12,
            maximumResponseBytes: Int(LaneAudioHTTPRange.chunkSize) + 16_384)
        return (result.data, result.response)
    }) {
        remoteURL = url
        self.fetch = fetch
    }

    func makeAsset() -> AVURLAsset {
        var components = URLComponents()
        components.scheme = "lane-audio"
        components.host = UUID().uuidString
        components.path = "/stream.\(remoteURL.pathExtension.isEmpty ? "audio" : remoteURL.pathExtension)"
        let asset = AVURLAsset(url: components.url!)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return asset
    }

    func cancelAll() {
        queue.async { self.tasks.values.forEach { $0.cancel() }; self.tasks.removeAll() }
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard request.request.url?.scheme == "lane-audio" else { return false }
        let key = ObjectIdentifier(request)
        tasks[key] = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do { try await self.load(request) }
            catch {
                self.queue.async {
                    if !request.isCancelled { request.finishLoading(with: error) }
                }
            }
            self.queue.async { self.tasks.removeValue(forKey: key) }
        }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        tasks.removeValue(forKey: ObjectIdentifier(request))?.cancel()
    }

    private func load(_ loading: AVAssetResourceLoadingRequest) async throws {
        var finished = false
        while !finished {
            try Task.checkCancellation()
            let state: (offset: Int64, end: Int64?, total: Int64?, type: String?) = await onQueue {
                let data = loading.dataRequest
                let offset = max(data?.currentOffset ?? 0, data?.requestedOffset ?? 0)
                let end = data.flatMap { $0.requestsAllDataToEndOfResource ? nil : $0.requestedOffset + Int64($0.requestedLength) }
                return (offset, end, self.contentLength, self.contentType)
            }
            let remaining = state.end.map { max(1, $0 - state.offset) } ?? Self.chunkSize
            let count = min(remaining, Self.chunkSize, state.total.map { $0 - state.offset } ?? Self.chunkSize)
            if count <= 0 {
                await onQueue { if !loading.isCancelled { loading.finishLoading() } }
                return
            }
            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = 12
            request.setValue("bytes=\(state.offset)-\(state.offset + count - 1)", forHTTPHeaderField: "Range")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("LaneMusic/1.0 (Android; Mobile)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await fetch(request)
            try Task.checkCancellation()
            guard response.statusCode == 206, !data.isEmpty,
                  let header = response.value(forHTTPHeaderField: "Content-Range"),
                  let range = LaneAudioHTTPRange.parse(header), range.start == state.offset,
                  state.total == nil || state.total == range.total,
                  data.count == Int(range.end - range.start + 1) else {
                throw URLError(.badServerResponse)
            }
            let mime = response.mimeType ?? ""
            let type = state.type ?? Self.sniffType(data, offset: state.offset)
                ?? (mime.hasPrefix("audio/") || mime.hasPrefix("video/") ? UTType(mimeType: mime)?.identifier : nil)
                ?? UTType(filenameExtension: remoteURL.pathExtension)?.identifier
                ?? UTType.mp3.identifier
            finished = await onQueue {
                guard !loading.isCancelled else { return true }
                self.contentLength = range.total
                self.contentType = type
                if let information = loading.contentInformationRequest {
                    information.contentType = type
                    information.contentLength = range.total
                    information.isByteRangeAccessSupported = true
                }
                if let target = loading.dataRequest {
                    let end = min(state.end ?? range.total, range.total)
                    let length = min(Int(end - state.offset), data.count)
                    if length > 0 { target.respond(with: Data(data.prefix(length))) }
                    if target.currentOffset >= end { loading.finishLoading(); return true }
                    return false
                }
                loading.finishLoading()
                return true
            }
        }
    }

    private func onQueue<T>(_ action: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in queue.async { continuation.resume(returning: action()) } }
    }

    private static func sniffType(_ data: Data, offset: Int64) -> String? {
        guard offset == 0 else { return nil }
        if data.starts(with: Data("ID3".utf8)) { return UTType.mp3.identifier }
        if data.count >= 12, String(data: data[4..<8], encoding: .ascii) == "ftyp" { return UTType.mpeg4Audio.identifier }
        if data.count >= 12, data.starts(with: Data("RIFF".utf8)), String(data: data[8..<12], encoding: .ascii) == "WAVE" {
            return UTType.wav.identifier
        }
        return nil
    }
}
