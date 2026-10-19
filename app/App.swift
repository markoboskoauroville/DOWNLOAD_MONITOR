// Download Monitor (Mantra): every download on this Mac, each with its own bar, in a native window. Replaces MANTRA_STAR
// apps/download.lua and the Chrome page (Marko, 13.10.2026: "no more Lua, only Swift"). The server stays: monitor.py at
// 127.0.0.1:8833 and dlmon.py are what every session calls, so their API is untouched. This window reads GET /progress
// twice a second and acts through POST /control/<id>/<action> and /forget_many. Opening the app starts the server if it
// is down, as the star's tick did; quitting the app stops it (POST /quit), as the star's second tick did. A download
// that dlmon.py started keeps going either way: its worker is in a session of its own.
// v2 (19.10.2026, Marko: "In the top of every user interface, there will now be an on/off switch ... If I say on, I
// close it's on" and "please unify the position of the close button on every application. It's far upper right
// corner. There is X to close the dialog in every dialog, same"): the first row is DOWNLOAD MONITOR  ON  OFF with the ✕
// at its far right. OFF quits, and the quit stops the server as before; ✕ (or the red button) closes the window only,
// the app and the server stay ON. The delete question carries the same ✕ (= Cancel). The star only opens it now.
import SwiftUI
import AppKit

let VERSION = 2
let RELEASES = "https://github.com/markoboskoauroville/DOWNLOAD_MONITOR/releases/latest"
let URLBASE = "http://127.0.0.1:8833"
let DIR = NSHomeDirectory() + "/Developer/DOWNLOAD_MONITOR"
let PYTHON = NSHomeDirectory() + "/.pyenv/versions/3.10.14/bin/python3"
let JOBS = NSHomeDirectory() + "/.download_monitor/jobs"

let GREEN = Color(red: 0x33/255, green: 0xD1/255, blue: 0x7A/255)
let GREY = Color(red: 0x7A/255, green: 0x80/255, blue: 0x87/255)
let AMBER = Color(red: 0xE8/255, green: 0xA3/255, blue: 0x3D/255)
let INK = Color(red: 0x0B/255, green: 0x0D/255, blue: 0x10/255)
let RED = Color(red: 0xFF/255, green: 0x5F/255, blue: 0x57/255)

struct Job: Decodable, Identifiable {
    let id: String; let name: String
    let have_mb: Double; let want_mb: Double; let pct: Double?
    let speed_mbs: Double; let eta_s: Int?; let eta_at: String?
    let done: Bool; let state: String; let control: Bool
    let info: String?; let repo: String?; let error: String?
}
struct Progress: Decodable {
    let jobs: [Job]; let total_have_mb: Double; let total_want_mb: Double
    let speed_mbit: Double; let total_pct: Double?; let last_eta_at: String?; let clock: String
    struct Disk: Decodable { let free_gb: Double? }
    let disk: Disk?
}

func mb(_ v: Double) -> String { v >= 1024 ? String(format: "%.2f GB", v / 1024) : String(format: "%.0f MB", v) }

final class Monitor: ObservableObject {
    @Published var p: Progress?
    @Published var up = false
    @Published var said = ""
    @Published var picked = Set<String>()
    private var timer: Timer?

    init() {
        ensureServer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
    }
    func ensureServer() {
        get("/health") { ok, _ in
            if ok { return }
            // detached, its output to the server's own log, as download.lua's SPAWN did
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
    func post(_ path: String, _ body: [String: Any] = [:], then: (() -> Void)? = nil) {
        var r = URLRequest(url: URL(string: URLBASE + path)!); r.httpMethod = "POST"; r.timeoutInterval = 10
        r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: r) { d, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let err = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["error"] as? String
            DispatchQueue.main.async { if code != 200 { self.said = err ?? "the server said \(code)" }; then?(); self.poll() }
        }.resume()
    }
    func poll() {
        get("/progress") { ok, d in
            let pr = ok ? d.flatMap { try? JSONDecoder().decode(Progress.self, from: $0) } : nil
            DispatchQueue.main.async {
                self.up = pr != nil
                if let pr = pr { self.p = pr; if self.said == "starting the server…" { self.said = "" } }
                self.picked = self.picked.filter { id in self.p?.jobs.contains { $0.id == id } ?? false }
            }
        }
    }
    func control(_ j: Job, _ a: String) { post("/control/\(j.id)/\(a)") }
    func forget(ids: [String]?, ask: String) {
        let al = NSAlert(); al.messageText = "Delete \(ask)?"
        al.informativeText = "A download still running is stopped first."
        al.addButton(withTitle: "Delete"); al.addButton(withTitle: "Cancel")
        CloseX.put(on: al)
        guard al.runModal() == .alertFirstButtonReturn else { return }
        post("/forget_many", ids == nil ? ["all": true] : ["ids": ids!]) { self.picked = [] }
    }
    func clearFinished() {
        let done = p?.jobs.filter { $0.done }.map { $0.id } ?? []
        guard !done.isEmpty else { said = "no finished rows"; return }
        post("/forget_many", ["ids": done]) { self.said = "\(done.count) finished rows cleared" }
    }
    // the folder: the job's file if it names one, else its Hugging Face cache folder
    func reveal(_ j: Job) {
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

// v2 (19.10.2026): the ✕ in the top-right corner of a dialog, the same as the window's: it answers Cancel
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

struct Word: View {
    let text: String; let on: Bool; let action: () -> Void
    var body: some View {
        Text(text).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(on ? GREEN : GREY)
            .padding(.horizontal, 5).padding(.vertical, 3).contentShape(Rectangle()).onTapGesture(perform: action)
    }
}

struct Bar: View {
    let pct: Double; let colour: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.16))
                RoundedRectangle(cornerRadius: 3).fill(colour).frame(width: g.size.width * CGFloat(max(0, min(100, pct))) / 100)
            }
        }.frame(height: 8)
    }
}

struct JobRow: View {
    @ObservedObject var m: Monitor
    let j: Job
    var colour: Color { j.done ? GREEN : j.error != nil || j.state == "stopped" ? RED : j.state == "paused" ? GREY : AMBER }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: m.picked.contains(j.id) ? "checkmark.square.fill" : "square").foregroundColor(GREY)
                    .onTapGesture { if m.picked.contains(j.id) { m.picked.remove(j.id) } else { m.picked.insert(j.id) } }
                Text(j.name).font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                Spacer()
                Text(j.done ? "DONE" : j.state.uppercased()).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(colour)
            }
            Bar(pct: j.pct ?? 0, colour: colour)
            HStack(spacing: 10) {
                Text("\(mb(j.have_mb)) of \(j.want_mb > 0 ? mb(j.want_mb) : "?")" + (j.pct.map { String(format: "  %.1f %%", $0) } ?? ""))
                if !j.done && j.speed_mbs > 0 { Text(String(format: "%.1f Mbit/s", j.speed_mbs * 8)) }
                if let at = j.eta_at, !j.done { Text("done at \(at)") }
                Spacer()
                if j.control && !j.done {
                    if j.state == "running" { Word(text: "PAUSE", on: false) { m.control(j, "pause") } }
                    else { Word(text: "START", on: false) { m.control(j, "start") } }
                    Word(text: "RESTART", on: false) { m.control(j, "restart") }
                }
                Word(text: "FOLDER", on: false) { m.reveal(j) }
            }.font(.system(size: 11, design: .monospaced)).foregroundColor(GREY)
            if let e = j.error { Text(e).font(.system(size: 11, design: .monospaced)).foregroundColor(RED).fixedSize(horizontal: false, vertical: true) }
            if let i = j.info, !i.isEmpty { Text(i).font(.system(size: 11)).foregroundColor(GREY).lineLimit(2) }
        }.padding(.vertical, 6)
    }
}

struct MonitorView: View {
    @ObservedObject var m: Monitor
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // v2 (19.10.2026): ON / OFF first, in the window's own words; the ✕ at the far right closes the window only
            HStack(spacing: 4) {
                Text("DOWNLOAD MONITOR").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(.white).padding(.trailing, 6)
                Word(text: "ON", on: true) {}.help("The Download Monitor runs")
                Word(text: "OFF", on: false) { NSApp.terminate(nil) }.help("Quit it; the server at 8833 stops too")
                Spacer()
                Button(action: { (NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible })?.performClose(nil) }) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).foregroundColor(GREY)
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Close the window (the Download Monitor stays ON)")
            }.padding(.top, -12).padding(.trailing, -12)
            HStack {
                Text("DOWNLOADS").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(GREY)
                Spacer()
                if let p = m.p, m.up {
                    Text(String(format: "%.1f Mbit/s", p.speed_mbit) + (p.last_eta_at.map { "  ·  all done at \($0)" } ?? ""))
                        .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(AMBER)
                } else {
                    Text("SERVER DOWN").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(RED)
                }
            }
            if let p = m.p, m.up {
                HStack {
                    Text("\(p.jobs.count) rows · \(mb(p.total_have_mb)) of \(mb(p.total_want_mb))" + (p.disk?.free_gb.map { String(format: " · %.0f GB free", $0) } ?? ""))
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(GREY)
                    Spacer()
                    Word(text: m.picked.count == p.jobs.count && !p.jobs.isEmpty ? "SELECT NONE" : "SELECT ALL", on: false) {
                        if m.picked.count == p.jobs.count { m.picked = [] } else { m.picked = Set(p.jobs.map { $0.id }) }
                    }
                    Word(text: "DELETE SELECTED (\(m.picked.count))", on: false) { if !m.picked.isEmpty { m.forget(ids: Array(m.picked), ask: "\(m.picked.count) rows") } }
                    Word(text: "CLEAR FINISHED", on: false) { m.clearFinished() }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(p.jobs.reversed()) { j in JobRow(m: m, j: j); Divider() }
                        if p.jobs.isEmpty { Text("Nothing is downloading.").font(.system(size: 12)).foregroundColor(GREY).padding(.top, 20) }
                    }
                }
            } else {
                Text("The server at 127.0.0.1:8833 does not answer.").font(.system(size: 12)).foregroundColor(GREY)
                Word(text: "START THE SERVER", on: false) { m.ensureServer() }
                Spacer()
            }
            if !m.said.isEmpty { Text(m.said).font(.system(size: 11, design: .monospaced)).foregroundColor(GREY) }
            HStack {
                Text("dlmon.py add / hf from any session puts a row here").font(.system(size: 10, design: .monospaced)).foregroundColor(GREY)
                Spacer()
                Text("v\(VERSION)").font(.system(size: 11, design: .monospaced)).foregroundColor(GREY).onTapGesture { NSWorkspace.shared.open(URL(string: RELEASES)!) }
            }
        }
        .padding(20).frame(width: 640, height: 560).background(INK).preferredColorScheme(.dark)
    }
}

let MONITOR = Monitor()

// quitting the app is the star's second tick: the server stops too (download.lua's stop); workers keep going
final class Delegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    // v2 (19.10.2026): the reopen (the star's row, the Dock) brings the window back, or lets the WindowGroup make a new one
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
        let ws = s.windows.filter { $0.isMiniaturized || $0.isVisible }
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

@main struct DownloadMonitor: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate
    var body: some Scene {
        WindowGroup("Download Monitor (Mantra)") { MonitorView(m: MONITOR) }.windowResizability(.contentSize)
    }
}
