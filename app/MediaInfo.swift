// MediaInfo.swift: every media detail of a file, read by MediaArea's MediaInfo (v8, 6.11.2026). Marko: "Because this
// is mostly used for media work, I need all media details. Find the repository media info and let it read all possible
// media info inside the file. In list view, I can see all this info for each file."
// The mediainfo command line (github.com/MediaArea/MediaInfo) is inside the app (Contents/Resources/mediainfo, put
// there by the GitHub workflow from MediaArea's own Mac build); without it the Homebrew copy is used. For every video,
// sound and picture a pane shows, two at a time in the background, once per file and date:
//   mediainfo --Output=JSON <file>   -> the facts for the columns and the details line (codec, size in pixels, frame
//                                       rate, bit rate, bit depth and chroma, colour, HDR, audio, timecode, scan)
//   mediainfo [--Full] <file>        -> the whole report, track by track, shown under the line when INFO is on
import Foundation
import SwiftUI

let MEDIA_EXT: Set<String> = ["mov", "mp4", "m4v", "mxf", "mkv", "webm", "avi", "mts", "m2ts", "ts", "mpg", "mpeg",
    "r3d", "braw", "ari", "crm", "dng", "exr", "dpx", "wav", "aif", "aiff", "mp3", "m4a", "aac", "flac", "ogg", "opus",
    "caf", "wma", "wmv", "3gp", "heic", "heif", "jpg", "jpeg", "png", "tif", "tiff", "psd", "gif", "webp", "avif", "jxl"]

struct MediaFacts: Hashable {
    var duration: Double = -1        // seconds
    var codec = ""                   // HEVC Main 10
    var width = 0, height = 0
    var fps: Double = 0
    var bitrate: Double = 0          // overall, bits per second
    var depth = ""                   // 10-bit 4:2:0
    var colour = ""                  // BT.709 · Limited, or the HDR format
    var audio = ""                   // AAC LC · 1 ch · 48 kHz · 256 kb/s (· 2 more tracks)
    var timecode = ""                // 01:00:00:00
    var scan = ""                    // Progressive / Interlaced
    var writer = ""                  // DaVinci Resolve Studio
    var tracks = ""                  // 1 video · 1 audio · 1 other
    var ok = false
    var res: String { width > 0 ? "\(width)×\(height)" : "" }
    var fpsText: String {
        guard fps > 0 else { return "" }
        return fps == fps.rounded() ? String(format: "%.0f", fps) : String(format: "%.3f", fps)
    }
    var rateText: String { bitrate > 0 ? rate(bitrate) : "" }
    // the one line under the name: everything above, in the order an editor reads it
    var line: String {
        var a: [String] = []
        for s in [codec, res, fps > 0 ? fpsText + " fps" : "", depth, scan == "Progressive" ? "" : scan, colour,
                  bitrate > 0 ? rateText : "", audio, timecode.isEmpty ? "" : "TC " + timecode, writer, tracks]
            where !s.isEmpty { a.append(s) }
        return a.joined(separator: " · ")
    }
}
func rate(_ b: Double) -> String {
    b >= 1e6 ? String(format: "%.1f Mb/s", b / 1e6) : b >= 1e3 ? String(format: "%.0f kb/s", b / 1e3) : String(format: "%.0f b/s", b)
}

final class Media: ObservableObject {
    static let shared = Media()
    @Published var facts: [String: MediaFacts] = [:]
    @Published var reports: [String: String] = [:]
    private var busy = Set<String>()
    private let q: OperationQueue = {
        let q = OperationQueue(); q.maxConcurrentOperationCount = 2; q.qualityOfService = .utility; return q
    }()
    // the mediainfo inside the app first, then Homebrew's
    static let binary: String? = {
        let inside = Bundle.main.resourcePath.map { $0 + "/mediainfo" }
        for p in [inside, "/opt/homebrew/bin/mediainfo", "/usr/local/bin/mediainfo"].compactMap({ $0 })
            where FileManager.default.isExecutableFile(atPath: p) { return p }
        return nil
    }()
    static var version: String {
        guard let b = binary else { return "" }
        return run(b, ["--Version"]).components(separatedBy: "\n").last { $0.contains("v") }?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
    static func isMedia(_ name: String) -> Bool { MEDIA_EXT.contains((name as NSString).pathExtension.lowercased()) }
    private func key(_ p: String, _ m: Date) -> String { p + "|\(m.timeIntervalSince1970)" }

    func want(_ path: String, mtime: Date) {
        let k = key(path, mtime)
        guard let b = Media.binary, facts[k] == nil, !busy.contains(k) else { return }
        busy.insert(k)
        q.addOperation {
            let f = Media.parse(Media.run(b, ["--Output=JSON", path]))
            DispatchQueue.main.async { self.facts[k] = f; self.busy.remove(k) }
        }
    }
    // the whole report (INFO): the MediaInfo text view, or with full every field it knows in every form
    func wantReport(_ path: String, mtime: Date, full: Bool) {
        let k = key(path, mtime) + (full ? "|full" : "")
        guard let b = Media.binary, reports[k] == nil, !busy.contains(k) else { return }
        busy.insert(k)
        q.addOperation {
            let t = Media.run(b, (full ? ["--Full"] : []) + [path])
            DispatchQueue.main.async { self.reports[k] = Media.clean(t, path); self.busy.remove(k) }
        }
    }
    func of(_ path: String, _ mtime: Date) -> MediaFacts? { facts[key(path, mtime)] }
    func report(_ path: String, _ mtime: Date, full: Bool) -> String? { reports[key(path, mtime) + (full ? "|full" : "")] }

    static func run(_ bin: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: bin); p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: d, as: UTF8.self)
    }
    // the full path is the first line of the report; the pane already shows it
    static func clean(_ t: String, _ path: String) -> String {
        t.components(separatedBy: "\n").filter { !$0.hasPrefix("Complete name") }.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parse(_ json: String) -> MediaFacts {
        var f = MediaFacts()
        guard let d = json.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let m = j["media"] as? [String: Any], let tracks = m["track"] as? [[String: Any]] else { return f }
        f.ok = true
        func s(_ t: [String: Any], _ k: String) -> String { (t[k] as? String) ?? "" }
        func n(_ t: [String: Any], _ k: String) -> Double { Double(s(t, k).components(separatedBy: " ").first ?? "") ?? 0 }
        let byType = Dictionary(grouping: tracks) { s($0, "@type") }
        let g = byType["General"]?.first ?? [:]
        let vids = byType["Video"] ?? [], auds = byType["Audio"] ?? [], imgs = byType["Image"] ?? []
        f.duration = n(g, "Duration") > 0 ? n(g, "Duration") : -1
        f.bitrate = n(g, "OverallBitRate")
        f.writer = s(g, "Encoded_Application").replacingOccurrences(of: "Blackmagic Design ", with: "")
        if let v = vids.first ?? imgs.first {
            var c = s(v, "Format")
            let prof = s(v, "Format_Profile")
            if c == "ProRes" || c == "DNxHD" || c == "AVC" || c == "HEVC" || c == "VP9" || c == "AV1" || c == "MPEG Video" {
                if !prof.isEmpty { c += " " + prof }
            }
            f.codec = c
            f.width = Int(n(v, "Width")); f.height = Int(n(v, "Height"))
            f.fps = n(v, "FrameRate") > 0 ? n(v, "FrameRate") : n(g, "FrameRate")
            let bits = s(v, "BitDepth"), chroma = s(v, "ChromaSubsampling")
            f.depth = [bits.isEmpty ? "" : bits + "-bit", chroma].filter { !$0.isEmpty }.joined(separator: " ")
            let hdr = s(v, "HDR_Format_Commercial").isEmpty ? s(v, "HDR_Format") : s(v, "HDR_Format_Commercial")
            let tr = s(v, "transfer_characteristics"), prim = s(v, "colour_primaries"), range = s(v, "colour_range")
            var col: [String] = []
            if !hdr.isEmpty { col.append(hdr) }
            if !prim.isEmpty { col.append(prim == tr || tr.isEmpty ? prim : prim + " / " + tr) }
            if !range.isEmpty { col.append(range) }
            f.colour = col.joined(separator: " ")
            f.scan = s(v, "ScanType")
            if f.bitrate == 0 { f.bitrate = n(v, "BitRate") }
        }
        if let a = auds.first {
            var p = [s(a, "Format") + (s(a, "Format_AdditionalFeatures").isEmpty ? "" : " " + s(a, "Format_AdditionalFeatures"))]
            let ch = s(a, "Channels"); if !ch.isEmpty { p.append(ch + " ch") }
            let sr = n(a, "SamplingRate"); if sr > 0 { p.append(sr.truncatingRemainder(dividingBy: 1000) == 0 ? String(format: "%.0f kHz", sr / 1000) : String(format: "%.1f kHz", sr / 1000)) }
            let bd = s(a, "BitDepth"); if !bd.isEmpty { p.append(bd + "-bit") }
            let br = n(a, "BitRate"); if br > 0 { p.append(rate(br)) }
            if auds.count > 1 { p.append("+\(auds.count - 1) track\(auds.count > 2 ? "s" : "")") }
            f.audio = p.joined(separator: " ")
        }
        for t in tracks where s(t, "@type") == "Other" || s(t, "@type") == "Video" {
            let tc = s(t, "TimeCode_FirstFrame")
            if !tc.isEmpty { f.timecode = tc; break }
        }
        if f.timecode.isEmpty, let tc = g["TimeCode_FirstFrame"] as? String { f.timecode = tc }
        var parts: [String] = []
        for (k, w) in [("Video", "video"), ("Audio", "audio"), ("Text", "text"), ("Image", "image"), ("Menu", "menu"), ("Other", "other")] {
            if let c = byType[k]?.count, c > 0 { parts.append("\(c) \(w)") }
        }
        if vids.count + auds.count > 1 || byType["Text"] != nil { f.tracks = parts.joined(separator: " ") }
        return f
    }
}

// INFO under a line: the report track by track, the name of each field grey and its value white, wrapped, never cut
struct ReportView: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, l in
                if let r = l.range(of: " : ") {
                    let k = l[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                    let v = String(l[r.upperBound...])
                    HStack(alignment: .top, spacing: 8) {
                        Text(k).font(.system(size: 11, design: .monospaced)).foregroundColor(GREY)
                            .frame(width: 210, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        Text(v).font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                } else if !l.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(l.uppercased()).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(AMBER)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.leading, 22).padding(.vertical, 4)
    }
}
