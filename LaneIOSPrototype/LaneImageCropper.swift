import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

struct LaneImageCropDraft: Identifiable {
    let id = UUID()
    let image: UIImage
    let original: Data
    let target: String
    var isGIF: Bool { original.starts(with: Data("GIF8".utf8)) }
}

enum LaneImageCropping {
    static func preview(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let frame = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1800,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: frame)
    }

    static func render(_ draft: LaneImageCropDraft, viewport: CGSize, zoom: CGFloat, offset: CGSize) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let width: CGFloat = draft.target == "avatar" ? 800 : 1800
                    let size = CGSize(width: width, height: width * viewport.height / viewport.width)
                    let factor = width / viewport.width
                    func draw(_ image: UIImage) -> CGImage? {
                        let scale = max(viewport.width / image.size.width, viewport.height / image.size.height) * zoom
                        let rect = CGRect(x: ((viewport.width - image.size.width * scale) / 2 + offset.width) * factor,
                                          y: ((viewport.height - image.size.height * scale) / 2 + offset.height) * factor,
                                          width: image.size.width * scale * factor, height: image.size.height * scale * factor)
                        let format = UIGraphicsImageRendererFormat(); format.scale = 1
                        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: rect) }.cgImage
                    }
                    if !draft.isGIF {
                        guard let image = draw(draft.image), let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else { throw LaneAPIError.emptyResponse }
                        continuation.resume(returning: data); return
                    }
                    guard let source = CGImageSourceCreateWithData(draft.original as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw LaneAPIError.emptyResponse }
                    let count = CGImageSourceGetCount(source)
                    guard count > 0, count <= 1000 else { throw LaneAPIError.decoding("This GIF has too many frames to edit safely on this iPhone.") }
                    let output = NSMutableData()
                    guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.gif.identifier as CFString, count, nil) else { throw LaneAPIError.emptyResponse }
                    let global = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
                    if let gif = global?[kCGImagePropertyGIFDictionary] { CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: gif] as CFDictionary) }
                    for index in 0..<count {
                        try autoreleasepool {
                            guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, [
                                kCGImageSourceCreateThumbnailFromImageAlways: true,
                                kCGImageSourceThumbnailMaxPixelSize: 1800,
                                kCGImageSourceShouldCacheImmediately: true
                            ] as CFDictionary), let cropped = draw(UIImage(cgImage: frame)) else { throw LaneAPIError.emptyResponse }
                            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
                            CGImageDestinationAddImage(destination, cropped, [kCGImagePropertyGIFDictionary: gif] as CFDictionary)
                            guard output.length <= 32 * 1024 * 1024 else { throw LaneAPIError.decoding("The edited GIF is too large. Use a smaller image.") }
                        }
                    }
                    guard CGImageDestinationFinalize(destination) else { throw LaneAPIError.emptyResponse }
                    continuation.resume(returning: output as Data)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

struct LaneImageCropScreen: View {
    @Environment(\.dismiss) private var dismiss
    let draft: LaneImageCropDraft
    let save: (Data, Bool) -> Void
    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var shape = "Square"
    @State private var busy = false
    @State private var error: String?
    @GestureState private var scale: CGFloat = 1
    @GestureState private var translation = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 32)
            let ratio: CGFloat = shape == "Square" ? 1 : shape == "Wide" ? 16 / 9 : draft.image.size.width / draft.image.size.height
            let heightLimit = max(120, geometry.size.height - 230)
            let viewport = CGSize(width: min(width, heightLimit * ratio), height: min(width / ratio, heightLimit))
            let base = max(viewport.width / draft.image.size.width, viewport.height / draft.image.size.height)
            let finalZoom = min(5, max(1, zoom * scale))
            let finalOffset = bounded(CGSize(width: offset.width + translation.width, height: offset.height + translation.height), viewport: viewport, factor: base * finalZoom)
            VStack(spacing: 22) {
                HStack {
                    Button("Cancel") { dismiss() }.disabled(busy).accessibilityIdentifier("crop.cancel")
                    Spacer(); Text("Crop image").font(.headline); Spacer()
                    Button(busy ? "Saving…" : "Use image") {
                        busy = true; error = nil
                        Task {
                            defer { busy = false }
                            do {
                                let data = try await LaneImageCropping.render(draft, viewport: viewport, zoom: finalZoom, offset: finalOffset)
                                save(data, draft.isGIF); dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(busy).accessibilityIdentifier("crop.save")
                }
                Picker("Crop shape", selection: $shape) {
                    Text("Square").tag("Square")
                    Text("Wide").tag("Wide")
                    Text("Original").tag("Original")
                }.pickerStyle(.segmented).disabled(busy).accessibilityIdentifier("crop.shape")
                Spacer(minLength: 0)
                ZStack {
                    Color.black
                    Image(uiImage: draft.image).resizable()
                        .frame(width: draft.image.size.width * base * finalZoom, height: draft.image.size.height * base * finalZoom)
                        .offset(finalOffset)
                }.frame(width: viewport.width, height: viewport.height).clipped()
                    .overlay(Rectangle().stroke(.white, lineWidth: 1))
                    .contentShape(Rectangle()).accessibilityIdentifier("crop.preview")
                    .gesture(MagnificationGesture().updating($scale) { value, state, _ in state = value }
                        .onEnded { value in zoom = min(5, max(1, zoom * value)); offset = bounded(offset, viewport: viewport, factor: base * zoom) })
                    .simultaneousGesture(DragGesture().updating($translation) { value, state, _ in state = value.translation }
                        .onEnded { value in offset = bounded(CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height), viewport: viewport, factor: base * zoom) })
                    .allowsHitTesting(!busy)
                Text(draft.isGIF ? "All GIF frames and timing will be preserved." : "Pinch to zoom and drag to frame the image.").font(.caption).foregroundStyle(.secondary)
                Button("Reset crop") { zoom = 1; offset = .zero }.disabled(busy).accessibilityIdentifier("crop.reset")
                if let error { Text(error).foregroundStyle(.red) }
                Spacer(minLength: 0)
            }.padding(16)
        }
        .background(Color.black.ignoresSafeArea()).preferredColorScheme(.dark)
        .interactiveDismissDisabled(busy)
        .onAppear { shape = draft.target == "avatar" ? "Square" : "Wide" }
        .onChange(of: shape) { _ in zoom = 1; offset = .zero }
    }
    private func bounded(_ value: CGSize, viewport: CGSize, factor: CGFloat) -> CGSize {
        let x = max(0, (draft.image.size.width * factor - viewport.width) / 2)
        let y = max(0, (draft.image.size.height * factor - viewport.height) / 2)
        return CGSize(width: min(x, max(-x, value.width)), height: min(y, max(-y, value.height)))
    }
}
