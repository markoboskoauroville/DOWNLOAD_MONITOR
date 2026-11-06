// Info.swift: Command-I, information about the file (v20, 6.11.2026). Marko: "Command-I is showing information about the
// file at the top. It shows the full path under that, Media Info Report, and before all that, Date Created, Date
// Modified". One window that follows the selection of the pane you work in: DATE CREATED, DATE MODIFIED, the full path,
// then MediaInfo's report (FULL: every field it knows, mediainfo --Full). Command-I or Escape closes it again.
import SwiftUI
import AppKit

final class InfoModel: ObservableObject {
    static let shared = InfoModel()
    @Published var path: String?
    @Published var created = "", modified = "", size = ""
    @Published var report: String?
    @Published var full = false { didSet { if let p = path { read(p) } } }
    static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE d.M.yyyy HH:mm:ss"; return f }()

    func load(_ p: String?) {
        guard let p = p else { return }
        path = p
        let a = (try? FileManager.default.attributesOfItem(atPath: p)) ?? [:]
        created = (a[.creationDate] as? Date).map { InfoModel.fmt.string(from: $0) } ?? "—"
        modified = (a[.modificationDate] as? Date).map { InfoModel.fmt.string(from: $0) } ?? "—"
        var d: ObjCBool = false
        let isDir = FileManager.default.fileExists(atPath: p, isDirectory: &d) && d.boolValue
        size = isDir ? "folder" : bytes((a[.size] as? NSNumber)?.int64Value ?? 0)
        report = nil
        if !isDir { read(p) }
        InfoWindow.retitle((p as NSString).lastPathComponent)
    }
    private func read(_ p: String) {
        guard let bin = Media.binary else { return }
        report = nil
        let full = self.full
        DispatchQueue.global(qos: .userInitiated).async {
            let t = Media.run(bin, (full ? ["--Full"] : []) + [p])
            let clean = t.components(separatedBy: "\n").filter { !$0.hasPrefix("Complete name") }.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { if self.path == p { self.report = clean.isEmpty ? "No media information in this file." : clean } }
        }
    }
}

struct InfoView: View {
    @ObservedObject var m = InfoModel.shared
    func line(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(k).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(GREY).frame(width: 110, alignment: .leading)
            Text(v).font(.system(size: 13, design: .monospaced)).foregroundColor(.white).textSelection(.enabled)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let p = m.path {
                line("DATE CREATED", m.created)
                line("DATE MODIFIED", m.modified)
                line("SIZE", m.size)
                Line().padding(.vertical, 2)
                Text("FULL PATH").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(GREY)
                Text(p).font(.system(size: 12, design: .monospaced)).foregroundColor(.white).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Line().padding(.vertical, 2)
                HStack(spacing: 6) {
                    Text("MEDIA INFO REPORT").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(GREY)
                    Bar_()
                    Word(text: "FULL", on: m.full, size: 10) { m.full.toggle() }.accessibilityIdentifier("info-full")
                    Spacer()
                }
                ScrollView {
                    if let r = m.report { ReportView(text: r) }
                    else { Text("…").font(.system(size: 12, design: .monospaced)).foregroundColor(GREY) }
                }
            } else {
                Text("Select a file, then press Command-I.").font(.system(size: 12, design: .monospaced)).foregroundColor(GREY)
            }
        }
        .padding(16).frame(minWidth: 480, minHeight: 360).background(INK).preferredColorScheme(.dark)
    }
}

// the report: each track's name in amber, every field's name grey and its value white, wrapped, never cut
struct ReportView: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, l in
                if let r = l.range(of: " : ") {
                    HStack(alignment: .top, spacing: 8) {
                        Text(l[..<r.lowerBound].trimmingCharacters(in: .whitespaces)).font(.system(size: 11, design: .monospaced))
                            .foregroundColor(GREY).frame(width: 200, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        Text(String(l[r.upperBound...])).font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                } else if !l.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(l.uppercased()).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(AMBER).padding(.top, 5)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum InfoWindow {
    static var window: NSWindow?
    static var visible: Bool { window?.isVisible ?? false }
    static func retitle(_ t: String) { window?.title = "Info · " + t }
    static func show(_ p: Pane?) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: InfoView()))
            w.styleMask = [.titled, .closable, .resizable]; w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 620, height: 760))
            w.setFrameAutosaveName("DownloadCopyMoveInfo")
            window = w
        }
        refresh(p)
        window?.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    static func close() { window?.orderOut(nil) }
    static func toggle(_ p: Pane?) { if visible { close() } else { show(p) } }
    // the window shows the file selected in this pane (the first one when several)
    static func refresh(_ p: Pane?) {
        guard let p = p, let f = p.rows.first(where: { p.selection.contains($0.path) })?.path else { return }
        if InfoModel.shared.path != f { InfoModel.shared.load(f) }
    }
}
