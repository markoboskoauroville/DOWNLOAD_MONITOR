// Panes.swift: the two panes, left and right, and the folder sizes (v5, 5.11.2026).
// Marko: "This app will also have 2 windows, left and right, for copying between 2 locations manually. And it needs to
// always next to every folder ... which ... Pathfinder doesn't do. Folder size— what is the folder size?"
// Each pane: its path, BACK | UP | HOME | VOLUMES | HIDDEN, the free space of its disk, and a list where every folder
// shows its whole size (measured in the background by Sizer, "…" until known, measured again when it changes) and every
// file its size. A double click opens a folder (or a file in its app). COPY → / MOVE → / ← COPY / ← MOVE put the
// selected items into the one queue, into the other pane's folder.
import SwiftUI
import AppKit

func bytes(_ n: Int64) -> String {
    let v = Double(n)
    if v >= 1e12 { return String(format: "%.2f TB", v / 1e12) }
    if v >= 1e9 { return String(format: "%.2f GB", v / 1e9) }
    if v >= 1e6 { return String(format: "%.1f MB", v / 1e6) }
    if v >= 1e3 { return String(format: "%.0f kB", v / 1e3) }
    return "\(n) B"
}

struct Item: Identifiable, Hashable {
    let path: String; let name: String; let isDir: Bool; let isLink: Bool; let size: Int64; let mtime: Date
    var id: String { path }
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

final class Pane: ObservableObject {
    let key: String
    @Published var path: String
    @Published var items: [Item] = []
    @Published var selection = Set<String>()
    @Published var showHidden = false
    @Published var free = ""
    private var back: [String] = []
    private var source: DispatchSourceFileSystemObject?
    private var pending = false
    private var timer: Timer?

    init(key: String, start: String) {
        self.key = key
        let saved = UserDefaults.standard.string(forKey: "pane.\(key)") ?? start
        path = FileManager.default.fileExists(atPath: saved) ? saved : start
        load()
        // the sizes are measured again while the pane is open (a copy filling a folder, a file added deep inside)
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.load() }
    }
    func go(_ p: String, remember: Bool = true) {
        guard p != path else { load(); return }
        if remember { back.append(path) }
        path = p; selection = []
        UserDefaults.standard.set(p, forKey: "pane.\(key)")
        load()
    }
    func up() {
        let parent = (path as NSString).deletingLastPathComponent
        if !parent.isEmpty && parent != path { go(parent) }
    }
    func goBack() { if let p = back.popLast() { go(p, remember: false) } }

    func load() {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: keys,
                                                                 options: showHidden ? [] : [.skipsHiddenFiles])) ?? []
        var out: [Item] = []
        for u in urls {
            let v = try? u.resourceValues(forKeys: Set(keys))
            let link = v?.isSymbolicLink ?? false
            var dir = v?.isDirectory ?? false
            if link { var d: ObjCBool = false; if FileManager.default.fileExists(atPath: u.path, isDirectory: &d) { dir = d.boolValue } }
            out.append(Item(path: u.path, name: u.lastPathComponent, isDir: dir, isLink: link,
                            size: Int64(v?.fileSize ?? 0), mtime: v?.contentModificationDate ?? .distantPast))
        }
        out.sort { a, b in a.isDir != b.isDir ? a.isDir : a.name.localizedStandardCompare(b.name) == .orderedAscending }
        if out != items { items = out }
        let keep = selection.filter { s in out.contains { $0.path == s } }
        if keep != selection { selection = keep }
        let f = freeSpace()
        if f != free { free = f }
        watch()
        for i in out where i.isDir && !i.isLink { Sizer.shared.want(i.path, mtime: i.mtime) }
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
    var selectedBytes: Int64 {
        items.filter { selection.contains($0.path) }.reduce(Int64(0)) { t, i in t + (i.isDir ? (Sizer.shared.sizes[i.path] ?? 0) : i.size) }
    }
}

struct ItemRow: View {
    let i: Item
    @ObservedObject var sizer = Sizer.shared
    var size: String {
        if i.isLink { return "link" }
        if i.isDir { return sizer.sizes[i.path].map(bytes) ?? "…" }
        return bytes(i.size)
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: i.isLink ? "arrow.turn.up.right" : i.isDir ? "folder.fill" : "doc")
                .foregroundColor(i.isDir ? AMBER : GREY).frame(width: 16)
            Text(i.name).font(.system(size: 13)).foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Text(size).font(.system(size: 12, design: .monospaced)).foregroundColor(i.isDir ? AMBER : GREY)
                .fixedSize()
        }.padding(.vertical, 1)
        .accessibilityElement(children: .combine)
    }
}

struct PaneView: View {
    @ObservedObject var pane: Pane
    @ObservedObject var sizer = Sizer.shared
    let title: String
    func open(_ sel: Set<String>) {
        guard sel.count == 1, let p = sel.first, let it = pane.items.first(where: { $0.path == p }) else { return }
        if it.isDir { pane.go(it.isLink ? URL(fileURLWithPath: p).resolvingSymlinksInPath().path : p) }
        else { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(title).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(GREY).padding(.trailing, 6)
                Word(text: "BACK", on: false) { pane.goBack() }
                Bar_()
                Word(text: "UP", on: false) { pane.up() }
                Bar_()
                Word(text: "HOME", on: false) { pane.go(NSHomeDirectory()) }
                Bar_()
                Word(text: "VOLUMES", on: false) { pane.go("/Volumes") }
                Bar_()
                Word(text: "HIDDEN", on: pane.showHidden) { pane.showHidden.toggle(); pane.load() }
                Spacer(minLength: 8)
                Text(pane.free).font(.system(size: 11, design: .monospaced)).foregroundColor(GREY).fixedSize()
            }
            Text(pane.path).font(.system(size: 12, design: .monospaced)).foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            List(selection: $pane.selection) {
                ForEach(pane.items) { i in ItemRow(i: i).tag(i.path) }
            }
            .contextMenu(forSelectionType: String.self, menu: { _ in EmptyView() }, primaryAction: { sel in open(sel) })
            .scrollContentBackground(.hidden).background(Color(white: 0.07))
            Text(pane.selection.isEmpty ? "\(pane.items.count) items · double click opens"
                 : "\(pane.selection.count) selected · \(bytes(pane.selectedBytes))")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(GREY)
        }
    }
}

// the grey pipe between neighbouring action words (swift-apps.md, "Buttons light under the mouse")
struct Bar_: View {
    var body: some View { Text("|").font(.system(size: 12, design: .monospaced)).foregroundColor(GREY.opacity(0.6)).accessibilityHidden(true) }
}
