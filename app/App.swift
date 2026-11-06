// Download, Copy and Move (Mantra), once Download Monitor (Mantra): every download on this Mac, and every copy and move,
// each with its own line, in a native window. The server stays: monitor.py at 127.0.0.1:8833 and dlmon.py are what every
// session calls, so their API is untouched. This window reads GET /progress twice a second and acts through
// POST /control/<id>/<action>, /forget_many and /copy. Opening the app starts the server if it is down; quitting the app
// stops it (POST /quit). A download dlmon.py started and the copy queue (copier.py) keep going either way: each runs in
// a session of its own, and the server picks them up again when it starts.
// v2 (19.10.2026): the first row ON  OFF with the ✕ at its far right; the delete question carries the same ✕.
// v3 (31.10.2026): TOP left of the ✕; OFF, TOP and ✕ are Accessibility buttons (off, top, close).
// v4 (5.11.2026): the icon like VM REMOTE; built by GitHub Actions.
// v5 (5.11.2026, Marko: "We need to use our Download app to be Download and Copy Move app. Rename it and copy the system
// of Pathfinder to show what's moving and the speed and put everything in the queue. We are not moving files multiple
// at the same time." and "This app will also have 2 windows, left and right, for copying between 2 locations manually
// ... Folder size— what is the folder size?"): renamed; two panes with folder sizes (Panes.swift); COPY → / MOVE → and
// back; one queue, one copy or move at a time, each line with from → to, its hairline, DONE, %, SPEED, TIME LEFT,
// READY AT, FILES, the file in hand, and PAUSE | CANCEL | FOLDER. Every word is a real button (Accessibility), orange
// under the mouse, red while pressed. The window is resizable and remembers its place.
// v6 (6.11.2026, Marko: "update my application ... to also be a file viewer ... it can open any number of folders at the
// same time, creating many vertical windows ... icon view and list view ... use the previewer mechanism from the Mac's
// itself ... you can ... through the Python API control it"): any number of panes as columns (Panes.swift), ICONS with
// real thumbnails and a size slider, LIST with NAME SIZE KIND MODIFIED DURATION sortable, double click opens in the
// file's own app, Space = Finder's Quick Look, PREVIEW = one click opens it full screen and ↑ ↓ go through the files
// (Viewer.swift); dlmon.py view … drives it through the server (POST /view, polled here with /progress).
// COPY → / MOVE → copy the active pane's selection into the pane to its right, ← COPY / ← MOVE into the one to its left.
// v7 (6.11.2026, Marko: "Make a top section, let's call it the dashboard. It should be one line, one row, grayed out if
// it's not active, and green"): the first row is the DASHBOARD, a word per part of the window (Dashboard.swift).
// v8 (6.11.2026, Marko: "I need all media details. Find the repository media info and let it read all possible media
// info inside the file. In list view, I can see all this info for each file."): MediaArea's MediaInfo inside the app
// (MediaInfo.swift): a details line under every media file, CODEC RES FPS BIT RATE columns, INFO | FULL = the whole report.
import SwiftUI
import AppKit

let VERSION = 16
let APPNAME = "Download, Copy and Move (Mantra)"
let RELEASES = "https://github.com/markoboskoauroville/DOWNLOAD_MONITOR/releases/latest"
let URLBASE = "http://127.0.0.1:8833"
let DIR = NSHomeDirectory() + "/Developer/DOWNLOAD_MONITOR"
let PYTHON = NSHomeDirectory() + "/.pyenv/versions/3.10.14/bin/python3"
let JOBS = NSHomeDirectory() + "/.download_monitor/jobs"

let GREEN = Color(red: 0x33/255, green: 0xD1/255, blue: 0x7A/255)
let GREY = Color(red: 0x7A/255, green: 0x80/255, blue: 0x87/255)
let AMBER = Color(red: 0xE8/255, green: 0xA3/255, blue: 0x3D/255)
let ORANGE = Color(red: 0xFF/255, green: 0x9F/255, blue: 0x0A/255)
let INK = Color(red: 0x0B/255, green: 0x0D/255, blue: 0x10/255)
let RED = Color(red: 0xFF/255, green: 0x5F/255, blue: 0x57/255)
let BLUE = Color(red: 0x5A/255, green: 0xA0/255, blue: 0xE0/255)

// the main window: found by the name its place is remembered under (the title is the paths now, v14)
func isMainWindow(_ w: NSWindow) -> Bool {
    !(w is NSPanel) && (w.frameAutosaveName == "DownloadCopyMoveMain" || w.title.hasPrefix("Download"))
}

struct Job: Decodable, Identifiable {
    let id: String; let name: String
    let have_mb: Double; let want_mb: Double; let pct: Double?
    let speed_mbs: Double; let eta_s: Int?; let eta_at: String?
    let done: Bool; let state: String; let control: Bool
    let info: String?; let repo: String?; let error: String?
    // copy and move (v5)
    let kind: String?; let src: String?; let dst: String?; let phase: String?; let current: String?
    let files_done: Int?; let files_total: Int?; let queue_pos: Int?; let note: String?
    var isCopy: Bool { kind == "copy" || kind == "move" }
}
struct Progress: Decodable {
    let jobs: [Job]; let total_have_mb: Double; let total_want_mb: Double
    let speed_mbit: Double; let total_pct: Double?; let last_eta_at: String?; let clock: String
    struct Disk: Decodable { let free_gb: Double? }
    let disk: Disk?
}

func mb(_ v: Double) -> String { v >= 1000 ? String(format: "%.2f GB", v / 1000) : String(format: "%.0f MB", v) }
func hms(_ s: Int) -> String { String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) }

final class Monitor: ObservableObject {
    @Published var p: Progress?
    @Published var up = false
    @Published var said = ""
    @Published var picked = Set<String>()
    private var timer: Timer?
    private var tick = 0
    private var viewSeq = -1                      // the last view command applied (-1: none read yet)
    private var lastState = ""
    private var stateAt = Date.distantPast

    init() {
        ensureServer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.poll(); self.pollView()
            self.tick += 1
            if self.tick % 2 == 0 { self.reportView() }
        }
    }
    // dlmon.py view …: the server keeps the commands in order; a fresh window takes only those of the last 20 seconds
    func pollView() {
        get("/view/commands?after=\(max(viewSeq, 0))") { ok, d in
            guard ok, let d = d, let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
            DispatchQueue.main.async {
                let seq = j["seq"] as? Int ?? 0
                if seq < self.viewSeq { self.viewSeq = 0; return }          // the server started again: count from 0
                let now = j["now"] as? Double ?? Date().timeIntervalSince1970
                let first = self.viewSeq < 0
                for c in (j["cmds"] as? [[String: Any]] ?? []) {
                    let s = c["seq"] as? Int ?? 0
                    if !first && s <= self.viewSeq { continue }
                    if first && now - (c["t"] as? Double ?? 0) > 20 { continue }
                    let said = ViewCommands.apply(c)
                    self.said = "view: " + said
                    self.quiet("/view/done", ["seq": s, "said": said])
                }
                self.viewSeq = max(seq, 0)
            }
        }
    }
    // what the panes show, for dlmon.py view list (sent when it changes, else every ten seconds)
    func reportView() {
        guard let d = try? JSONSerialization.data(withJSONObject: ViewCommands.state(), options: [.sortedKeys]),
              let s = String(data: d, encoding: .utf8) else { return }
        if s == lastState && Date().timeIntervalSince(stateAt) < 10 { return }
        lastState = s; stateAt = Date()
        quiet("/view/state", nil, raw: d)
    }
    func quiet(_ path: String, _ body: [String: Any]?, raw: Data? = nil) {
        var r = URLRequest(url: URL(string: URLBASE + path)!); r.httpMethod = "POST"; r.timeoutInterval = 3
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = raw ?? (try? JSONSerialization.data(withJSONObject: body ?? [:]))
        URLSession.shared.dataTask(with: r) { _, _, _ in }.resume()
    }
    func ensureServer() {
        get("/health") { ok, _ in
            if ok { return }
            let log = NSHomeDirectory() + "/.download_monitor/monitor.log"
            try? FileManager.default.createDirectory(atPath: NSHomeDirectory() + "/.download_monitor", withIntermediateDirectories: true)
            let sh = Process(); sh.executableURL = URL(fileURLWithPath: "/bin/sh")
            sh.arguments = ["-c", "cd \"\(DIR)\" && nohup \"\(PYTHON)\" \"\(DIR)/monitor.py\" >> \"\(log)\" 2>&1 < /dev/null &"]
            try? sh.run()
            DispatchQueue.main.async { self.said = "starting the server…" }
        }
    }
    func get(_ path: String, _ then: @escaping (Bool, Data?) -> Void) {
        var r = URLRequest(url: URL(string: URLBASE + path)!); r.timeoutInterval = 2
        URLSession.shared.dataTask(with: r) { d, resp, _ in then((resp as? HTTPURLResponse)?.statusCode == 200, d) }.resume()
    }
    func post(_ path: String, _ body: [String: Any] = [:], timeout: TimeInterval = 10, then: (() -> Void)? = nil) {
        var r = URLRequest(url: URL(string: URLBASE + path)!); r.httpMethod = "POST"; r.timeoutInterval = timeout
        r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: r) { d, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let err = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["error"] as? String
            DispatchQueue.main.async { if code != 200 { self.said = err ?? "the server said \(code)" } else { then?() }; self.poll() }
        }.resume()
    }
    func poll() {
        get("/progress") { ok, d in
            let pr = ok ? d.flatMap { try? JSONDecoder().decode(Progress.self, from: $0) } : nil
            DispatchQueue.main.async {
                self.up = pr != nil
                if let pr = pr { self.p = pr; if self.said == "starting the server…" { self.said = "" } }
                let ids = Set(self.p?.jobs.map { $0.id } ?? [])
                let keep = self.picked.filter { ids.contains($0) }
                if keep != self.picked { self.picked = keep }
            }
        }
    }
    func control(_ j: Job, _ a: String) { post("/control/\(j.id)/\(a)") }
    func forget(ids: [String]?, ask: String) {
        let al = NSAlert(); al.messageText = "Delete \(ask)?"
        al.informativeText = "A download still running is stopped first; a copy or move running is paused first (what is copied stays)."
        al.addButton(withTitle: "Delete"); al.addButton(withTitle: "Cancel")
        CloseX.put(on: al)
        guard al.runModal() == .alertFirstButtonReturn else { return }
        post("/forget_many", ids == nil ? ["all": true] : ["ids": ids!]) { self.picked = [] }
    }
    func clearFinished() {
        let done = p?.jobs.filter { $0.done || $0.state == "cancelled" }.map { $0.id } ?? []
        guard !done.isEmpty else { said = "no finished rows"; return }
        post("/forget_many", ["ids": done]) { self.said = "\(done.count) finished rows cleared" }
    }
    // COPY → / MOVE → and back: the selection of the active pane into the folder of the pane to its right (→) or left (←)
    func transfer(_ mode: String, dir: Int) {
        let ps = Panes.shared
        let a = min(max(ps.active, 0), ps.list.count - 1), b = a + dir
        guard ps.list.indices.contains(b) else { said = "no pane to the \(dir > 0 ? "right" : "left") of pane \(a + 1)"; return }
        transfer(mode, from: ps.list[a], to: ps.list[b])
    }
    func transfer(_ mode: String, from: Pane, to: Pane) {
        let items = from.items.filter { from.selection.contains($0.path) }.map { $0.path }
        guard !items.isEmpty else { said = "select something in pane \(from.index + 1) first"; return }
        guard from.path != to.path else { said = "both panes show the same folder"; return }
        if mode == "move" {
            let al = NSAlert(); al.messageText = "Move \(items.count == 1 ? (items[0] as NSString).lastPathComponent : "\(items.count) items") to \(to.path)?"
            al.informativeText = "Copied first; the original is deleted only after the check (count, bytes, MD5 of the five largest files), and a link to the new place stays where it was."
            al.addButton(withTitle: "Move"); al.addButton(withTitle: "Cancel")
            CloseX.put(on: al)
            guard al.runModal() == .alertFirstButtonReturn else { return }
        }
        said = "putting \(items.count) in the queue…"
        post("/copy", ["items": items, "dst_dir": to.path, "mode": mode], timeout: 600) {
            self.said = "\(mode) of \(items.count) item\(items.count == 1 ? "" : "s") queued into \(to.path)"
            from.selection = []
        }
    }
    // the folder: a copy's destination, the job's file, else its Hugging Face cache folder
    func reveal(_ j: Job) {
        if j.isCopy, let d = j.dst {
            let p = FileManager.default.fileExists(atPath: d) ? d : (d as NSString).deletingLastPathComponent
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]); return
        }
        let f = JOBS + "/" + j.id.replacingOccurrences(of: "[^A-Za-z0-9_.-]", with: "_", options: .regularExpression) + ".json"
        let job = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: f)))) as? [String: Any] ?? [:]
        if let file = job["file"] as? String, FileManager.default.fileExists(atPath: file) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file)]); return
        }
        if let repo = j.repo {
            let hub = (job["hub"] as? String) ?? NSHomeDirectory() + "/.cache/huggingface/hub"
            let dir = hub + "/models--" + repo.replacingOccurrences(of: "/", with: "--")
            if FileManager.default.fileExists(atPath: dir) { NSWorkspace.shared.open(URL(fileURLWithPath: dir)); return }
        }
        said = "no folder known for \(j.name)"
    }
}

// the ✕ in the top-right corner of a dialog, the same as the window's: it answers Cancel
final class CloseX: NSObject {
    static let shared = CloseX()
    static func put(on al: NSAlert) {
        al.layout()
        guard let v = al.window.contentView else { return }
        let x = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!
                            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))!, target: shared, action: #selector(cancel))
        x.isBordered = false; x.contentTintColor = NSColor(srgbRed: 0x7A/255.0, green: 0x80/255.0, blue: 0x87/255.0, alpha: 1)
        x.frame = NSRect(x: v.bounds.maxX - 34, y: v.bounds.maxY - 34, width: 28, height: 28); x.autoresizingMask = [.minXMargin, .minYMargin]
        x.toolTip = "Close (the same as Cancel)"
        v.addSubview(x)
    }
    @objc func cancel() { NSApp.stopModal(withCode: .alertSecondButtonReturn) }
}

// a word that is a button: grey at rest (green when on), orange under the mouse, red while pressed; a real AX button
struct WordStyle: ButtonStyle {
    let on: Bool; let size: CGFloat
    func makeBody(configuration: Configuration) -> some View { WordFace(label: configuration.label, pressed: configuration.isPressed, on: on, size: size) }
}
struct WordFace<L: View>: View {
    let label: L; let pressed: Bool; let on: Bool; let size: CGFloat
    @State private var hover = false
    var body: some View {
        label.font(.system(size: size, weight: .bold, design: .monospaced))
            .foregroundColor(pressed ? RED : hover ? ORANGE : on ? GREEN : GREY)
            .padding(.horizontal, 5).padding(.vertical, 3).contentShape(Rectangle())
            .onHover { h in hover = h; if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
}
struct Word: View {
    let text: String; let on: Bool; var size: CGFloat = 12; let action: () -> Void
    init(text: String, on: Bool, size: CGFloat = 12, action: @escaping () -> Void) { self.text = text; self.on = on; self.size = size; self.action = action }
    var body: some View {
        Button(action: action) { Text(text).fixedSize() }.buttonStyle(WordStyle(on: on, size: size)).accessibilityLabel(text)
    }
}

struct TopWord: View {
    @AppStorage("onTop") private var onTop = false
    var body: some View {
        Word(text: "TOP", on: onTop) { onTop.toggle(); TopWord.float(onTop) }
            .accessibilityIdentifier("top").accessibilityValue(onTop ? "on" : "off")
            .help("Always on top: green, the window stays above every other window")
            .onAppear { DispatchQueue.main.async { TopWord.float(onTop) } }
    }
    static func float(_ on: Bool) {
        for w in NSApp.windows where isMainWindow(w) { w.level = on ? .floating : .normal }
    }
}

// a hairline that fills like a progress line (workflow-interface.md: everything is a hairline)
struct Hair: View {
    let pct: Double; let colour: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(white: 0.18))
                Rectangle().fill(colour).frame(width: g.size.width * CGFloat(max(0, min(100, pct))) / 100)
            }
        }.frame(height: 2)
    }
}
struct Line: View { var body: some View { Rectangle().fill(Color(white: 0.2)).frame(height: 1) } }

// one labelled cell: a small grey LABEL, the VALUE under it
struct Cell: View {
    let label: String; let value: String; var colour: Color = .white
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(GREY).fixedSize()
            Text(value).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundColor(colour).fixedSize()
        }.frame(minWidth: 90, alignment: .leading)
    }
}

struct CopyRow: View {
    @ObservedObject var m: Monitor
    let j: Job
    var colour: Color {
        switch j.state {
        case "done": return BLUE
        case "failed": return RED
        case "paused", "cancelled": return GREY
        case "running": return j.phase == "verifying" ? GREEN : AMBER
        default: return j.phase != nil ? RED : GREY
        }
    }
    var label: String {
        let pos = j.queue_pos.map { " \($0)" } ?? ""
        switch j.state {
        case "running": return (j.phase ?? "running").uppercased()
        case "queued": return "QUEUED\(pos)" + (j.phase.map { " · " + $0.uppercased() } ?? "")
        case "paused": return "PAUSED\(pos) · HOLDS THE QUEUE"
        default: return j.state.uppercased()
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: m.picked.contains(j.id) ? "checkmark.square.fill" : "square").foregroundColor(GREY)
                    .onTapGesture { if m.picked.contains(j.id) { m.picked.remove(j.id) } else { m.picked.insert(j.id) } }
                    .accessibilityLabel("Select").accessibilityAddTraits(.isButton)
                Text((j.kind ?? "copy").uppercased()).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(AMBER).fixedSize()
                Text(j.name).font(.system(size: 13, weight: .semibold)).foregroundColor(.white).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(label).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(colour).fixedSize(horizontal: false, vertical: true)
            }
            Text("\(j.src ?? "?")  →  \(j.dst ?? "?")").font(.system(size: 11, design: .monospaced)).foregroundColor(GREY)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Hair(pct: j.pct ?? 0, colour: colour)
            HStack(alignment: .top, spacing: 14) {
                Cell(label: j.phase == "verifying" ? "COPIED" : "DONE", value: "\(mb(j.have_mb)) of \(mb(j.want_mb))")
                Cell(label: j.phase == "verifying" ? "VERIFIED" : "PERCENT", value: j.pct.map { String(format: "%.1f %%", $0) } ?? "–", colour: AMBER)
                Cell(label: "SPEED", value: j.speed_mbs > 0 ? String(format: "%.1f MB/s", j.speed_mbs) : "–")
                Cell(label: "TIME LEFT", value: j.eta_s.map(hms) ?? "–")
                Cell(label: "READY AT", value: j.eta_at ?? "–", colour: AMBER)
                Cell(label: "FILES", value: "\(j.files_done ?? 0) / \(j.files_total ?? 0)")
                Spacer(minLength: 0)
            }
            if let c = j.current { Text("now: " + c).font(.system(size: 11, design: .monospaced)).foregroundColor(.white).fixedSize(horizontal: false, vertical: true) }
            if let e = j.error { Text(e).font(.system(size: 11, design: .monospaced)).foregroundColor(RED).fixedSize(horizontal: false, vertical: true) }
            if let n = j.note, !n.isEmpty { Text(n).font(.system(size: 11)).foregroundColor(GREY).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 2) {
                Spacer()
                let stopped = ["paused", "failed", "cancelled"].contains(j.state)
                Word(text: stopped ? "START" : "PAUSE", on: j.state == "running") {
                    if j.done { m.said = "\(j.name) is done" } else { m.control(j, stopped ? "start" : "pause") }
                }.accessibilityIdentifier("pause-\(j.id)")
                Bar_()
                Word(text: "CANCEL", on: false) {
                    if j.done || j.state == "cancelled" { m.said = "nothing to cancel" } else { m.control(j, "cancel") }
                }.accessibilityIdentifier("cancel-\(j.id)")
                Bar_()
                Word(text: "FOLDER", on: false) { m.reveal(j) }
            }
        }.padding(.vertical, 8)
    }
}

struct JobRow: View {
    @ObservedObject var m: Monitor
    let j: Job
    var colour: Color { j.done ? GREEN : j.error != nil || j.state == "stopped" ? RED : j.state == "paused" ? GREY : AMBER }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: m.picked.contains(j.id) ? "checkmark.square.fill" : "square").foregroundColor(GREY)
                    .onTapGesture { if m.picked.contains(j.id) { m.picked.remove(j.id) } else { m.picked.insert(j.id) } }
                    .accessibilityLabel("Select").accessibilityAddTraits(.isButton)
                Text("DOWNLOAD").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(GREY).fixedSize()
                Text(j.name).font(.system(size: 13, weight: .semibold)).foregroundColor(.white).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(j.done ? "DONE" : j.state.uppercased()).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(colour).fixedSize()
            }
            Hair(pct: j.pct ?? 0, colour: colour)
            HStack(spacing: 10) {
                Text("\(mb(j.have_mb)) of \(j.want_mb > 0 ? mb(j.want_mb) : "?")" + (j.pct.map { String(format: "  %.1f %%", $0) } ?? "")).fixedSize()
                if !j.done && j.speed_mbs > 0 { Text(String(format: "%.1f MB/s", j.speed_mbs)).fixedSize() }
                if let s = j.eta_s, !j.done { Text(hms(s) + " left").fixedSize() }
                if let at = j.eta_at, !j.done { Text("ready at \(at)").fixedSize() }
                Spacer()
                if j.control && !j.done {
                    Word(text: j.state == "running" ? "PAUSE" : "START", on: false) { m.control(j, j.state == "running" ? "pause" : "start") }
                    Bar_()
                    Word(text: "RESTART", on: false) { m.control(j, "restart") }
                    Bar_()
                }
                Word(text: "FOLDER", on: false) { m.reveal(j) }
            }.font(.system(size: 11, design: .monospaced)).foregroundColor(GREY)
            if let e = j.error { Text(e).font(.system(size: 11, design: .monospaced)).foregroundColor(RED).fixedSize(horizontal: false, vertical: true) }
            if let i = j.info, !i.isEmpty { Text(i).font(.system(size: 11)).foregroundColor(GREY).lineLimit(3).fixedSize(horizontal: false, vertical: true) }
        }.padding(.vertical, 6)
    }
}


struct MonitorView: View {
    @ObservedObject var m: Monitor
    @ObservedObject var panes = Panes.shared
    @ObservedObject var dash = Dash.shared

    var copies: [Job] {
        let all = m.p?.jobs.filter { $0.isCopy } ?? []
        let live = all.filter { $0.queue_pos != nil }.sorted { ($0.queue_pos ?? 0) < ($1.queue_pos ?? 0) }
        return live + all.filter { $0.queue_pos == nil }.reversed()
    }
    var downloads: [Job] { (m.p?.jobs.filter { !$0.isCopy } ?? []).reversed() }

    var topRow: some View {
        HStack(spacing: 2) {
            Text("DOWNLOAD, COPY AND MOVE").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.white).padding(.trailing, 6).fixedSize()
            Word(text: "ON", on: true) {}.help("Download, Copy and Move runs").accessibilityIdentifier("on")
            Bar_()
            Word(text: "OFF", on: false) { DispatchQueue.main.async { NSApp.terminate(nil) } }
                .help("Quit it; the server at 8833 stops too. A copy or move running goes on (PAUSE stops it)")
                .accessibilityIdentifier("off")
            Spacer(minLength: 10)
            DashRow()
            Spacer(minLength: 10)
            Text("v\(VERSION)").font(.system(size: 11, design: .monospaced)).foregroundColor(GREY)
                .onTapGesture { NSWorkspace.shared.open(URL(string: RELEASES)!) }
            TopWord()
            Button(action: { (NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible })?.orderOut(nil) }) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).foregroundColor(GREY)
                    .frame(width: 30, height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Close the window (the app stays ON)")
            .accessibilityLabel("Close window").accessibilityIdentifier("close")
        }
    }

    // the panes as columns; over them ADD PANE | REMOVE PANE and the copy words of the active pane
    var paneArea: some View {
        let a = panes.active + 1
        return VStack(alignment: .leading, spacing: 6) {
            if dash.shown("toolbar") { toolbar(a) }
            GeometryReader { g in
                let n = panes.list.count
                let room = max(1, g.size.width - 9 * CGFloat(max(0, n - 1)))
                let w = panes.weights()
                HStack(alignment: .top, spacing: 0) {
                    ForEach(panes.list) { p in
                        if p.index > 0 { PaneDivider(left: p.index - 1, room: room) }
                        PaneView(pane: p).frame(width: room * CGFloat(w[p.index]), height: g.size.height)
                    }
                }
            }
        }.padding(.vertical, 8)
    }
    func toolbar(_ a: Int) -> some View {
            Flow {
                Text("PANES").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(GREY).padding(.trailing, 6)
                Word(text: "ADD PANE", on: false) { panes.add() }.accessibilityIdentifier("add-pane")
                Bar_()
                Word(text: "REMOVE PANE", on: false) {
                    if panes.list.count > 1 { panes.removeLast() } else { m.said = "one pane stays" }
                }.accessibilityIdentifier("remove-pane")
                Text("   FROM PANE \(a):").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(GREY).padding(.horizontal, 6)
                Word(text: "← COPY", on: false) { m.transfer("copy", dir: -1) }.accessibilityIdentifier("copy-left")
                    .help("Copy the selection of pane \(a) into the folder of pane \(a - 1)")
                Bar_()
                Word(text: "← MOVE", on: false) { m.transfer("move", dir: -1) }.accessibilityIdentifier("move-left")
                Bar_()
                Word(text: "COPY →", on: false) { m.transfer("copy", dir: 1) }.accessibilityIdentifier("copy-right")
                    .help("Copy the selection of pane \(a) into the folder of pane \(a + 1)")
                Bar_()
                Word(text: "MOVE →", on: false) { m.transfer("move", dir: 1) }.accessibilityIdentifier("move-right")
            }
    }

    var queue: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(dash.shown("queue") ? "THE QUEUE · ONE COPY OR MOVE AT A TIME" : "DOWNLOADS").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(GREY).fixedSize()
                Spacer()
                if let p = m.p, m.up {
                    Text(String(format: "%.1f MB/s", p.speed_mbit / 8) + (p.last_eta_at.map { "  ·  all ready at \($0)" } ?? ""))
                        .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(AMBER).fixedSize()
                } else {
                    Text("SERVER DOWN").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(RED)
                }
            }
            if let p = m.p, m.up {
                HStack(spacing: 2) {
                    Text("\(p.jobs.count) rows" + (p.disk?.free_gb.map { String(format: " · %.0f GB free here", $0) } ?? ""))
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(GREY).fixedSize()
                    Spacer()
                    Word(text: m.picked.count == p.jobs.count && !p.jobs.isEmpty ? "SELECT NONE" : "SELECT ALL", on: false) {
                        if m.picked.count == p.jobs.count { m.picked = [] } else { m.picked = Set(p.jobs.map { $0.id }) }
                    }
                    Bar_()
                    Word(text: "DELETE SELECTED (\(m.picked.count))", on: false) {
                        if m.picked.isEmpty { m.said = "nothing selected" } else { m.forget(ids: Array(m.picked), ask: "\(m.picked.count) rows") }
                    }
                    Bar_()
                    Word(text: "CLEAR FINISHED", on: false) { m.clearFinished() }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if dash.shown("queue") { ForEach(copies) { j in CopyRow(m: m, j: j); Line() } }
                        if copies.isEmpty && dash.shown("queue") {
                            Text("Nothing in the queue. Select in one pane, then COPY → or MOVE →; or dlmon.py copy / move from any session.")
                                .font(.system(size: 12)).foregroundColor(GREY).padding(.vertical, 10).fixedSize(horizontal: false, vertical: true)
                        }
                        if !downloads.isEmpty && dash.shown("downloads") {
                            if dash.shown("queue") {
                                Text("DOWNLOADS").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(GREY).padding(.top, 14)
                            }
                            ForEach(downloads) { j in JobRow(m: m, j: j); Line() }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("The server at 127.0.0.1:8833 does not answer.").font(.system(size: 12)).foregroundColor(GREY)
                Word(text: "START THE SERVER", on: false) { m.ensureServer() }
                Spacer()
            }
        }.padding(.top, 8)
    }

    // DOWNLOADS alone takes room only while there is a download to show
    var showQueue: Bool { dash.shown("queue") || (dash.shown("downloads") && !downloads.isEmpty) }
    // what the DASHBOARD shows: the panes over the queue (a divider between them to drag), or one of them alone
    @ViewBuilder var parts: some View {
        if dash.shown("panes") && showQueue {
            VSplitView {
                paneArea.frame(minHeight: 340, idealHeight: 600)
                queue.frame(minHeight: 160, idealHeight: 260)
            }
        } else if dash.shown("panes") {
            paneArea.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if showQueue {
            queue.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("Every part is hidden: turn one on in the dashboard above.").font(.system(size: 12)).foregroundColor(GREY)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // v16: the paths line first, with no title bar over it
    var body: some View {
        VStack(spacing: 0) { PathsBar(); inner }.ignoresSafeArea(.container, edges: .top)
    }
    var inner: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow.padding(.top, -10).padding(.trailing, -10)
            Line().padding(.top, 4)
            parts
            if dash.shown("status") { Line() }
            if dash.shown("status") { HStack {
                Text(m.said.isEmpty ? "dlmon.py copy / move / add / hf from any session puts a line here" : m.said)
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(GREY).fixedSize(horizontal: false, vertical: true)
                Spacer()
            }.padding(.top, 6) }
        }
        .padding(16)
        .frame(minWidth: max(980, CGFloat(panes.list.count) * 280 + 40), idealWidth: 1240, maxWidth: .infinity,
               minHeight: dash.shown("panes") && showQueue ? 700 : 360, idealHeight: 900, maxHeight: .infinity)
        .background(INK).preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.async {
                for w in NSApp.windows where isMainWindow(w) {
                    w.setFrameAutosaveName("DownloadCopyMoveMain")
                    StatusBar.install(on: w)
                }
            }
        }
    }
}

let MONITOR = Monitor()

final class Delegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ n: Notification) { Keys.install() }
    // the ✕ only hides the window, so the Dock, the star and dlmon.py view bring the same one back
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
        let ws = s.windows.filter { isMainWindow($0) && !($0 is NSPanel) }
        if ws.isEmpty { return true }
        for w in ws { w.deminiaturize(nil); w.makeKeyAndOrderFront(nil) }
        s.activate(ignoringOtherApps: true)
        return false
    }
    func applicationWillTerminate(_ n: Notification) {
        var r = URLRequest(url: URL(string: URLBASE + "/quit")!); r.httpMethod = "POST"; r.timeoutInterval = 2
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: r) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 2)
    }
}

@main struct DownloadCopyMove: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate
    var body: some Scene {
        WindowGroup(APPNAME) { MonitorView(m: MONITOR) }
            .windowResizability(.contentMinSize)
            .defaultSize(width: 1240, height: 900)
    }
}
