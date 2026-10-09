import Foundation
import UIKit
import Photos
import ImageIO
import UniformTypeIdentifiers
import SwiftSignalKit
import TelegramCore
import AccountContext
import Display
import DeviceAccess
import SaveToCameraRoll
import WebPBinding
import GZip
import LottieBinding
import LottieSettings
import AnimatedStickerNode
import YuvConversion

private enum StickerCameraRollFile {
    case png(URL)
    case gif(URL)
    
    var url: URL {
        switch self {
        case let .png(url), let .gif(url):
            return url
        }
    }
    
    var uniformTypeIdentifier: String {
        switch self {
        case .png:
            // MARK: NAGRAM
            return UTType.png.identifier
        case .gif:
            return UTType.gif.identifier
        }
    }
}

// MARK: NAGRAM — 保存贴纸到相册：静态贴纸导出 PNG，动态贴纸导出 GIF。
func saveStickerToCameraRoll(context: AccountContext, fileReference: FileMediaReference, userLocation: MediaResourceUserLocation) -> Signal<Bool, NoError> {
    let file = fileReference.media
    return fetchMediaData(context: context, userLocation: userLocation, mediaReference: fileReference.abstract)
    |> mapToSignal { state, _ -> Signal<String, NoError> in
        switch state {
        case let .data(data):
            if data.isComplete {
                return .single(data.path)
            } else {
                return .complete()
            }
        case .progress:
            return .complete()
        }
    }
    |> take(1)
    |> mapToSignal { path -> Signal<StickerCameraRollFile?, NoError> in
        return generateStickerCameraRollFile(file: file, path: path, lottieSettings: context.lottieRenderingSettings)
    }
    |> mapToSignal { file -> Signal<Bool, NoError> in
        guard let file else {
            return .single(false)
        }
        return saveStickerCameraRollFile(context: context, file: file)
    }
}

private func generateStickerCameraRollFile(file: TelegramMediaFile, path: String, lottieSettings: LottieRenderingSettings) -> Signal<StickerCameraRollFile?, NoError> {
    return Signal { subscriber in
        let queue = Queue(name: "SaveStickerToCameraRoll")
        queue.async {
            let result: StickerCameraRollFile?
            if file.isAnimatedSticker {
                result = generateLottieStickerGif(file: file, path: path, lottieSettings: lottieSettings)
            } else if file.isVideoSticker {
                result = generateVideoStickerGif(file: file, path: path, queue: queue)
            } else {
                result = generateStaticStickerPng(file: file, path: path)
            }
            subscriber.putNext(result)
            subscriber.putCompletion()
        }
        return EmptyDisposable
    }
}

private func saveStickerCameraRollFile(context: AccountContext, file: StickerCameraRollFile) -> Signal<Bool, NoError> {
    return Signal { subscriber in
        DeviceAccess.authorizeAccess(to: .mediaLibrary(.save), presentationData: context.sharedContext.currentPresentationData.with { $0 }, present: { controller, arguments in
            context.sharedContext.presentGlobalController(controller, arguments)
        }, openSettings: context.sharedContext.applicationBindings.openSettings, { authorized in
            guard authorized else {
                try? FileManager.default.removeItem(at: file.url)
                subscriber.putNext(false)
                subscriber.putCompletion()
                return
            }
            
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = file.url.lastPathComponent
            options.uniformTypeIdentifier = file.uniformTypeIdentifier
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: file.url, options: options)
            }, completionHandler: { success, _ in
                try? FileManager.default.removeItem(at: file.url)
                subscriber.putNext(success)
                subscriber.putCompletion()
            })
        })
        return EmptyDisposable
    }
}

private func generateStaticStickerPng(file: TelegramMediaFile, path: String) -> StickerCameraRollFile? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else {
        return nil
    }
    let image = WebP.convert(fromWebP: data) ?? UIImage(data: data)
    guard let pngData = image?.pngData() else {
        return nil
    }
    let url = stickerTemporaryUrl(file: file, pathExtension: "png")
    do {
        try pngData.write(to: url, options: [.atomic])
        return .png(url)
    } catch {
        return nil
    }
}

private func generateLottieStickerGif(file: TelegramMediaFile, path: String, lottieSettings: LottieRenderingSettings) -> StickerCameraRollFile? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else {
        return nil
    }
    let decompressedData = TGGUnzipData(data, 8 * 1024 * 1024) ?? data
    guard let lottie = makeLottieInstance(data: decompressedData, fitzModifier: .none, colorReplacements: nil, cacheKey: "nagram-save-sticker-\(file.fileId.id)", settings: lottieSettings) else {
        return nil
    }
    let frameCount = Int(lottie.frameCount)
    guard frameCount > 0 else {
        return nil
    }
    let frameRate = max(1, Int(lottie.frameRate))
    let size = stickerRenderSize(file: file)
    let width = Int(size.width)
    let height = Int(size.height)
    let url = stickerTemporaryUrl(file: file, pathExtension: "gif")
    
    if writeGif(url: url, frameCount: frameCount, frameRate: frameRate, frameImage: { frameIndex in
        guard let context = DrawingContext(size: size, scale: 1.0, opaque: false, clear: true) else {
            return nil
        }
        lottie.renderFrame(with: Int32(frameIndex), into: context.bytes.assumingMemoryBound(to: UInt8.self), width: Int32(width), height: Int32(height), bytesPerRow: Int32(context.bytesPerRow))
        return context.generateImage()?.cgImage
    }) {
        return .gif(url)
    } else {
        try? FileManager.default.removeItem(at: url)
        return nil
    }
}

private func generateVideoStickerGif(file: TelegramMediaFile, path: String, queue: Queue) -> StickerCameraRollFile? {
    let size = stickerRenderSize(file: file)
    let width = Int(size.width)
    let height = Int(size.height)
    guard let probeSource = makeVideoStickerDirectFrameSource(queue: queue, path: path, hintVP9: true, width: width, height: height, cachePathPrefix: nil, unpremultiplyAlpha: false) else {
        return nil
    }
    var frameCount = probeSource.frameCount
    if frameCount <= 0 {
        var decodedFrames = 0
        while decodedFrames < 300 {
            guard let _ = probeSource.takeFrame(draw: true) else {
                break
            }
            decodedFrames += 1
        }
        frameCount = probeSource.frameCount > 0 ? probeSource.frameCount : decodedFrames
    }
    frameCount = min(frameCount, 300)
    guard frameCount > 0, let source = makeVideoStickerDirectFrameSource(queue: queue, path: path, hintVP9: true, width: width, height: height, cachePathPrefix: nil, unpremultiplyAlpha: false) else {
        return nil
    }
    let url = stickerTemporaryUrl(file: file, pathExtension: "gif")
    if writeGif(url: url, frameCount: frameCount, frameRate: max(1, source.frameRate), frameImage: { _ in
        guard let frame = source.takeFrame(draw: true) else {
            return nil
        }
        return cgImage(from: frame)
    }) {
        return .gif(url)
    } else {
        try? FileManager.default.removeItem(at: url)
        return nil
    }
}

private func writeGif(url: URL, frameCount: Int, frameRate: Int, frameImage: (Int) -> CGImage?) -> Bool {
    guard frameCount > 0, let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
        return false
    }
    let gifProperties: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFLoopCount: 0
        ]
    ]
    CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)
    
    let delay = max(0.02, 1.0 / Double(max(1, frameRate)))
    let frameProperties: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: delay,
            kCGImagePropertyGIFUnclampedDelayTime: delay
        ]
    ]
    for i in 0 ..< frameCount {
        guard let image = frameImage(i) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
    }
    return CGImageDestinationFinalize(destination)
}

private func cgImage(from frame: AnimatedStickerFrame) -> CGImage? {
    let bytesPerRow: Int?
    switch frame.type {
    case .argb:
        bytesPerRow = frame.bytesPerRow
    default:
        bytesPerRow = nil
    }
    guard let context = DrawingContext(size: CGSize(width: CGFloat(frame.width), height: CGFloat(frame.height)), scale: 1.0, opaque: false, clear: true, bytesPerRow: bytesPerRow) else {
        return nil
    }
    switch frame.type {
    case .argb:
        frame.data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            memcpy(context.bytes, baseAddress, min(frame.data.count, context.length))
        }
    case .yuva:
        frame.data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            decodeYUVAToRGBA(baseAddress.assumingMemoryBound(to: UInt8.self), context.bytes.assumingMemoryBound(to: UInt8.self), Int32(frame.width), Int32(frame.height), Int32(context.bytesPerRow))
        }
    case .dct:
        return nil
    }
    return context.generateImage()?.cgImage
}

private func stickerRenderSize(file: TelegramMediaFile) -> CGSize {
    for attribute in file.attributes {
        switch attribute {
        case let .ImageSize(size):
            return normalizedStickerSize(width: CGFloat(size.width), height: CGFloat(size.height))
        case let .Video(_, size, _, _, _, _):
            return normalizedStickerSize(width: CGFloat(size.width), height: CGFloat(size.height))
        default:
            break
        }
    }
    return CGSize(width: 512.0, height: 512.0)
}

private func normalizedStickerSize(width: CGFloat, height: CGFloat) -> CGSize {
    let width = max(1.0, width)
    let height = max(1.0, height)
    let maxSide = max(width, height)
    if maxSide <= 512.0 {
        return CGSize(width: width, height: height)
    }
    let scale = 512.0 / maxSide
    return CGSize(width: max(1.0, floor(width * scale)), height: max(1.0, floor(height * scale)))
}

private func stickerTemporaryUrl(file: TelegramMediaFile, pathExtension: String) -> URL {
    let name = "nagram-sticker-\(file.fileId.namespace)-\(file.fileId.id)-\(Int64.random(in: Int64.min ... Int64.max)).\(pathExtension)"
    return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
}
