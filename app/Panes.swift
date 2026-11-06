// Panes.swift: the panes, side by side as vertical columns, and the folder sizes.
// v5 (5.11.2026), Marko: "This app will also have 2 windows, left and right, for copying between 2 locations manually.
// And it needs to always next to every folder ... which ... Pathfinder doesn't do. Folder size— what is the folder size?"
// v6 (6.11.2026), Marko: "it can open any number of folders at the same time, creating many vertical windows. Now, for
// this case, only two, and I can double-click any file, and it will open up in its viewer ... multiple views: icon view
// and list view. If I'm in icon view, I have a slider at the top to enlarge icons, or a list view with all details."
// Each pane: PANE n and the free space, BACK | UP | HOME | VOLUMES | HIDDEN, the path (every part a button), ICONS |
// LIST | PREVIEW, and the files: ICONS is a grid of real thumbnails (QuickLookThumbnailing, a video shows a frame) with
// a size slider; LIST is a table NAME · SIZE (folders measured by Sizer) · KIND · MODIFIED · DURATION, every column
// sortable. v8 (6.11.2026): every video, sound and picture also gets its MediaInfo facts (MediaInfo.swift): a details
// column each in LIST (v10: one line per file, the pane scrolls sideways; TIME RES FPS BIT RATE CODEC first). A double click opens a folder, or a file in its own app; Space is Finder's Quick Look (Viewer.swift).
import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

func bytes(_ n: Int64) -> String {
    let v = Double(n)
    if v >= 1e12 { return String(format: "%.2f TB", v / 1e12) }
    if v >= 1e9 { return String(format: "%.2f GB", v / 1e9) }
    if v >= 1e6 { return String(format: "%.1f MB", v / 1e6) }
    if v >= 1e3 { return String(format: "%.0f kB", v / 1e3) }
    return "\(n) B"
}
func duration(_ s: Double) -> String {
    let t = Int(s.rounded())
    return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
}
let DATEFMT: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d.M.yyyy HH:mm"; return f }()

// v21 (6.11.2026), Marko: "while the file is written on the disk, until it's finished ... the file name needs to be updated
// ... in real time showing me how many bytes are coming and what the size of the file is at the moment, and also in
// parentheses, the speed of writing". A file whose size grows from one second to the next is live: its line shows the
// size now, the exact bytes, and (speed). Three quiet seconds and it is a plain file again.
struct Live: Hashable {
    var size: Int64; var speed: Double
    var text: String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        let exact = f.string(from: NSNumber(value: size)) ?? "\(size)"
        return "\(bytes(size)) · \(exact) bytes (\(speed > 0 ? bytes(Int64(speed)) + "/s" : "0 B/s"))"
    }
}

struct Item: Identifiable, Hashable {
    let path: String; let name: String; let isDir: Bool; let isLink: Bool; let size: Int64; let mtime: Date
    let kind: String; let isMedia: Bool
    var id: String { path }
}

// one line of a pane as it is shown and sorted: the folder's measured size (-1 while unknown), the media's duration
struct Row: Identifiable, Hashable {
    let path: String; let name: String; let isDir: Bool; let isLink: Bool
    let size: Int64; let kind: String; let mtime: Date; let duration: Double
    var media: MediaFacts? = nil
    var live: Live? = nil
    var id: String { path }
    var shownName: String { live.map { name + "   " + $0.text } ?? name }
    var pixels: Int { (media?.width ?? 0) * (media?.height ?? 0) }
    var sizeText: String { isLink ? "link" : size < 0 ? "…" : bytes(size) }
}

// Folder sizes: the logical bytes of every file inside (the same count a copy makes), two folders at a time, in the
// background. A size is measured again when the folder's date changes, or when it is older than two minutes.
final class Sizer: ObservableObject {
    static let shared = Sizer()
    @Published var sizes: [String: Int64] = [:]
    private var seen: [String: (Date, Date)] = [:]          // path -> (folder date when measured, measured at)
    private var busy = Set<String>()
    private let q: OperationQueue = {
        let q = OperationQueue(); q.maxConcurrentOperationCount = 2; q.qualityOfService = .utility; return q
    }()
    func want(_ path: String, mtime: Date, maxAge: TimeInterval = 120) {
        if busy.contains(path) { return }
        if let s = seen[path], s.0 == mtime, Date().timeIntervalSince(s.1) < maxAge, sizes[path] != nil { return }
        busy.insert(path)
        q.addOperation {
            let n = Sizer.measure(path)
            DispatchQueue.main.async { self.sizes[path] = n; self.seen[path] = (mtime, Date()); self.busy.remove(path) }
        }
    }
    static func measure(_ path: String) -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: keys,
                                                     options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in e {
            if let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true { total += Int64(v.fileSize ?? 0) }
        }
        return total
    }
}

// The duration of a video or a sound: read from its header (AVURLAsset), two at a time, once per file and date
final class Durations: ObservableObject {
    static let shared = Durations()
    @Published var d: [String: Double] = [:]
    private var busy = Set<String>()
    private let q: OperationQueue = {
        let q = OperationQueue(); q.maxConcurrentOperationCount = 2; q.qualityOfService = .utility; return q
    }()
    func want(_ path: String, mtime: Date) {
        let key = path + "|\(mtime.timeIntervalSince1970)"
        if d[key] != nil || busy.contains(key) { return }
        busy.insert(key)
        q.addOperation {
            let s = CMTimeGetSeconds(AVURLAsset(url: URL(fileURLWithPath: path)).duration)
            DispatchQueue.main.async { self.d[key] = s.isFinite && s > 0 ? s : 0; self.busy.remove(key) }
        }
    }
    func of(_ path: String, _ mtime: Date) -> Double { d[path + "|\(mtime.timeIntervalSince1970)"] ?? -1 }
}

final class Pane: ObservableObject, Identifiable {
    var index: Int
    @Published var path: String
    @Published var items: [Item] = []
    @Published var selection = Set<String>()
    @Published var showHidden = false
    @Published var filter = ""                              // v11: the box next to NAME; not remembered
    @Published var free = ""
    @Published var live: [String: Live] = [:]              // v21: files growing right now
    private var last: [String: (Int64, Date)] = [:]
    private var quiet: [String: Int] = [:]
    private var liveTimer: Timer?
    @Published var mode: String { didSet { UserDefaults.standard.set(mode, forKey: "pane.\(index).mode") } }
    @Published var iconSize: Double { didSet { UserDefaults.standard.set(iconSize, forKey: "pane.\(index).icon") } }
    @Published var preview: Bool { didSet { UserDefaults.standard.set(preview, forKey: "pane.\(index).preview") } }
    @Published var sortKey: String { didSet { UserDefaults.standard.set(sortKey, forKey: "pane.\(index).sort") } }
    @Published var ascending: Bool { didSet { UserDefaults.standard.set(ascending, forKey: "pane.\(index).asc") } }
    var columns = 1                                         // icons per row in ICONS (for ↑ ↓)
    var anchor: String?                                     // where a shift click starts
    private var back: [String] = []
    private var source: DispatchSourceFileSystemObject?
    private var pending = false
    private var timer: Timer?
    private var pendingPreview: DispatchWorkItem?

    init(index: Int, start: String) {
        self.index = index
        let d = UserDefaults.standard
        path = FileManager.default.fileExists(atPath: start) ? start : NSHomeDirectory()
        mode = d.string(forKey: "pane.\(index).mode") ?? "list"
        iconSize = d.object(forKey: "pane.\(index).icon") as? Double ?? 128
        preview = d.bool(forKey: "pane.\(index).preview")
        sortKey = d.string(forKey: "pane.\(index).sort") ?? "name"
        ascending = d.object(forKey: "pane.\(index).asc") as? Bool ?? true
        load()
        // the sizes are measured again while the pane is open (a copy filling a folder, a file added deep inside)
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.load() }
        // every second: which files are growing (common run loop mode, so it also runs while a list is scrolled)
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        liveTimer = t
    }
    deinit { timer?.invalidate(); liveTimer?.invalidate(); source?.cancel() }

    func tick() {
        let now = Date(); var nl = live; var finished = false
        let files = items.filter { !$0.isDir && !$0.isLink }.prefix(3000)
        for i in files {
            guard let a = try? FileManager.default.attributesOfItem(atPath: i.path),
                  let n = (a[.size] as? NSNumber)?.int64Value else { continue }
            guard let p = last[i.path] else { last[i.path] = (n, now); continue }
            if n != p.0 {
                let dt = max(0.2, now.timeIntervalSince(p.1))
                nl[i.path] = Live(size: n, speed: max(0, Double(n - p.0) / dt))
                last[i.path] = (n, now); quiet[i.path] = 0
            } else if nl[i.path] != nil {
                let q = (quiet[i.path] ?? 0) + 1; quiet[i.path] = q
                if q >= 3 { nl[i.path] = nil; finished = true } else { nl[i.path] = Live(size: n, speed: 0) }
            }
        }
        let here = Set(files.map { $0.path })
        for k in last.keys where !here.contains(k) { last[k] = nil; quiet[k] = nil; nl[k] = nil }
        if nl != live { live = nl }
        if finished { load() }
    }

    func go(_ p: String, remember: Bool = true) {
        guard p != path else { load(); return }
        if remember { back.append(path) }
        path = p; selection = []
        Panes.shared.save()
        load()
    }
    func up() {
        let parent = (path as NSString).deletingLastPathComponent
        if !parent.isEmpty && parent != path { go(parent) }
    }
    func goBack() { if let p = back.popLast() { go(p, remember: false) } }

    func load() {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey,
                                      .localizedTypeDescriptionKey, .contentTypeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: keys,
                                                                 options: showHidden ? [] : [.skipsHiddenFiles])) ?? []
        var out: [Item] = []
        for u in urls {
            let v = try? u.resourceValues(forKeys: Set(keys))
            let link = v?.isSymbolicLink ?? false
            var dir = v?.isDirectory ?? false
            if link { var d: ObjCBool = false; if FileManager.default.fileExists(atPath: u.path, isDirectory: &d) { dir = d.boolValue } }
            let media = !dir && ((v?.contentType.map { $0.conforms(to: .audiovisualContent) || $0.conforms(to: .image) } ?? false)
                                 || Media.isMedia(u.lastPathComponent))
            out.append(Item(path: u.path, name: u.lastPathComponent, isDir: dir, isLink: link,
                            size: Int64(v?.fileSize ?? 0), mtime: v?.contentModificationDate ?? .distantPast,
                            kind: v?.localizedTypeDescription ?? (dir ? "Folder" : ""), isMedia: media))
        }
        out.sort { a, b in a.isDir != b.isDir ? a.isDir : a.name.localizedStandardCompare(b.name) == .orderedAscending }
        if out != items { items = out }
        let keep = selection.filter { s in out.contains { $0.path == s } }
        if keep != selection { selection = keep }
        let f = freeSpace()
        if f != free { free = f }
        watch()
        for i in out where i.isDir && !i.isLink { Sizer.shared.want(i.path, mtime: i.mtime) }
        for i in out where i.isMedia {
            if Media.binary != nil { Media.shared.want(i.path, mtime: i.mtime) } else { Durations.shared.want(i.path, mtime: i.mtime) }
        }
    }
    private func freeSpace() -> String {
        let u = URL(fileURLWithPath: path)
        if let v = try? u.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let n = v.volumeAvailableCapacityForImportantUsage, n > 0 { return bytes(n) + " free" }
        if let v = try? u.resourceValues(forKeys: [.volumeAvailableCapacityKey]), let n = v.volumeAvailableCapacity { return bytes(Int64(n)) + " free" }
        return ""
    }
    // the folder on screen is watched: a file added, removed or renamed reloads the list half a second later
    private var watched = ""
    private func watch() {
        if watched == path && source != nil { return }
        source?.cancel(); source = nil; watched = path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .main)
        s.setEventHandler { [weak self] in
            guard let self = self, !self.pending else { return }
            self.pending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.pending = false; self.load() }
        }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
    }

    // a click on a column title: the same column turns the order round, another sorts by it (sizes, dates and
    // durations biggest and newest first, as Finder does)
    func sortBy(_ key: String) {
        if sortKey == key { ascending.toggle() } else { sortKey = key; ascending = !["size", "date", "duration", "res", "fps", "rate"].contains(key) }
    }
    static func less(_ key: String, _ a: Row, _ b: Row) -> Bool {
        switch key {
        case "size": if a.size != b.size { return a.size < b.size }
        case "kind": let c = a.kind.localizedStandardCompare(b.kind); if c != .orderedSame { return c == .orderedAscending }
        case "date": if a.mtime != b.mtime { return a.mtime < b.mtime }
        case "duration": if a.duration != b.duration { return a.duration < b.duration }
        case "codec": let c = (a.media?.codec ?? "").localizedStandardCompare(b.media?.codec ?? ""); if c != .orderedSame { return c == .orderedAscending }
        case "res": if a.pixels != b.pixels { return a.pixels < b.pixels }
        case "fps": if (a.media?.fps ?? 0) != (b.media?.fps ?? 0) { return (a.media?.fps ?? 0) < (b.media?.fps ?? 0) }
        case "rate": if (a.media?.bitrate ?? 0) != (b.media?.bitrate ?? 0) { return (a.media?.bitrate ?? 0) < (b.media?.bitrate ?? 0) }
        case "name": break
        default:
            if let c = LCOLS.first(where: { $0.key == key }) {
                let x = c.text(a), y = c.text(b)
                if x.isEmpty != y.isEmpty { return y.isEmpty }       // the empty ones last
                let o = x.localizedStandardCompare(y); if o != .orderedSame { return o == .orderedAscending }
            }
        }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
    // the lines in the order on screen: sorted by the column chosen; by name, the folders first (as before)
    var rows: [Row] {
        let sizes = Sizer.shared.sizes, durs = Durations.shared, mi = Media.shared
        let key = sortKey, up = ascending
        var r: [Row] = items.map { i in
            let f = i.isMedia ? mi.of(i.path, i.mtime) : nil
            // the duration from MediaInfo; a picture has none; while it is read, "…"
            let dur: Double = !i.isMedia ? -1 : Media.binary == nil ? durs.of(i.path, i.mtime)
                : f.map { $0.duration > 0 ? $0.duration : -1 } ?? 0
            let lv = i.isDir ? nil : live[i.path]
            return Row(path: i.path, name: i.name, isDir: i.isDir, isLink: i.isLink,
                       size: i.isLink ? 0 : i.isDir ? (sizes[i.path] ?? -1) : lv?.size ?? i.size, kind: i.kind, mtime: i.mtime,
                       duration: dur, media: f, live: lv)
        }
        let words = filter.lowercased().split(separator: " ").map(String.init)
        if !words.isEmpty { r = r.filter { Pane.matches($0.name, words) } }
        r.sort { a, b in up ? Pane.less(key, a, b) : Pane.less(key, b, a) }
        if key == "name" { r = r.filter { $0.isDir } + r.filter { !$0.isDir } }
        return r
    }
    // v11 (Marko 6.11.2026: "next to the name ... add a text box. The text box is a simple filter"): every word typed must
    // be in the name, any case; * and ? work as in a shell pattern (*_9x16.mp4)
    static func matches(_ name: String, _ words: [String]) -> Bool {
        let n = name.lowercased()
        return words.allSatisfy { w in
            w.contains("*") || w.contains("?") ? fnmatch("*" + w + "*", n, 0) == 0 : n.contains(w)
        }
    }
    var selectedBytes: Int64 {
        items.filter { selection.contains($0.path) }.reduce(Int64(0)) { t, i in t + (i.isDir ? (Sizer.shared.sizes[i.path] ?? 0) : i.size) }
    }
    var selectedFile: String? {
        let files = rows.filter { selection.contains($0.path) && !$0.isDir }
        return files.first?.path
    }

    // a click in ICONS: alone selects, ⌘ adds or takes away, ⇧ selects from the last click to here
    func click(_ p: String) {
        let m = NSEvent.modifierFlags
        if m.contains(.command) {
            if selection.contains(p) { selection.remove(p) } else { selection.insert(p) }
        } else if m.contains(.shift), let a = anchor {
            let order = rows.map { $0.path }
            if let i = order.firstIndex(of: a), let j = order.firstIndex(of: p) { selection = Set(order[min(i, j)...max(i, j)]) }
        } else { selection = [p] }
        anchor = p
        Panes.shared.active = index
    }
    // ← → ↑ ↓ in ICONS, and ↑ ↓ in the full-screen preview (files only there, so it goes from video to video)
    func move(_ by: Int, filesOnly: Bool = false) {
        let rs = rows.filter { !filesOnly || !$0.isDir }
        guard !rs.isEmpty else { return }
        let cur = rs.firstIndex { selection.contains($0.path) }
        var n = cur.map { $0 + by } ?? (by > 0 ? 0 : rs.count - 1)
        n = max(0, min(rs.count - 1, n))
        selection = [rs[n].path]; anchor = rs[n].path
    }
    // a double click: a folder is entered, a file opens in its own app
    func openItems(_ sel: Set<String>) {
        pendingPreview?.cancel(); pendingPreview = nil
        guard let p = sel.first, let it = items.first(where: { $0.path == p }) else { return }
        if sel.count == 1 && it.isDir { go(it.isLink ? URL(fileURLWithPath: p).resolvingSymlinksInPath().path : p); return }
        for s in sel where !(items.first(where: { $0.path == s })?.isDir ?? true) { NSWorkspace.shared.open(URL(fileURLWithPath: s)) }
    }
    // PREVIEW on: one click on a file opens it full screen, once it is clear the click is not a double click
    func selectionChanged() {
        if !selection.isEmpty { Panes.shared.active = index }
        if InfoWindow.visible && !selection.isEmpty { InfoWindow.refresh(self) }
        if QL.shared.visible { QL.shared.follow(self); return }
        guard preview, selection.count == 1, selectedFile != nil else { return }
        pendingPreview?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingPreview = nil
            if self.selectedFile != nil && !QL.shared.visible { QL.shared.show(self, full: true) }
        }
        pendingPreview = w
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval + 0.05, execute: w)
    }
    func state() -> [String: Any] {
        ["pane": index + 1, "path": path, "mode": mode, "icon_size": Int(iconSize), "preview": preview,
         "sort": sortKey + (ascending ? " up" : " down"),
         "live": live.map { ["path": $0.key, "size": $0.value.size, "speed": Int($0.value.speed)] },
         "items": items.count, "shown": rows.count, "filter": filter, "selected": rows.filter { selection.contains($0.path) }.map { $0.path }]
    }
}

// All the panes, left to right. Their folders are remembered (the v5 left and right ones become panes 1 and 2).
final class Panes: ObservableObject {
    static let shared = Panes()
    @Published var list: [Pane] = []
    @Published var active = 0
    init() {
        let d = UserDefaults.standard
        let paths = d.stringArray(forKey: "panes.paths")
            ?? [d.string(forKey: "pane.left") ?? NSHomeDirectory(), d.string(forKey: "pane.right") ?? "/Volumes"]
        list = (paths.isEmpty ? [NSHomeDirectory(), "/Volumes"] : paths).enumerated().map { Pane(index: $0.offset, start: $0.element) }
    }
    func save() { UserDefaults.standard.set(list.map { $0.path }, forKey: "panes.paths") }
    // v12 (Marko 6.11.2026: "for the line between panes, please let me drag it left, right, whatever is needed"): the
    // share of the width each pane has (adds up to 1), set by dragging the line between two panes, remembered; a double
    // click on a line shares the width equally again. A pane added or taken away starts equal again.
    @Published var share: [Double] = UserDefaults.standard.array(forKey: "panes.share") as? [Double] ?? []
    func weights() -> [Double] {
        let n = list.count
        guard share.count == n, share.allSatisfy({ $0 > 0 }) else { return Array(repeating: 1.0 / Double(max(n, 1)), count: n) }
        let t = share.reduce(0, +)
        return share.map { $0 / t }
    }
    func setShare(_ w: [Double]) { share = w; UserDefaults.standard.set(w, forKey: "panes.share") }
    func equalShare() { share = []; UserDefaults.standard.removeObject(forKey: "panes.share") }
    // the panes become these folders, one column each (dlmon.py view open)
    func open(_ folders: [String]) {
        guard !folders.isEmpty else { return }
        if QL.shared.visible { QL.shared.close() }
        if folders.count != list.count { equalShare() }
        list = folders.enumerated().map { Pane(index: $0.offset, start: $0.element) }
        active = 0
        save()
    }
    static let maxPanes = 5
    // v14: the panes button counts 1 to 5 (and round), a long press asks for the number
    func setCount(_ n: Int) {
        let n = max(1, min(Panes.maxPanes, n))
        while list.count > n { removeLast() }
        while list.count < n { add() }
    }
    func add(_ folder: String? = nil) {
        guard list.count < Panes.maxPanes else { return }
        let start = folder ?? (list.indices.contains(active) ? list[active].path : NSHomeDirectory())
        list.append(Pane(index: list.count, start: start))
        equalShare()
        save()
    }
    func removeLast() {
        guard list.count > 1 else { return }
        if QL.shared.pane === list.last { QL.shared.close() }
        list.removeLast()
        equalShare()
        active = min(active, list.count - 1)
        save()
    }
    var activePane: Pane? { list.indices.contains(active) ? list[active] : list.first }
    // pane n (1-based) or, without a number, every pane
    func pick(_ n: Int?) -> [Pane] {
        guard let n = n else { return list }
        return list.indices.contains(n - 1) ? [list[n - 1]] : []
    }
}

// a row of words that wraps when the pane is narrow, so nothing is ever cut (never-cut-text)
struct Flow: Layout {
    var spacing: CGFloat = 2
    var line: CGFloat = 2
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > w { x = 0; y += row + line; row = 0 }
            x += z.width + spacing; maxX = max(maxX, x); row = max(row, z.height)
        }
        return CGSize(width: w.isFinite ? w : maxX, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > b.minX && x + z.width > b.maxX { x = b.minX; y += row + line; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + spacing; row = max(row, z.height)
        }
    }
}

struct PaneView: View {
    @ObservedObject var pane: Pane
    @ObservedObject var panes = Panes.shared
    @ObservedObject var sizer = Sizer.shared
    @ObservedObject var durs = Durations.shared
    @ObservedObject var media = Media.shared
    @ObservedObject var dash = Dash.shared
    var n: Int { pane.index + 1 }
    var isActive: Bool { panes.active == pane.index }

    // the path, every folder in it a button, parted by a grey > (swift-apps.md)
    var crumbs: some View {
        let parts = pane.path.split(separator: "/").map(String.init)
        return Flow(spacing: 0) {
            Word(text: "/", on: false) { pane.go("/") }.accessibilityIdentifier("path-\(n)-0")
            ForEach(Array(parts.enumerated()), id: \.offset) { k, name in
                if k > 0 { Text(">").font(.system(size: 12, design: .monospaced)).foregroundColor(GREY.opacity(0.6)).accessibilityHidden(true) }
                Button(action: { pane.go("/" + parts[0...k].joined(separator: "/")) }) { Text(name).fixedSize() }
                    .buttonStyle(CrumbStyle(last: k == parts.count - 1))
                    .accessibilityLabel(name).accessibilityIdentifier("path-\(n)-\(k + 1)")
            }
        }
    }

    var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button(action: { panes.active = pane.index }) { Text("PANE \(n)").fixedSize() }
                .buttonStyle(WordStyle(on: isActive, size: 11))
                .help("The active pane: COPY → and MOVE → start here").accessibilityLabel("Pane \(n)")
                .accessibilityIdentifier("pane-\(n)").accessibilityValue(isActive ? "active" : "")
            Spacer(minLength: 8)
            Text(pane.free).font(.system(size: 11, design: .monospaced)).foregroundColor(GREY).fixedSize()
        }
    }
    var nav: some View {
        Flow {
            Word(text: "BACK", on: false) { pane.goBack() }.accessibilityIdentifier("back-\(n)")
            Bar_()
            Word(text: "UP", on: false) { pane.up() }.accessibilityIdentifier("up-\(n)")
            Bar_()
            Word(text: "HOME", on: false) { pane.go(NSHomeDirectory()) }.accessibilityIdentifier("home-\(n)")
            Bar_()
            Word(text: "VOLUMES", on: false) { pane.go("/Volumes") }.accessibilityIdentifier("volumes-\(n)")
            Bar_()
            Word(text: "HIDDEN", on: pane.showHidden) { pane.showHidden.toggle(); pane.load() }.accessibilityIdentifier("hidden-\(n)")
        }
    }
    var views: some View {
        Flow {
            Word(text: "ICONS", on: pane.mode == "icons") { pane.mode = "icons" }.accessibilityIdentifier("icons-\(n)")
            Bar_()
            Word(text: "LIST", on: pane.mode == "list") { pane.mode = "list" }.accessibilityIdentifier("list-\(n)")
            Bar_()
            Word(text: "PREVIEW", on: pane.preview) { pane.preview.toggle() }.accessibilityIdentifier("preview-\(n)")
                .help("On: one click on a file opens it full screen, ↑ ↓ go to the file before and after, Escape closes")
        }
    }
    var slider: some View {
        HStack(spacing: 8) {
            Text("SIZE").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(GREY).fixedSize()
            Slider(value: $pane.iconSize, in: 48...512).controlSize(.small)
                .accessibilityLabel("Icon size").accessibilityIdentifier("size-\(n)").accessibilityValue("\(Int(pane.iconSize))")
            Text("\(Int(pane.iconSize))").font(.system(size: 11, design: .monospaced)).foregroundColor(GREY).frame(width: 34, alignment: .trailing)
        }
    }
    var footer: some View {
        Text(pane.selection.isEmpty ? "\(pane.items.count) items · double click opens · Space previews"
             : "\(pane.selection.count) selected · \(bytes(pane.selectedBytes)) · Space previews")
            .font(.system(size: 11, design: .monospaced)).foregroundColor(GREY).fixedSize(horizontal: false, vertical: true)
    }
    // every part of the pane is on the DASHBOARD (v7): NAV (the PANE n line and BACK … HIDDEN), PATH, VIEWS, STATUS
    var body: some View {
        let rows = pane.rows
        VStack(alignment: .leading, spacing: 6) {
            if dash.shown("nav") { header; nav }
            if dash.shown("path") { crumbs }
            if dash.shown("views") { views }
            if pane.mode == "icons" {
                if dash.shown("views") { slider }
                HStack { FilterBox(pane: pane); Spacer() }
                IconsView(pane: pane, rows: rows)
            } else {
                ListView(pane: pane, rows: rows)
            }
            if dash.shown("status") { footer }
        }
        .padding(.horizontal, 6)
        .onChange(of: pane.selection) { _ in pane.selectionChanged() }
    }
}

struct CrumbStyle: ButtonStyle {
    let last: Bool
    func makeBody(configuration: Configuration) -> some View { CrumbFace(label: configuration.label, pressed: configuration.isPressed, last: last) }
}
struct CrumbFace<L: View>: View {
    let label: L; let pressed: Bool; let last: Bool
    @State private var hover = false
    var body: some View {
        label.font(.system(size: 12, design: .monospaced))
            .foregroundColor(pressed ? RED : hover ? ORANGE : last ? .white : Color(white: 0.75))
            .padding(.horizontal, 3).padding(.vertical, 2).contentShape(Rectangle())
            .onHover { h in hover = h; if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
}

// LIST (v10, Marko 6.11.2026: "my media info wants to be only in one line, same as the file name without report. I need
// to have a horizontal scroller to see all this data, but don't break the lines. I want to have each file on one line"
// and "the most important field is time ... Then resolution, then frame per second, then bitrate, and then codec").
// Every file is one line, nothing wraps: NAME, then TIME RES FPS BIT RATE CODEC, then SIZE and every other MediaInfo
// fact, each its own column as wide as its longest value; the pane scrolls sideways to reach them. Every title sorts.
struct LCol {
    let key: String; let title: String; let right: Bool; let text: (Row) -> String
}
let LCOLS: [LCol] = [
    LCol(key: "duration", title: "TIME", right: true) { r in r.duration > 0 ? duration(r.duration) : r.duration == -1 ? "" : "…" },
    LCol(key: "res", title: "RES", right: true) { $0.media?.res ?? "" },
    LCol(key: "fps", title: "FPS", right: true) { $0.media?.fpsText ?? "" },
    LCol(key: "rate", title: "BIT RATE", right: true) { $0.media?.rateText ?? "" },
    LCol(key: "codec", title: "CODEC", right: false) { $0.media?.codec ?? "" },
    LCol(key: "size", title: "SIZE", right: true) { $0.sizeText },
    LCol(key: "depth", title: "DEPTH", right: false) { $0.media?.depth ?? "" },
    LCol(key: "colour", title: "COLOUR", right: false) { $0.media?.colour ?? "" },
    LCol(key: "scan", title: "SCAN", right: false) { $0.media?.scan ?? "" },
    LCol(key: "audio", title: "AUDIO", right: false) { $0.media?.audio ?? "" },
    LCol(key: "tc", title: "TIMECODE", right: false) { $0.media?.timecode ?? "" },
    LCol(key: "writer", title: "WRITTEN BY", right: false) { $0.media?.writer ?? "" },
    LCol(key: "tracks", title: "TRACKS", right: false) { $0.media?.tracks ?? "" },
    LCol(key: "kind", title: "KIND", right: false) { $0.kind },
    LCol(key: "date", title: "MODIFIED", right: false) { DATEFMT.string(from: $0.mtime) },
]
let MONO = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
let HEADF = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
func textWidth(_ s: String, _ f: NSFont) -> CGFloat { ceil((s as NSString).size(withAttributes: [.font: f]).width) }

// the filter box: type, and only the files whose name has the words stay; Escape or ✕ empties it
struct FilterBox: View {
    @ObservedObject var pane: Pane
    var body: some View {
        HStack(spacing: 4) {
            TextField("filter", text: $pane.filter).textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced)).foregroundColor(.white)
                .onExitCommand { pane.filter = "" }
                .accessibilityLabel("Filter").accessibilityIdentifier("filter-\(pane.index + 1)")
            if !pane.filter.isEmpty {
                Button(action: { pane.filter = "" }) { Text("✕").foregroundColor(GREY) }.buttonStyle(.plain)
                    .accessibilityLabel("Clear filter").accessibilityIdentifier("filter-clear-\(pane.index + 1)")
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 2).frame(width: 150)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.16)))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(pane.filter.isEmpty ? Color(white: 0.25) : GREEN, lineWidth: 1))
    }
}

// the right-click menu of a file: PREVIEW (as big as the screen allows, no black bars), then the columns
struct FileMenu: View {
    let pane: Pane; let sel: Set<String>
    var body: some View {
        if let f = sel.first, sel.count == 1, !(pane.rows.first { $0.path == f }?.isDir ?? true) {
            Button("Preview") {
                pane.selection = sel; pane.anchor = f; Panes.shared.active = pane.index
                QL.shared.show(pane, full: true)
            }
            Divider()
        }
        ColumnMenu()
    }
}

struct ListView: View {
    @ObservedObject var pane: Pane
    @ObservedObject var media = Media.shared
    @ObservedObject var prefs = ColumnPrefs.shared
    let rows: [Row]
    func head(_ title: String, _ key: String) -> some View {
        let on = pane.sortKey == key
        let label = on ? title + (pane.ascending ? " ▲" : " ▼") : title
        return Word(text: label, on: on, size: 10) { pane.sortBy(key) }
            .accessibilityIdentifier("sort-\(pane.index + 1)-\(key)")
    }
    // each column as wide as its longest value or its title (with room for ▲); a column empty for every line goes
    func widths() -> (CGFloat, [(LCol, CGFloat)]) {
        let nameW = min(900, max(230, rows.map { textWidth($0.shownName, NSFont.systemFont(ofSize: 13)) }.max() ?? 0) + 30)
        var out: [(LCol, CGFloat)] = []
        for c in prefs.visible() {
            let vals = rows.map { c.text($0) }
            // before Marko chooses his own columns, one empty for the whole folder is left out; once he chooses, it stays
            if !prefs.custom && c.key != "duration" && c.key != "size" && c.key != "date" && c.key != "kind" && vals.allSatisfy({ $0.isEmpty }) { continue }
            let w = max(textWidth(c.title + " ▲", HEADF) + 14, vals.map { textWidth($0, MONO) }.max() ?? 0)
            out.append((c, w + 4))
        }
        return (nameW, out)
    }
    var body: some View {
        let (nameW, cols) = widths()
        let total = nameW + cols.reduce(0) { $0 + $1.1 + 12 } + 40
        GeometryReader { g in
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        HStack(spacing: 8) {
                            head("NAME", "name")
                            FilterBox(pane: pane)
                        }.frame(width: nameW, alignment: .leading)
                        ForEach(cols, id: \.0.key) { c, w in head(c.title, c.key).frame(width: w, alignment: c.right ? .trailing : .leading) }
                    }.padding(.leading, 12).padding(.bottom, 2)
                    .contentShape(Rectangle()).contextMenu { ColumnMenu() }
                    Line()
                    List(selection: $pane.selection) {
                        ForEach(rows) { r in ListRow(r: r, nameW: nameW, cols: cols).tag(r.path) }
                    }
                    .contextMenu(forSelectionType: String.self, menu: { sel in FileMenu(pane: pane, sel: sel) }, primaryAction: { sel in pane.openItems(sel) })
                    .scrollContentBackground(.hidden).background(Color(white: 0.07))
                    .accessibilityIdentifier("list-of-\(pane.index + 1)")
                }
                .frame(width: max(total, g.size.width), height: g.size.height, alignment: .topLeading)
            }
        }
    }
}

struct ListRow: View {
    let r: Row; let nameW: CGFloat; let cols: [(LCol, CGFloat)]
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 6) {
                Image(nsImage: Thumbs.icon(r.path)).resizable().frame(width: 16, height: 16)
                Text(r.name).font(.system(size: 13)).foregroundColor(.white).lineLimit(1).fixedSize()
                if let lv = r.live {
                    Text(lv.text).font(.system(size: 13).monospacedDigit()).foregroundColor(AMBER).lineLimit(1).fixedSize()
                }
            }.frame(width: nameW, alignment: .leading)
            ForEach(cols, id: \.0.key) { c, w in
                Text(c.text(r)).font(.system(size: 12, design: .monospaced))
                    .foregroundColor(c.key == "size" && r.isDir ? AMBER : c.key == "duration" ? .white : GREY)
                    .lineLimit(1).fixedSize().frame(width: w, alignment: c.right ? .trailing : .leading)
            }
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
    }
}

struct IconsView: View {
    @ObservedObject var pane: Pane
    let rows: [Row]
    var cell: CGFloat { CGFloat(pane.iconSize) + 16 }
    func fit(_ w: CGFloat) { pane.columns = max(1, Int((w - 8) / (cell + 8))) }

    func one(_ r: Row) -> some View {
        let p = pane
        let path: String = r.path
        let face = IconCell(r: r, size: CGFloat(p.iconSize), selected: p.selection.contains(path))
        let tapped = face.id(path)
            .gesture(TapGesture(count: 2).onEnded { p.openItems([path]) })
            .simultaneousGesture(TapGesture().onEnded { p.click(path) })
        let named = tapped.accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(r.name))
            .accessibilityValue(Text(r.sizeText))
            .accessibilityAddTraits(.isButton)
        let ident: String = "item-\(p.index + 1)-\(r.name)"
        return named.contextMenu {
            if !r.isDir { Button("Preview") { p.selection = [path]; p.anchor = path; Panes.shared.active = p.index; QL.shared.show(p, full: true) } }
        }.accessibilityIdentifier(ident)
            .accessibilityAction { p.selection = [path] }
    }

    var grid: some View {
        let cols: [GridItem] = [GridItem(.adaptive(minimum: cell, maximum: cell), spacing: 8, alignment: .top)]
        return LazyVGrid(columns: cols, alignment: .leading, spacing: 10) {
            ForEach(rows) { r in one(r) }
        }.padding(8)
    }

    func scrolled(_ proxy: ScrollViewProxy) -> some View {
        ScrollView { grid }
            .onChange(of: pane.selection) { s in
                guard s.count == 1, let target = s.first else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(target) }
            }
    }

    var body: some View {
        GeometryReader { g in
            ScrollViewReader { proxy in scrolled(proxy) }
                .onAppear { fit(g.size.width) }
                .onChange(of: g.size.width) { w in fit(w) }
                .onChange(of: pane.iconSize) { _ in fit(g.size.width) }
        }
        .background(Color(white: 0.07))
    }
}

struct IconCell: View {
    let r: Row; let size: CGFloat; let selected: Bool
    @State private var img: NSImage?
    var bucket: CGFloat { size <= 64 ? 64 : size <= 128 ? 128 : size <= 256 ? 256 : 512 }
    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: img ?? Thumbs.icon(r.path)).resizable().aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
            Text(r.name).font(.system(size: 11)).foregroundColor(.white).multilineTextAlignment(.center)
                .frame(maxWidth: size + 8).fixedSize(horizontal: false, vertical: true)
            if let lv = r.live {
                Text(lv.text).font(.system(size: 10, design: .monospaced)).foregroundColor(AMBER)
                    .multilineTextAlignment(.center).frame(maxWidth: size + 8).fixedSize(horizontal: false, vertical: true)
            }
            Text(r.isDir ? r.sizeText : r.duration > 0 ? "\(r.sizeText) · \(duration(r.duration))" : r.sizeText)
                .font(.system(size: 10, design: .monospaced)).foregroundColor(r.isDir ? AMBER : GREY).fixedSize()
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? BLUE.opacity(0.35) : Color.clear))
        .contentShape(Rectangle())
        .onAppear { load() }
        .onChange(of: bucket) { _ in load() }
    }
    private func load() {
        let p = r.path, b = bucket
        Thumbs.thumb(p, b, r.mtime) { i in if p == r.path { img = i } }
    }
}

// the grey pipe between neighbouring action words (swift-apps.md, "Buttons light under the mouse")
struct Bar_: View {
    var body: some View { Text("|").font(.system(size: 12, design: .monospaced)).foregroundColor(GREY.opacity(0.6)).accessibilityHidden(true) }
}

// the line between two panes: grab it and drag left or right; the two panes beside it give and take width (each keeps
// at least 200 pt); a double click shares the width equally again
struct PaneDivider: View {
    let left: Int; let room: CGFloat
    @ObservedObject var panes = Panes.shared
    @State private var start: [Double]?
    @State private var hover = false
    var body: some View {
        Rectangle().fill(Color.clear).frame(width: 9)
            .overlay(Rectangle().fill(hover || start != nil ? ORANGE : Color(white: 0.2)).frame(width: hover || start != nil ? 3 : 1))
            .contentShape(Rectangle())
            .onHover { h in
                hover = h
                if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in
                    if start == nil { start = panes.weights() }
                    guard var w = start, left + 1 < w.count else { return }
                    let sum = w[left] + w[left + 1]
                    let minF = min(Double(200 / room), sum / 2)
                    let l = max(minF, min(sum - minF, w[left] + Double(v.translation.width / room)))
                    w[left] = l; w[left + 1] = sum - l
                    panes.setShare(w)
                }
                .onEnded { _ in start = nil })
            .simultaneousGesture(TapGesture(count: 2).onEnded { panes.equalShare() })
            .accessibilityElement(children: .ignore).accessibilityLabel("Divider \(left + 1)")
            .accessibilityIdentifier("divider-\(left + 1)")
            .help("Drag to make the panes wider or narrower; double click shares the width equally")
    }
}
