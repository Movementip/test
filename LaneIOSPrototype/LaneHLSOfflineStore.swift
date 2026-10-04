import Foundation
import AVFoundation
import UIKit

#if DEBUG
// Generated 440 Hz tone for actual AVAssetDownloadURLSession tests only.
enum LaneHLSTestFixture {
    // RFC 8216 §3.4: packed AAC segments start with an ID3 PRIV timestamp.
    static func segment(timestamp: UInt64) -> Data {
        func size(_ value: Int) -> Data {
            Data([UInt8((value >> 21) & 127), UInt8((value >> 14) & 127), UInt8((value >> 7) & 127), UInt8(value & 127)])
        }
        var ticks = (timestamp & 0x1ffffffff).bigEndian
        let payload = Data("com.apple.streaming.transportStreamTimestamp".utf8) + Data([0]) + withUnsafeBytes(of: &ticks) { Data($0) }
        let frame = Data("PRIV".utf8) + size(payload.count) + Data([0, 0]) + payload
        return Data([0x49, 0x44, 0x33, 4, 0, 0]) + size(frame.count) + frame + audio
    }
    static let audio = Data(base64Encoded: "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523+f3btc888888888/A//lQYAggAAEOFazsoNHu/Maa+9v31C5SwMQigsWmGyllxQ3HTh/hXfnd7Nk9IgoKappJpJpJgAAdnZ2dnZ2dnbj/+VBgB2AAAQwVrMxhIG08evG19a+uD9y5RQMYm7JF9wCl3JS9KWnSJSVRfOFJYUtt1l226y4NevXr4P/5UGAHwAABFhWsyGASDDS979emutca/20XKWBiITU0waeYNPM9aRuYiCljyfIOiTgSEhISEhISEhISEhPA//lQYAZgAAEGFazIYPgeu68emutdcLlLA3D4+6E7QnaIPiFzkAUsez5A0YeDAwMDAwM4//lQYAggAAEIFazMYiho8fL3a41r7vqaLlLAxELMOktw9JTblJyyN06SBnyclUWwZ2dnZ2du7r7sQJ5555555+D/+VBgB0AAAQoVrORQEQw0c+P6aTrWuP97i5SQMInS/o9yXGl5vzHZzP9ZX8lqhcUUUUUUUUUUUUXA//lQYAhAAAEMFazsUihpz4c+ra1+OvN3ZcpYGIRRlNrmgKk3ZK2r0VKObtxkJemZkZGWvdTX7t2vc8888888889w//lQYAfgAAESFazsVChpO/HuOr/Gn40i5SwMQianTDpBcT9Vn6rd00BidSvK5BQUHRJNJokmkdwmYJCTk003//lQYAfAAAEKFazMYiBty59/m/Zr79Pqy5RwMJ2wKcwij8sX33Zue6MYROJouW5SMj32XWb9u+wCeeeeefj/+VBgB8AAARYVrMxgEgw01v89k61x9fvZcpYGIhNLVFaaitNJWppt45PAivLUzo7Ozs7dvhhiDAwMDAwNwP/5UGAGwAABBhWszGD4Fd+P45461xxwuVMDcXiAeQO+MMTjDE4w1+wVGaplLcsLCwsLCwsLHP/5UGAH4AABCBWszGIoaZz9t7q+r41P51IuUsDEQsxaRxLPs3ZRYojh2C1iFZmE4uzs7Ozs7OzgPPPPPPPPcP/5UGAGAAABDBWsyGD4GeK9/TXV9aXKOBhLTZbb8V3BD8uRcgBtYz482aaaaaaabv/5UGAIIAABDBWs7FIoaPE/ga1+J9auy5SwMQinmbrBz1AaO3LJw69lKeTTEkZRREZGR7tddNdNdM888888888///lQYAfAAAEIFazIVgkUNO/E/tGuta/D73ZcpYGIRUzhThfyq2o93cuj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")!
}
#endif

/// HLS is a package of playlists, segments and (where supported) keys, not a
/// downloaded .m3u8 file. Let AVFoundation own its offline asset location.
@MainActor final class LaneHLSOfflineStore: NSObject, AVAssetDownloadDelegate {
    static let shared = LaneHLSOfflineStore()
    static let identifier = "com.lane.ios.offline-hls"
    static let changed = Notification.Name("LaneHLSOfflineChanged")
    private struct Record: Codable { let track: TrackCandidate; let path: String; let quality: String }
    private struct Description: Codable { let id: UUID; let track: TrackCandidate; let quality: String }
    private struct Job { let description: Description; let task: AVAssetDownloadTask; let continuation: CheckedContinuation<URL, Error> }
    private var records: [String: Record] = [:]
    private var jobs: [Int: Job] = [:]
    private var locations: [Int: URL] = [:]
    private var inFlight: [String: Task<URL, Error>] = [:]
    private var pendingVerifications = 0
    private var eventsFinished = false
    private var backgroundCompletion: (() -> Void)?
    private lazy var downloads: AVAssetDownloadURLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        return AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: self, delegateQueue: .main)
    }()
    private var library: URL { FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].standardizedFileURL }

    private override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "lane.hls.records"), let value = try? JSONDecoder().decode([String: Record].self, from: data) { records = value }
        _ = downloads // reconnect native background tasks with this identifier
    }

    var tracks: [TrackCandidate] { records.values.compactMap { fileURL(for: $0.track.trackID ?? $0.track.id) == nil ? nil : $0.track } }
    func fileURL(for id: String) -> URL? {
        guard let record = records[id], !record.path.hasPrefix("/"), !record.path.split(separator: "/").contains("..") else { return nil }
        let url = library.appendingPathComponent(record.path).standardizedFileURL
        guard url.path.hasPrefix(library.path + "/"), url.pathExtension == "movpkg", FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func download(track: TrackCandidate, remote: URL, quality: String) async throws -> URL {
        let id = track.trackID ?? track.id
        if let task = inFlight[id] { return try await task.value }
        let task = Task { @MainActor in
            let asset = AVURLAsset(url: remote)
            guard try await asset.load(.isPlayable) else {
                throw LaneAPIError.decoding("This adaptive stream is not playable.")
            }
            // Load the selection before handing the asset to the native
            // background service, as in Apple's current HLS persistence sample.
            _ = try await asset.load(.preferredMediaSelection)
            try Task.checkCancellation()
            let configuration = AVAssetDownloadConfiguration(asset: asset, title: track.title)
            let task = downloads.makeAssetDownloadTask(downloadConfiguration: configuration)
            let description = Description(id: UUID(), track: track, quality: quality)
            task.taskDescription = String(data: try JSONEncoder().encode(description), encoding: .utf8)
            return try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { continuation in
                    jobs[task.taskIdentifier] = Job(description: description, task: task, continuation: continuation)
                    task.resume()
                }
            }, onCancel: { task.cancel() })
        }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    func remove(_ id: String) throws {
        inFlight[id]?.cancel()
        if let url = fileURL(for: id) { try FileManager.default.removeItem(at: url) }
        records.removeValue(forKey: id); save()
    }

    func handleBackgroundEvents(completion: @escaping () -> Void) {
        eventsFinished = false; backgroundCompletion = completion; _ = downloads
    }
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        locations[assetDownloadTask.taskIdentifier] = location
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let job = jobs.removeValue(forKey: task.taskIdentifier)
        let location = locations.removeValue(forKey: task.taskIdentifier)
        let restored = task.taskDescription.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode(Description.self, from: $0) }
        guard let description = job?.description ?? restored else { return }
        if let error { job?.continuation.resume(throwing: error); return }
        guard let location, location.pathExtension == "movpkg", location.standardizedFileURL.path.hasPrefix(library.path + "/") else {
            job?.continuation.resume(throwing: LaneAPIError.decoding("iOS did not return a complete offline package.")); return
        }
        pendingVerifications += 1
        Task {
            defer { pendingVerifications -= 1; completeBackgroundEventsIfReady() }
            do {
                let asset = AVURLAsset(url: location)
                let playable = try await asset.load(.isPlayable)
                guard asset.assetCache?.isPlayableOffline == true, playable else {
                    throw LaneAPIError.decoding("The adaptive stream is not playable offline. It was not marked downloaded.")
                }
                let id = description.track.trackID ?? description.track.id
                let previous = fileURL(for: id)
                records[id] = Record(track: description.track, path: String(location.standardizedFileURL.path.dropFirst(library.path.count + 1)), quality: description.quality)
                save()
                if let previous, previous != location { try? FileManager.default.removeItem(at: previous) }
                let policy = AVMutableAssetDownloadStorageManagementPolicy()
                policy.priority = .important; policy.expirationDate = .distantFuture
                AVAssetDownloadStorageManager.shared().setStorageManagementPolicy(policy, for: location)
                job?.continuation.resume(returning: location)
            } catch { job?.continuation.resume(throwing: error) }
        }
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        eventsFinished = true; completeBackgroundEventsIfReady()
    }
    private func completeBackgroundEventsIfReady() {
        guard eventsFinished, pendingVerifications == 0, let completion = backgroundCompletion else { return }
        backgroundCompletion = nil; eventsFinished = false; completion()
    }
    private func save() {
        if let data = try? JSONEncoder().encode(records) { UserDefaults.standard.set(data, forKey: "lane.hls.records") }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}

final class LaneApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == LaneHLSOfflineStore.identifier else { completionHandler(); return }
        Task { @MainActor in LaneHLSOfflineStore.shared.handleBackgroundEvents(completion: completionHandler) }
    }
}
