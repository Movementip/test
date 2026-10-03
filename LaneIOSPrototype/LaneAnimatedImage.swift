import SwiftUI
import UIKit
import ImageIO

/// Decode only the displayed and next frame. UIImage.animatedImage retains
/// every decoded frame, which can exhaust memory for remote profile GIFs.
struct LaneAnimatedImage: UIViewRepresentable {
    let data: Data
    var contentMode: ContentMode = .fill
    func makeUIView(context: Context) -> LaneGIFImageView { LaneGIFImageView(frame: .zero) }
    func updateUIView(_ view: LaneGIFImageView, context: Context) {
        view.contentMode = contentMode == .fill ? .scaleAspectFill : .scaleAspectFit
        view.setGIF(data)
    }
    static func dismantleUIView(_ view: LaneGIFImageView, coordinator: ()) { view.stopAnimation() }
}

final class LaneGIFImageView: UIImageView {
    private let decodeQueue = DispatchQueue(label: "lane.gif.frames", qos: .utility)
    private var compressed: Data?
    private var source: CGImageSource?
    private var count = 0
    private var generation = UUID()
    private var pending: (image: UIImage, delay: TimeInterval, index: Int)?
    private var decoding = false
    private var due: TimeInterval = 0
    private var link: CADisplayLink?
    private var observers: [NSObjectProtocol] = []
    #if DEBUG
    private(set) var displayedFrames = 0
    var animationIsRunning: Bool { link != nil }
    #endif

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updateAnimationState()
            })
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric) }
    override func didMoveToWindow() { super.didMoveToWindow(); updateAnimationState() }

    func setGIF(_ data: Data) {
        guard compressed != data else { return }
        generation = UUID(); compressed = data; pending = nil; decoding = false; due = 0
        source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        count = source.map(CGImageSourceGetCount) ?? 0
        if count > 0 { decode(0) }
        updateAnimationState()
    }

    func stopAnimation() { link?.invalidate(); link = nil }
    private func updateAnimationState() {
        guard window != nil, UIApplication.shared.applicationState != .background, count > 0 else { stopAnimation(); return }
        if link == nil {
            let value = CADisplayLink(target: self, selector: #selector(tick(_:)))
            value.preferredFramesPerSecond = 30
            value.add(to: .main, forMode: .common); link = value
        }
    }

    @objc private func tick(_ value: CADisplayLink) {
        guard value.timestamp >= due, let frame = pending else { return }
        image = frame.image; pending = nil; due = value.timestamp + frame.delay
        #if DEBUG
        displayedFrames += 1
        #endif
        if count > 1 { decode((frame.index + 1) % count) }
        else { stopAnimation() }
    }

    private func decode(_ index: Int) {
        guard !decoding, let source else { return }
        decoding = true
        let operation = generation
        decodeQueue.async { [weak self] in
            autoreleasepool {
                let frame = CGImageSourceCreateThumbnailAtIndex(source, index, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1280,
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary)
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                let delay = max(0.02, gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? gif?[kCGImagePropertyGIFDelayTime] as? Double ?? 0.1)
                DispatchQueue.main.async {
                    guard let self, self.generation == operation else { return }
                    self.decoding = false
                    if let frame { self.pending = (UIImage(cgImage: frame), delay, index) }
                }
            }
        }
    }
    deinit { link?.invalidate(); for observer in observers { NotificationCenter.default.removeObserver(observer) } }
}
