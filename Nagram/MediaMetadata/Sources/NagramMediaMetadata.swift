import Foundation
import AVFoundation
import CoreMedia
import Display
import Postbox
import TelegramCore
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import AlertUI
import SwiftSignalKit

// MARK: NAGRAM — 媒体信息弹窗。
// 从 AnyMediaReference 提取图片 / 视频 metadata（分辨率、时长、帧率、码率、编码等），
// 并以 alert 形式展示。完整文件走 AVAsset 探测；流式播放只有 partial 缓存时，
// 退回手动解析 mp4 头部（faststart moov）取编码与帧率。
public enum NagramMediaMetadata {
    public static func present(
        context: AccountContext,
        mediaReference: AnyMediaReference,
        presentationData: PresentationData,
        present: (ViewController) -> Void
    ) {
        let text = buildText(context: context, mediaReference: mediaReference)
        let controller = textAlertController(
            context: context,
            forceTheme: defaultDarkColorPresentationTheme,
            title: "媒体信息",
            text: text,
            actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
        )
        present(controller)
    }

    private static func buildText(context: AccountContext, mediaReference: AnyMediaReference) -> String {
        var lines: [(String, String)] = []
        let mediaBox = context.account.postbox.mediaBox

        if let imageRef = mediaReference.concrete(TelegramMediaImage.self) {
            let image = imageRef.media
            if let representation = largestImageRepresentation(image.representations) {
                lines.append(("分辨率", "\(Int(representation.dimensions.width)) × \(Int(representation.dimensions.height))"))
                if let localPath = mediaBox.completedResourcePath(representation.resource), let size = fileSize(atPath: localPath) {
                    lines.append(("文件大小", formatBytes(size)))
                } else if let declared = representation.resource.size, declared > 0 {
                    lines.append(("文件大小", formatBytes(declared)))
                }
            }
            lines.append(("类型", "图片"))
        } else if let fileRef = mediaReference.concrete(TelegramMediaFile.self) {
            let file = fileRef.media
            var isVideo = false
            var isAnimated = false
            var videoDuration: Double?
            var videoDimensions: PixelDimensions?
            var declaredCodec: String?
            var audioDuration: Int?
            for attr in file.attributes {
                switch attr {
                case let .Video(duration, size, _, _, _, videoCodec):
                    isVideo = true
                    videoDuration = duration
                    videoDimensions = size
                    declaredCodec = videoCodec
                case let .Audio(_, duration, _, _, _):
                    audioDuration = duration
                case let .ImageSize(size):
                    if videoDimensions == nil {
                        videoDimensions = size
                    }
                case .Animated:
                    isAnimated = true
                default:
                    break
                }
            }

            let typeLabel: String
            if isVideo {
                typeLabel = isAnimated ? "GIF" : "视频"
            } else if audioDuration != nil {
                typeLabel = "音频"
            } else if isAnimated {
                typeLabel = "动图"
            } else {
                typeLabel = "文件"
            }
            lines.append(("类型", typeLabel))

            if let dims = videoDimensions {
                lines.append(("分辨率", "\(Int(dims.width)) × \(Int(dims.height))"))
            }
            if let duration = videoDuration {
                lines.append(("时长", formatDuration(duration)))
            } else if let duration = audioDuration {
                lines.append(("时长", formatDuration(Double(duration))))
            }

            let localPath = mediaBox.completedResourcePath(file.resource)
            var fileBytes: Int64?
            if let path = localPath, let size = fileSize(atPath: path) {
                fileBytes = size
            } else if let size = file.size {
                fileBytes = size
            }
            if let bytes = fileBytes {
                lines.append(("文件大小", formatBytes(bytes)))
            }

            if isVideo {
                var probe = VideoProbe()
                if let path = localPath {
                    probe = probeVideo(path: path)
                }
                // 流式播放的视频只有 partial 缓存、没有完整文件；faststart mp4 的 moov
                // 在文件头，看过几秒后头部分片必然已落盘，直接解析它补齐编码与帧率。
                if probe.codec == nil || probe.frameRate == nil {
                    let headerPath = localPath ?? mediaBox.storePathsForId(file.resource.id).partial
                    let header = probeMP4Header(path: headerPath)
                    if probe.codec == nil {
                        probe.codec = header.codec
                    }
                    if probe.frameRate == nil {
                        probe.frameRate = header.frameRate
                    }
                }
                if let fps = probe.frameRate {
                    lines.append(("帧率", String(format: "%.1f fps", fps)))
                }
                if let rate = probe.bitrate {
                    lines.append(("码率", formatBitrate(rate)))
                } else if let bytes = fileBytes, let duration = videoDuration, duration > 0 {
                    lines.append(("码率", formatBitrate(Double(bytes) * 8.0 / duration)))
                }
                if let codec = probe.codec {
                    lines.append(("编码", codec))
                } else if let codec = declaredCodec {
                    lines.append(("编码", codec.uppercased()))
                }
            }

            if !file.mimeType.isEmpty {
                lines.append(("MIME", file.mimeType))
            }
        } else {
            lines.append(("类型", "未知"))
        }

        let width = lines.map { $0.0.count }.max() ?? 0
        return lines.map { key, value in
            let padded = key + String(repeating: " ", count: max(0, width - key.count))
            return "\(padded)   \(value)"
        }.joined(separator: "\n")
    }

    private struct VideoProbe {
        var frameRate: Float?
        var bitrate: Double?
        var codec: String?
    }

    private static func probeVideo(path: String) -> VideoProbe {
        var result = VideoProbe()
        guard FileManager.default.fileExists(atPath: path) else {
            return result
        }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let tracks = asset.tracks(withMediaType: .video)
        guard let track = tracks.first else {
            return result
        }
        if track.nominalFrameRate > 0 {
            result.frameRate = track.nominalFrameRate
        }
        if track.estimatedDataRate > 0 {
            result.bitrate = Double(track.estimatedDataRate)
        }
        if let desc = track.formatDescriptions.first {
            let fd = desc as! CMFormatDescription
            let subtype = CMFormatDescriptionGetMediaSubType(fd)
            result.codec = fourCCString(subtype).uppercased()
        }
        return result
    }

    private static func fourCCString(_ value: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        if let s = String(bytes: bytes, encoding: .ascii) {
            return codecDisplayName(s.trimmingCharacters(in: .whitespaces))
        }
        return "?"
    }

    private static func codecDisplayName(_ fourcc: String) -> String {
        switch fourcc {
        case "avc1", "avc3": return "H.264"
        case "hvc1", "hev1": return "HEVC"
        case "dvh1", "dvhe": return "Dolby Vision (HEVC)"
        case "vp08": return "VP8"
        case "vp09": return "VP9"
        case "av01": return "AV1"
        case "mp4v": return "MPEG-4"
        case "s263": return "H.263"
        default: return fourcc.uppercased()
        }
    }

    // MP4 头部解析：不依赖完整文件，从（可能是 partial 的）mp4 中读取
    // moov → trak → mdia，取 stsd 的 fourcc 与 mdhd/stts 推算帧率。
    // 分片缺失处读到的是空洞或越界，childBoxes 的尺寸校验会让解析安全地半途而废。

    private final class BoxReader {
        private let handle: FileHandle
        let fileLength: Int64

        init?(path: String) {
            guard let handle = FileHandle(forReadingAtPath: path) else {
                return nil
            }
            self.handle = handle
            guard let length = try? handle.seekToEnd() else {
                return nil
            }
            self.fileLength = Int64(length)
        }

        deinit {
            try? self.handle.close()
        }

        func read(at offset: Int64, count: Int) -> [UInt8]? {
            guard offset >= 0, count > 0, offset + Int64(count) <= self.fileLength else {
                return nil
            }
            guard let _ = try? self.handle.seek(toOffset: UInt64(offset)), let data = try? self.handle.read(upToCount: count), data.count == count else {
                return nil
            }
            return [UInt8](data)
        }
    }

    private static func beUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32? {
        guard offset >= 0, bytes.count >= offset + 4 else {
            return nil
        }
        return (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16) | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
    }

    private static func beUInt64(_ bytes: [UInt8], _ offset: Int) -> UInt64? {
        guard let high = beUInt32(bytes, offset), let low = beUInt32(bytes, offset + 4) else {
            return nil
        }
        return (UInt64(high) << 32) | UInt64(low)
    }

    private static func childBoxes(_ reader: BoxReader, _ range: Range<Int64>) -> [(type: String, payload: Range<Int64>)] {
        var result: [(String, Range<Int64>)] = []
        var offset = range.lowerBound
        while offset + 8 <= range.upperBound, result.count < 512 {
            guard let header = reader.read(at: offset, count: 8), let size32 = beUInt32(header, 0) else {
                break
            }
            guard let type = String(bytes: header[4..<8], encoding: .ascii), type.allSatisfy({ $0.isASCII && !$0.isNewline }) else {
                break
            }
            var size = Int64(size32)
            var payloadStart = offset + 8
            if size32 == 1 {
                guard let ext = reader.read(at: offset + 8, count: 8), let size64 = beUInt64(ext, 0), size64 <= Int64.max else {
                    break
                }
                size = Int64(size64)
                payloadStart = offset + 16
            }
            guard size >= payloadStart - offset, offset + size <= range.upperBound else {
                break
            }
            result.append((type, payloadStart..<(offset + size)))
            offset += size
        }
        return result
    }

    private static func probeMP4Header(path: String) -> VideoProbe {
        var result = VideoProbe()
        guard let reader = BoxReader(path: path), reader.fileLength > 16 else {
            return result
        }
        guard let moov = childBoxes(reader, 0..<reader.fileLength).first(where: { $0.type == "moov" })?.payload else {
            return result
        }
        for trak in childBoxes(reader, moov) where trak.type == "trak" {
            guard let mdia = childBoxes(reader, trak.payload).first(where: { $0.type == "mdia" })?.payload else {
                continue
            }
            let mdiaChildren = childBoxes(reader, mdia)

            guard let hdlr = mdiaChildren.first(where: { $0.type == "hdlr" })?.payload,
                  let hdlrBytes = reader.read(at: hdlr.lowerBound, count: 12),
                  String(bytes: hdlrBytes[8..<12], encoding: .ascii) == "vide" else {
                continue
            }

            var timescale: Double?
            var duration: Double?
            if let mdhd = mdiaChildren.first(where: { $0.type == "mdhd" })?.payload,
               let bytes = reader.read(at: mdhd.lowerBound, count: min(Int(mdhd.upperBound - mdhd.lowerBound), 32)) {
                if bytes[0] == 0, let ts = beUInt32(bytes, 12), let d = beUInt32(bytes, 16) {
                    timescale = Double(ts)
                    duration = Double(d)
                } else if bytes[0] == 1, let ts = beUInt32(bytes, 20), let d = beUInt64(bytes, 24) {
                    timescale = Double(ts)
                    duration = Double(d)
                }
            }

            guard let minf = mdiaChildren.first(where: { $0.type == "minf" })?.payload,
                  let stbl = childBoxes(reader, minf).first(where: { $0.type == "stbl" })?.payload else {
                continue
            }
            let stblChildren = childBoxes(reader, stbl)

            if let stsd = stblChildren.first(where: { $0.type == "stsd" })?.payload,
               let bytes = reader.read(at: stsd.lowerBound, count: 16),
               let fourcc = String(bytes: bytes[12..<16], encoding: .ascii) {
                result.codec = codecDisplayName(fourcc.trimmingCharacters(in: .whitespaces))
            }

            if let stts = stblChildren.first(where: { $0.type == "stts" })?.payload,
               let head = reader.read(at: stts.lowerBound, count: 8),
               let entryCount32 = beUInt32(head, 4) {
                let entryCount = Int(entryCount32)
                if entryCount > 0, entryCount <= 4096,
                   let table = reader.read(at: stts.lowerBound + 8, count: entryCount * 8) {
                    var samples: Double = 0
                    for i in 0..<entryCount {
                        samples += Double(beUInt32(table, i * 8) ?? 0)
                    }
                    if samples > 0, let ts = timescale, let d = duration, ts > 0, d > 0 {
                        result.frameRate = Float(samples / (d / ts))
                    }
                }
            }

            if result.codec != nil {
                break
            }
        }
        return result
    }

    private static func fileSize(atPath path: String) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber else {
            return nil
        }
        return size.int64Value
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var idx = 0
        while value >= 1024 && idx < units.count - 1 {
            value /= 1024
            idx += 1
        }
        if idx == 0 {
            return "\(bytes) B"
        }
        return String(format: "%.2f %@", value, units[idx])
    }

    private static func formatBitrate(_ bitsPerSecond: Double) -> String {
        if bitsPerSecond >= 1_000_000 {
            return String(format: "%.2f Mbps", bitsPerSecond / 1_000_000)
        } else if bitsPerSecond >= 1_000 {
            return String(format: "%.0f Kbps", bitsPerSecond / 1_000)
        }
        return String(format: "%.0f bps", bitsPerSecond)
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
