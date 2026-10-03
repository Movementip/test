import Foundation
import AVFoundation
import MediaToolbox

/// Android maps six normalized values into the device equalizer's gain range.
/// iOS has no hardware Equalizer: use six independent peaking filters instead.
struct LaneEQFilter {
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    init(frequency: Double, gain: Double, sampleRate: Double) {
        guard abs(gain) > 0.001 else { return }
        let omega = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let alpha = sin(omega) / (2 * 0.8), amplitude = pow(10, gain / 40)
        let denominator = 1 + alpha / amplitude
        b0 = (1 + alpha * amplitude) / denominator
        b1 = -2 * cos(omega) / denominator
        b2 = (1 - alpha * amplitude) / denominator
        a1 = b1; a2 = (1 - alpha / amplitude) / denominator
    }
}

struct LaneEQDelay {
    var z1 = 0.0, z2 = 0.0
    mutating func sample(_ input: Double, filter: LaneEQFilter) -> Double {
        let output = filter.b0 * input + z1
        z1 = filter.b1 * input - filter.a1 * output + z2
        z2 = filter.b2 * input - filter.a2 * output
        return output
    }
}

final class LaneEqualizerProcessor {
    static let frequencies: [Double] = [60, 150, 400, 1000, 4000, 12000]
    private let lock = NSLock()
    private var requested = [Double](repeating: 0.5, count: 6)
    private var enabled = false, dirty = true
    private var sampleRate = 48000.0, channels = 0
    private var validFormat = false, active = false
    private var filters = frequencies.map { LaneEQFilter(frequency: $0, gain: 0, sampleRate: 48000) }
    private var delays: [LaneEQDelay] = []
    private var headroom = 1.0
    private var frameCount: Int64 = 0

    func configure(values: [Double], enabled: Bool) {
        lock.lock(); defer { lock.unlock() }
        requested = values.count == 6 ? values.map { min(1, max(0, $0.isFinite ? $0 : 0.5)) } : [Double](repeating: 0.5, count: 6)
        self.enabled = enabled; dirty = true
    }
    var processedFrames: Int64 { lock.lock(); defer { lock.unlock() }; return frameCount }
    var supportsFormat: Bool { lock.lock(); defer { lock.unlock() }; return validFormat }

    func prepare(_ format: AudioStreamBasicDescription) {
        sampleRate = format.mSampleRate; channels = Int(format.mChannelsPerFrame)
        let supported = format.mFormatID == kAudioFormatLinearPCM && format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32 && channels > 0 && channels <= 8 && sampleRate > 0
        delays = Array(repeating: LaneEQDelay(), count: supported ? channels * 6 : 0)
        lock.lock(); validFormat = supported; dirty = true; lock.unlock()
    }

    /// Called on the audio thread. No actor hops, heap allocations, I/O or
    /// blocking mutex acquisition; a contested update is applied next buffer.
    func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard channels > 0, delays.count == channels * 6 else { return }
        if lock.try() {
            if dirty {
                active = enabled && requested.contains { abs($0 - 0.5) >= 0.01 }
                var boost = 0.0
                for band in 0..<6 {
                    let gain = (requested[band] - 0.5) * 30
                    filters[band] = LaneEQFilter(frequency: Self.frequencies[band], gain: active ? gain : 0, sampleRate: sampleRate)
                    boost = max(boost, gain)
                }
                headroom = active ? pow(10, -boost / 20) : 1
                for index in delays.indices { delays[index] = LaneEQDelay() }
                dirty = false
            }
            frameCount += Int64(frames); lock.unlock()
        }
        guard active else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        var firstChannel = 0
        for buffer in buffers {
            let count = Int(buffer.mNumberChannels)
            guard count > 0, firstChannel + count <= channels, let raw = buffer.mData else { return }
            let samples = raw.assumingMemoryBound(to: Float.self)
            let available = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * count))
            for frame in 0..<available {
                for channel in 0..<count {
                    let index = frame * count + channel
                    var value = Double(samples[index]) * headroom
                    for band in 0..<6 {
                        value = delays[(firstChannel + channel) * 6 + band].sample(value, filter: filters[band])
                    }
                    samples[index] = value.isFinite ? Float(min(1, max(-1, value))) : 0
                }
            }
            firstChannel += count
        }
    }

    func audioMix(for asset: AVAsset) async throws -> AVAudioMix? {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let context = Unmanaged.passRetained(self)
        var callbacks = MTAudioProcessingTapCallbacks(version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: context.toOpaque(),
            init: { _, client, storage in storage.pointee = client },
            finalize: { tap in Unmanaged<LaneEqualizerProcessor>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release() },
            prepare: { tap, _, format in Unmanaged<LaneEqualizerProcessor>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().prepare(format.pointee) },
            unprepare: nil,
            process: { tap, frames, _, buffers, count, flags in
                let status = MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flags, nil, count)
                guard status == noErr else { count.pointee = 0; return }
                Unmanaged<LaneEqualizerProcessor>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().process(buffers, frames: count.pointee)
            })
        var result: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &result)
        guard status == noErr, let result else { context.release(); return nil }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = result.takeRetainedValue()
        let mix = AVMutableAudioMix(); mix.inputParameters = [parameters]
        return mix
    }
}

#if canImport(UIKit)
import SwiftUI
struct LaneEqualizerScreen: View {
    @EnvironmentObject private var session: LaneSession
    var body: some View {
        Form {
            Toggle("Equalizer", isOn: Binding(get: { session.equalizerEnabled }, set: { session.setEqualizer(enabled: $0) }))
                .accessibilityIdentifier("equalizer.enabled")
            ForEach(0..<6, id: \.self) { band in
                VStack(alignment: .leading) {
                    HStack {
                        Text(band < 4 ? "\(Int(LaneEqualizerProcessor.frequencies[band])) Hz" : "\(Int(LaneEqualizerProcessor.frequencies[band] / 1000)) kHz")
                        Spacer(); Text(String(format: "%+.1f dB", (session.equalizerValues[band] - 0.5) * 30)).monospacedDigit()
                    }
                    Slider(value: Binding(get: { session.equalizerValues[band] }, set: { session.setEqualizer(band: band, value: $0) }), in: 0...1)
                        .disabled(!session.equalizerEnabled).accessibilityIdentifier("equalizer.band.\(band)")
                }
            }
            Button("Reset equalizer") { session.resetEqualizer() }.accessibilityIdentifier("equalizer.reset")
            Text(session.equalizerStatus).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("equalizer.status")
            Text("Six bands, neutral at 0 dB. Positive gain reserves headroom to avoid clipping. Some adaptive streams do not support iOS audio filters; they continue playing without the equalizer.").font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("Equalizer").navigationBarTitleDisplayMode(.inline).preferredColorScheme(.dark).laneIOSBackSwipe()
            .task {
                while !Task.isCancelled {
                    session.refreshEqualizerStatus()
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                }
            }
    }
}
#endif
