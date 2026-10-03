import Foundation
import AVFoundation
// A generated test tone, not user music. Run with a new temporary WAV path;
// encode to AAC ADTS with macOS afconvert for the DEBUG-only HTTP fixture.
func generate() throws {
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
let frames: AVAudioFrameCount = 132300
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
buffer.frameLength = frames
for index in 0..<Int(frames) { buffer.floatChannelData![0][index] = Float(0.1 * sin(2 * .pi * 440 * Double(index) / 44100)) }
let file = try AVAudioFile(forWriting: destination, settings: format.settings)
try file.write(from: buffer)
}
try generate()
