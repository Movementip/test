import Foundation
import Network
import AVFoundation

/// Real native downloads and playback. API mocks do not handle this loopback
/// server; the only media is a generated tone, never a user's music.
private final class LaneNativeHLSServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "lane.native.hls.fixture")
    private var connections: [NWConnection] = []
    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                guard let data, let request = String(data: data, encoding: .utf8) else { connection.cancel(); return }
                let payload: Data
                let type: String
                if request.contains("/master.m3u8 ") {
                    payload = Data("#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-STREAM-INF:BANDWIDTH=80000,CODECS=\"mp4a.40.2\"\nmedia.m3u8\n".utf8)
                    type = "application/vnd.apple.mpegurl"
                } else if request.contains("/media.m3u8 ") {
                    payload = Data("#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXTINF:3.065034,\n1.aac\n#EXTINF:3.065034,\n2.aac\n#EXT-X-ENDLIST\n".utf8)
                    type = "application/vnd.apple.mpegurl"
                } else {
                    payload = LaneHLSTestFixture.segment(timestamp: request.contains("/2.aac ") ? 275853 : 0)
                    type = "audio/aac"
                }
                let head = "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(head.utf8) + (request.hasPrefix("HEAD ") ? Data() : payload), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)
    }
    var port: UInt16 { listener.port?.rawValue ?? 0 }
    func stop() { queue.sync { listener.cancel(); connections.forEach { $0.cancel() }; connections = [] } }
}

enum LaneHLSOfflineTests {
    @MainActor static func restore(id: String) async throws {
        let store = LaneHLSOfflineStore.shared
        guard let url = store.fileURL(for: id), store.tracks.contains(where: { $0.trackID == id }),
              AVURLAsset(url: url).assetCache?.isPlayableOffline == true else {
            throw LaneAPIError.decoding("Native package/metadata did not survive a fresh process")
        }
        let player = AVPlayer(url: url)
        player.volume = 0; player.play()
        for _ in 0..<100 {
            if player.currentTime().seconds > 0.3 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard player.currentTime().seconds > 0.3 else { throw player.currentItem?.error ?? LaneAPIError.decoding("Native offline package produced no audio") }
        player.pause(); player.replaceCurrentItem(with: nil)
        print("Native HLS fresh-process offline playback passed")
    }

    @MainActor static func run() async throws {
        let server = try LaneNativeHLSServer()
        defer { server.stop() }
        for _ in 0..<100 { if server.port > 0 { break }; try await Task.sleep(nanoseconds: 50_000_000) }
        guard server.port > 0 else { throw LaneAPIError.decoding("Native fixture could not bind loopback") }
        let id = "native-hls-test-\(UUID().uuidString)"
        let track = TrackCandidate(id: id, title: "Generated test tone", subtitle: "Fixture", trackID: id)
        let store = LaneHLSOfflineStore.shared
        defer { try? store.remove(id) }
        let location = try await store.download(track: track, remote: URL(string: "http://127.0.0.1:\(server.port)/master.m3u8")!, quality: "basic")
        guard location.pathExtension == "movpkg", store.fileURL(for: id) == location else { throw LaneAPIError.decoding("Native package was not recorded") }
        server.stop()
        UserDefaults.standard.synchronize() // deterministic cross-process fixture
        let child = Process(), output = Pipe()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--lane-hls-reload", id]
        child.standardOutput = output; child.standardError = output
        try child.run()
        for _ in 0..<250 { if !child.isRunning { break }; try await Task.sleep(nanoseconds: 100_000_000) }
        if child.isRunning { child.terminate(); throw LaneAPIError.decoding("Fresh-process offline test timed out") }
        let message = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard child.terminationStatus == 0, message.contains("Native HLS fresh-process offline playback passed") else { throw LaneAPIError.decoding(message) }
        try store.remove(id)
        guard store.fileURL(for: id) == nil, !FileManager.default.fileExists(atPath: location.path) else { throw LaneAPIError.decoding("Native package removal failed") }
        print("Lane native HLS tests passed: real .movpkg, bookmark/ledger restore in a fresh process, playback with HTTP server stopped, scoped deletion")
    }
}
