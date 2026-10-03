import Foundation
import UIKit
import MetricKit

/// End the assertion inside the expiration callback, before hopping to the
/// main actor. A queued actor task is too late if the system watchdog fires.
final class LaneAudioBackgroundLease {
    let generation = UUID()
    private let lock = NSLock()
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var ended = false

    func begin(expired: @escaping (UUID) -> Void) {
        let value = UIApplication.shared.beginBackgroundTask(withName: "Lane audio transition") { [weak self] in
            guard let self, self.end() else { return }
            expired(self.generation)
        }
        lock.lock()
        let alreadyEnded = ended
        if !alreadyEnded { identifier = value }
        lock.unlock()
        if alreadyEnded, value != .invalid { UIApplication.shared.endBackgroundTask(value) }
    }

    var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return !ended && identifier != .invalid
    }

    @discardableResult func end() -> Bool {
        lock.lock()
        guard !ended else { lock.unlock(); return false }
        ended = true
        let value = identifier
        identifier = .invalid
        lock.unlock()
        if value != .invalid { UIApplication.shared.endBackgroundTask(value) }
        return true
    }

    #if DEBUG
    func expireForTesting(expired: (UUID) -> Void) {
        if end() { expired(generation) }
    }
    #endif
    deinit { end() }
}

/// Local, bounded diagnostics. Never stores account IDs, tokens, titles or
/// signed media URLs and never uploads anything. MetricKit reports are delayed
/// and aggregate: absence of a report does NOT prove an app wasn't killed.
final class LaneAudioDiagnostics: NSObject, MXMetricManagerSubscriber {
    static let shared = LaneAudioDiagnostics()
    private let queue = DispatchQueue(label: "lane.audio.diagnostics")
    private let eventKey = "lane.audio.events"
    private let metricKey = "lane.audio.exitMetrics"

    private override init() {
        super.init()
        MXMetricManager.shared.add(self)
        record("process-start version=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
    }

    func record(_ event: String) {
        queue.async {
            var entries = UserDefaults.standard.stringArray(forKey: self.eventKey) ?? []
            entries.append("\(ISO8601DateFormatter().string(from: Date())) \(event)")
            UserDefaults.standard.set(Array(entries.suffix(80)), forKey: self.eventKey)
        }
    }

    func report() -> String {
        queue.sync {
            let events = UserDefaults.standard.stringArray(forKey: eventKey) ?? []
            let metrics = UserDefaults.standard.string(forKey: metricKey) ?? "No system exit report yet (reports may arrive later)."
            return "Local audio lifecycle\n" + events.joined(separator: "\n") + "\n\nSystem exit counters (aggregate, not a diagnosis of the last stop)\n" + metrics
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        guard let payload = payloads.last, let metric = payload.applicationExitMetrics,
              let json = String(data: metric.jsonRepresentation(), encoding: .utf8) else { return }
        queue.async {
            UserDefaults.standard.set("\(payload.timeStampBegin) – \(payload.timeStampEnd)\n\(json)", forKey: self.metricKey)
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        // Keep counts only. Call stacks/metadata are deliberately not retained.
        for payload in payloads {
            record("system-diagnostics crashes=\(payload.crashDiagnostics?.count ?? 0) hangs=\(payload.hangDiagnostics?.count ?? 0)")
        }
    }
}
