import Foundation
import AVFoundation

@main struct LaneEqualizerTests {
    static func main() {
        precondition(LaneEqualizerPresets.all.count == 14)
        precondition(Set(LaneEqualizerPresets.all.map(\.name)).count == 14)
        precondition(LaneEqualizerProcessor.frequencies == [60, 150, 400, 1000, 2400, 15000])
        precondition(LaneEqualizerPresets.all.allSatisfy { $0.values.count == 6 && $0.values.allSatisfy { (0...1).contains($0) } })
        precondition(LaneEqualizerPresets.all.first(where: { $0.name == "Bass Boost" })?.values == [0.85, 0.7, 0.5, 0.45, 0.5, 0.5])
        func rendered(values: [Double], enabled: Bool, frequency: Double) -> [Float] {
            let processor = LaneEqualizerProcessor()
            processor.configure(values: values, enabled: enabled)
            processor.prepare(AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8,
                mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0))
            var samples = (0..<48000).flatMap { frame -> [Float] in
                [Float(0.1 * sin(2 * .pi * frequency * Double(frame) / 48000)), 0]
            }
            samples.withUnsafeMutableBytes { bytes in
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
                processor.process(&list, frames: 48000)
            }
            precondition(processor.processedFrames == 48000)
            precondition(samples.allSatisfy { $0.isFinite && abs($0) <= 1 })
            precondition(stride(from: 1, to: samples.count, by: 2).allSatisfy { samples[$0] == 0 }, "Channel leakage")
            return samples
        }
        let neutral = Array(repeating: 0.5, count: 6)
        let bypass = rendered(values: neutral, enabled: false, frequency: 1000)
        precondition(bypass == rendered(values: neutral, enabled: true, frequency: 1000), "Neutral must be bit-exact")
        var cut = neutral; cut[3] = 0
        let filtered = rendered(values: cut, enabled: true, frequency: 1000)
        func rms(_ samples: [Float]) -> Double {
            let values = stride(from: 12000, to: samples.count, by: 2).map { Double(samples[$0]) }
            return sqrt(values.reduce(0) { $0 + $1 * $1 } / Double(values.count))
        }
        precondition(rms(filtered) / rms(bypass) < 0.2, "1000 Hz cut did not affect PCM")
        precondition(rendered(values: cut, enabled: false, frequency: 1000) == bypass)
        _ = rendered(values: [0, 1, 0, 1, 0, 1], enabled: true, frequency: 12000)
        print("Lane EQ PCM tests passed: bit-exact neutral/bypass, audible band cut, stereo isolation, finite bounded output")
    }
}
