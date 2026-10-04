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
        // Avoid expensive denormal arithmetic on a long silent tail.
        if abs(z1) < 1e-24 { z1 = 0 }; if abs(z2) < 1e-24 { z2 = 0 }
        return output
    }
}

/// Labels and normalized preset gains from APK TrackEffectsSheetContentKt.
enum LaneEqualizerPresets {
    struct Preset: Identifiable { let name: String; let values: [Double]; var id: String { name } }
    static let all: [Preset] = [
        Preset(name: "Default", values: [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]),
        Preset(name: "Bass Boost", values: [0.85, 0.7, 0.5, 0.45, 0.5, 0.5]),
        Preset(name: "Treble Boost", values: [0.5, 0.5, 0.5, 0.55, 0.7, 0.85]),
        Preset(name: "Vocal Boost", values: [0.4, 0.4, 0.5, 0.7, 0.75, 0.55]),
        Preset(name: "Pop", values: [0.4, 0.5, 0.65, 0.65, 0.55, 0.45]),
        Preset(name: "Rock", values: [0.75, 0.65, 0.45, 0.55, 0.65, 0.75]),
        Preset(name: "Electronic", values: [0.8, 0.65, 0.45, 0.5, 0.65, 0.75]),
        Preset(name: "Hip-Hop", values: [0.85, 0.7, 0.45, 0.5, 0.6, 0.7]),
        Preset(name: "R&B", values: [0.7, 0.6, 0.55, 0.6, 0.65, 0.6]),
        Preset(name: "Jazz", values: [0.6, 0.6, 0.55, 0.5, 0.6, 0.65]),
        Preset(name: "Classical", values: [0.6, 0.5, 0.5, 0.5, 0.55, 0.65]),
        Preset(name: "Acoustic", values: [0.6, 0.55, 0.5, 0.6, 0.65, 0.6]),
        Preset(name: "Lounge", values: [0.6, 0.55, 0.5, 0.5, 0.45, 0.4]),
        Preset(name: "Spoken Word", values: [0.3, 0.4, 0.6, 0.7, 0.65, 0.4])
    ]
    static let labels = ["60 Hz", "150 Hz", "400 Hz", "1 kHz", "2.4 kHz", "15 kHz"]
}

final class LaneEqualizerProcessor {
    static let frequencies: [Double] = [60, 150, 400, 1000, 2400, 15000]
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
        ScrollView {
            LaneEqualizerControls().padding(24)
        }.background(Color.black.ignoresSafeArea())
            .navigationTitle("Equalizer").navigationBarTitleDisplayMode(.inline)
            .tint(Color(red: 1, green: 0.51, blue: 0.52)).preferredColorScheme(.dark).laneIOSBackSwipe()
    }
}

struct LaneEqualizerControls: View {
    @EnvironmentObject private var session: LaneSession
    @State private var fineAdjustment = false
    private let accent = Color(red: 1, green: 0.51, blue: 0.52)
    private var selectedPreset: String {
        LaneEqualizerPresets.all.first(where: { $0.values == session.equalizerValues })?.name ?? "Custom"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Toggle("Equalizer", isOn: Binding(get: { session.equalizerEnabled }, set: { session.setEqualizer(enabled: $0) }))
                .font(LaneTypography.manrope(22))
                .accessibilityIdentifier("equalizer.enabled")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if selectedPreset == "Custom" { chip("Custom", selected: true, action: {}) }
                    ForEach(LaneEqualizerPresets.all) { preset in
                        chip(preset.name, selected: selectedPreset == preset.name) { session.applyEqualizerPreset(preset) }
                    }
                }
            }
            LaneEqualizerCurve().frame(height: 172)
            HStack {
                ForEach(LaneEqualizerPresets.labels, id: \.self) { label in
                    Text(label).font(LaneTypography.manrope(11)).foregroundStyle(.secondary)
                    if label != LaneEqualizerPresets.labels.last { Spacer(minLength: 0) }
                }
            }.padding(.top, -12)
            Button { withAnimation { fineAdjustment.toggle() } } label: {
                HStack {
                    Text("Fine adjustment"); Spacer()
                    Image(systemName: fineAdjustment ? "chevron.up" : "chevron.down")
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("equalizer.fineAdjustment")
                .accessibilityValue(fineAdjustment ? "Expanded" : "Collapsed")
            if fineAdjustment {
                ForEach(0..<6, id: \.self) { band in
                    VStack(alignment: .leading) {
                        HStack {
                            Text(LaneEqualizerPresets.labels[band]); Spacer()
                            Text(String(format: "%+.1f dB", (session.equalizerValues[band] - 0.5) * 30)).monospacedDigit()
                        }
                        Slider(value: Binding(get: { session.equalizerValues[band] }, set: { session.setEqualizer(band: band, value: $0) }), in: 0...1)
                            .disabled(!session.equalizerEnabled).accessibilityIdentifier("equalizer.band.\(band)")
                    }.padding(.top, 10)
                }
            }
            Button("Reset equalizer") { session.resetEqualizer() }.accessibilityIdentifier("equalizer.reset")
            Text(session.equalizerStatus).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("equalizer.status")
            Text("Six bands, neutral at 0 dB. Positive gain reserves headroom to avoid clipping. Some adaptive streams do not support iOS audio filters; they continue playing without the equalizer.").font(.caption).foregroundStyle(.secondary)
        }.font(LaneTypography.manrope(16)).tint(accent)
            .task {
                while !Task.isCancelled {
                    session.refreshEqualizerStatus()
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                }
            }
    }
    private func chip(_ name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name).font(LaneTypography.manrope(13))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .foregroundStyle(selected ? Color.black : Color.white)
                .background(selected ? accent : Color.white.opacity(0.1), in: Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier("equalizer.preset.\(name)")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct LaneEqualizerCurve: View {
    @EnvironmentObject private var session: LaneSession
    @State private var draggedBand: Int?
    private let accent = Color(red: 1, green: 0.51, blue: 0.52)
    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 12), height = max(1, geometry.size.height - 12)
            let points = session.equalizerValues.enumerated().map { index, value in
                CGPoint(x: 6 + width * CGFloat(index) / 5, y: 6 + height * CGFloat(1 - value))
            }
            ZStack {
                Canvas { context, size in
                    for point in points {
                        var grid = Path(); grid.move(to: CGPoint(x: point.x, y: 0)); grid.addLine(to: CGPoint(x: point.x, y: size.height))
                        context.stroke(grid, with: .color(.white.opacity(0.05)), lineWidth: 2)
                    }
                    var curve = Path(); curve.addLines(points)
                    var fill = curve; fill.addLine(to: CGPoint(x: points[5].x, y: size.height))
                    fill.addLine(to: CGPoint(x: points[0].x, y: size.height)); fill.closeSubpath()
                    context.fill(fill, with: .linearGradient(Gradient(colors: [accent.opacity(0.3), accent.opacity(0)]),
                        startPoint: CGPoint(x: 0, y: points.map(\.y).min() ?? 0), endPoint: CGPoint(x: 0, y: size.height)))
                    context.stroke(curve, with: .color(accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }.accessibilityHidden(true)
                ForEach(0..<6, id: \.self) { band in
                    Circle().fill(accent).frame(width: 12, height: 12).position(points[band])
                        .accessibilityLabel(LaneEqualizerPresets.labels[band])
                        .accessibilityValue(String(format: "%+.1f dB", (session.equalizerValues[band] - 0.5) * 30))
                        .accessibilityAdjustableAction { direction in
                            let delta: Double
                            switch direction { case .increment: delta = 0.05; case .decrement: delta = -0.05; @unknown default: return }
                            update(band, value: session.equalizerValues[band] + delta)
                        }
                }
            }.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                    let band = draggedBand ?? min(5, max(0, Int(((gesture.startLocation.x - 6) / width * 5).rounded())))
                    draggedBand = band
                    update(band, value: 1 - Double((gesture.location.y - 6) / height))
                }.onEnded { _ in draggedBand = nil })
                .accessibilityElement(children: .contain).accessibilityIdentifier("equalizer.curve")
        }
    }
    private func update(_ band: Int, value: Double) {
        if !session.equalizerEnabled { session.setEqualizer(enabled: true) }
        session.setEqualizer(band: band, value: value)
    }
}
#endif
