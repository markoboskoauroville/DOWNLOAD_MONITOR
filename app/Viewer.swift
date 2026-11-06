// Viewer.swift: the file viewer (v6, 6.11.2026). Marko: "please also use the previewer mechanism from the Mac's itself.
// There will be a preview mode. A preview mode means that when I click on one file, the preview will open in full
// screen. When it's finished, I just press the down arrow or up arrow to go through the three files, and it should play
// those files. Then I press Escape, and the preview window will exit. That's exactly the same preview window in Finder,
// which is activated with the spacebar". And: "you can create this code so you can through the Python API control it."
//
// Thumbs: real thumbnails (QLThumbnailGenerator; a video gives a frame), cached by file, size and date.
// QL: Finder's own Quick Look panel (QLPreviewPanel). It shows the selected file of one pane; ↑ ↓ in the panel move
//     that pane's selection to the file before or after and the panel follows (and plays); ← → (v10) jump to the pane
//     at the left or right and play its file; a click in another pane does the same; Escape or Space closes it. PREVIEW on a pane: one click on a file opens it full screen.
// Keys: Space toggles the preview for the active pane; in ICONS ← → ↑ ↓ move the selection, ⌘↓ opens, ⌘↑ goes up.
// Commands: what `dlmon.py view …` puts on the server (POST /view), polled by the window and applied here.
import SwiftUI
import AppKit
import QuickLookUI
import QuickLookThumbnailing

enum Thumbs {
    static let cache = NSCache<NSString, NSImage>()
    static let icons = NSCache<NSString, NSImage>()
    static func icon(_ path: String) -> NSImage {
        if let i = icons.object(forKey: path as NSString) { return i }
        let i = NSWorkspace.shared.icon(forFile: path)
        icons.setObject(i, forKey: path as NSString)
        return i
    }
    static func thumb(_ path: String, _ px: CGFloat, _ mtime: Date, _ then: @escaping (NSImage) -> Void) {
        let key = "\(path)|\(Int(px))|\(mtime.timeIntervalSince1970)" as NSString
        if let i = cache.object(forKey: key) { then(i); return }
        let req = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path), size: CGSize(width: px, height: px),
                                               scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            guard let rep = rep else { return }
            let i = rep.nsImage
            DispatchQueue.main.async { cache.setObject(i, forKey: key); then(i) }
        }
    }
}

final class QL: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QL()
    weak var pane: Pane?
    var panel: QLPreviewPanel? { QLPreviewPanel.sharedPreviewPanelExists() ? QLPreviewPanel.shared() : nil }
    var visible: Bool { panel?.isVisible ?? false }
    var file: String? { pane?.selectedFile }

    // open the panel for this pane's selected file; full = Finder's full screen (the screen of this window)
    func show(_ p: Pane, full: Bool) {
        pane = p
        guard p.selectedFile != nil, let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        if panel.isVisible { panel.reloadData() } else { panel.makeKeyAndOrderFront(nil); panel.reloadData() }
        if full && !panel.isInFullScreenMode {
            let screen = NSApp.windows.first { isMainWindow($0) && $0.isVisible }?.screen ?? NSScreen.main
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { _ = panel.enterFullScreenMode(screen, withOptions: nil) }
        }
    }
    // out of full screen first; the panel comes back at the end of that animation, so it is put away after it
    // (measured 6.11.2026: an orderOut right after exitFullScreenMode left the small panel playing)
    func close() {
        guard let panel = panel, panel.isVisible else { return }
        if panel.isInFullScreenMode {
            panel.exitFullScreenMode(options: nil)
            for t in [0.0, 0.4, 0.9] { DispatchQueue.main.asyncAfter(deadline: .now() + t) { panel.orderOut(nil) } }
        } else { panel.orderOut(nil) }
    }
    func toggle(_ p: Pane) { if visible { close() } else { show(p, full: p.preview) } }
    // a pane's selection moved (a click, an arrow, Python): the panel shows the new file. v10: a click in ANOTHER pane
    // takes the preview there too, it does not stay in the old folder
    func follow(_ p: Pane) {
        guard visible, let panel = panel else { return }
        if p.selectedFile == nil { return }
        pane = p
        Panes.shared.active = p.index
        panel.dataSource = self
        panel.reloadData()
    }
    // v10 (Marko 6.11.2026: "when I'm previewing my files with spacebar, I need to be able to jump between panes ...
    // when I jump another pane, it will start to play that file. It will not stay in the old folder"): ← → in the
    // preview go to the pane at the left / right (round at the ends); it plays that pane's selected file, or its first
    func jump(_ by: Int) {
        let ps = Panes.shared.list
        guard ps.count > 1, let cur = pane, let i = ps.firstIndex(where: { $0 === cur }) else { return }
        for k in 1..<ps.count {
            let t = ps[((i + by * k) % ps.count + ps.count) % ps.count]
            if t.selectedFile == nil { t.move(1, filesOnly: true) }      // nothing chosen there: its first file
            if t.selectedFile != nil { follow(t); return }
        }
    }

    // QLPreviewPanelDataSource: one item, the selected file, so the arrows come to us and move the pane
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { file == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        URL(fileURLWithPath: file ?? "/") as NSURL
    }
    // QLPreviewPanelDelegate: the keys the panel does not use itself
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let e = event, e.type == .keyDown, let p = pane else { return false }
        switch e.keyCode {
        case 125: p.move(1, filesOnly: true); follow(p); return true          // ↓: the next file
        case 126: p.move(-1, filesOnly: true); follow(p); return true         // ↑: the file before
        case 124: jump(1); return true                                          // →: the pane at the right plays
        case 123: jump(-1); return true                                         // ←: the pane at the left plays
        case 53, 49: close(); return true                                       // Escape, Space
        default: return false
        }
    }
}

// Space, the arrows in ICONS, ⌘↓ / ⌘↑, for the main window (not for a dialog, a text field or the panel)
enum Keys {
    static var monitor: Any?
    static func install() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard let w = e.window, !(w is QLPreviewPanel), !(w is NSPanel), isMainWindow(w) else { return e }
            if w.firstResponder is NSText { return e }
            guard let p = Panes.shared.activePane else { return e }
            let m = e.modifierFlags.intersection([.command, .option, .control])
            if m == [.command] {
                if e.keyCode == 125 { p.openItems(p.selection); return nil }
                if e.keyCode == 126 { p.up(); return nil }
                return e
            }
            guard m.isEmpty else { return e }
            if e.keyCode == 49 { QL.shared.toggle(p); return nil }                // Space
            guard p.mode == "icons" else { return e }                            // LIST: the table's own arrows
            switch e.keyCode {
            case 124: p.move(1); return nil
            case 123: p.move(-1); return nil
            case 125: p.move(p.columns); return nil
            case 126: p.move(-p.columns); return nil
            default: return e
            }
        }
    }
}

// The commands from dlmon.py view … (POST /view on the server), and the state the window reports back (POST /view/state)
enum ViewCommands {
    static func front() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { isMainWindow($0) && !($0 is NSPanel) }) {
            w.deminiaturize(nil); w.makeKeyAndOrderFront(nil)
        } else {
            // the window was closed: opening the running app again makes SwiftUI give it a new one
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        }
    }
    static func folder(_ s: String) -> String? {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: s, isDirectory: &d) && d.boolValue ? s : nil
    }
    static func apply(_ c: [String: Any]) -> String {
        let ps = Panes.shared
        let n = c["pane"] as? Int
        switch c["action"] as? String ?? "" {
        case "open":
            let fs = (c["folders"] as? [String] ?? []).compactMap(folder)
            guard !fs.isEmpty else { return "open: no folder" }
            ps.open(fs)
            if let m = c["mode"] as? String { ps.list.forEach { $0.mode = m } }
            front()
            return "showing \(fs.count) folder\(fs.count == 1 ? "" : "s")"
        case "add":
            guard let f = (c["folder"] as? String).flatMap(folder) else { return "add: not a folder" }
            ps.add(f); front()
            return "pane \(ps.list.count): \(f)"
        case "remove":
            ps.removeLast(); return "\(ps.list.count) panes"
        case "go":
            guard let f = (c["folder"] as? String).flatMap(folder), let p = ps.pick(n ?? ps.active + 1).first else { return "go: no such pane or folder" }
            p.go(f); return "pane \(p.index + 1): \(f)"
        case "mode":
            let m = (c["mode"] as? String) == "icons" ? "icons" : "list"
            ps.pick(n).forEach { $0.mode = m }; return "mode \(m)"
        case "size":
            let s = max(48, min(512, (c["size"] as? Double) ?? Double(c["size"] as? Int ?? 128)))
            ps.pick(n).forEach { $0.iconSize = s; $0.mode = "icons" }; return "icon size \(Int(s))"
        case "previewmode":
            let on = c["on"] as? Bool ?? true
            ps.pick(n).forEach { $0.preview = on }; return "preview mode \(on ? "on" : "off")"
        case "select", "preview":
            guard let file = c["file"] as? String, FileManager.default.fileExists(atPath: file) else { return "no such file" }
            let dir = (file as NSString).deletingLastPathComponent
            let p: Pane
            if let same = ps.list.first(where: { $0.path == dir }) { p = same }
            else if let a = ps.activePane { a.go(dir); p = a }
            else { return "no pane" }
            p.load()
            p.selection = [file]; p.anchor = file; ps.active = p.index
            if c["action"] as? String == "preview" {
                front()
                let full = c["full"] as? Bool ?? true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { QL.shared.show(p, full: full) }
                return "previewing \(file)"
            }
            return "selected \(file)"
        case "close":
            QL.shared.close(); return "preview closed"
        case "left", "right":
            guard QL.shared.visible else { return "no preview open" }
            QL.shared.jump(c["action"] as? String == "right" ? 1 : -1)
            return QL.shared.file.map { "pane \((QL.shared.pane?.index ?? 0) + 1) now " + $0 } ?? "no file"
        case "next", "prev":
            guard let p = QL.shared.visible ? QL.shared.pane : ps.activePane else { return "no pane" }
            p.move(c["action"] as? String == "next" ? 1 : -1, filesOnly: true)
            QL.shared.follow(p)
            return p.selectedFile.map { "now " + $0 } ?? "no file"
        case "filter":
            let t = c["text"] as? String ?? ""
            ps.pick(n).forEach { $0.filter = t }
            return t.isEmpty ? "filter cleared" : "filter \"\(t)\": " + ps.pick(n).map { "pane \($0.index + 1) shows \($0.rows.count)" }.joined(separator: ", ")
        case "share":
            // pane widths in percent (dlmon.py view share 30 70); none = equal
            let w = (c["widths"] as? [Double]) ?? []
            if w.count == ps.list.count && w.allSatisfy({ $0 > 0 }) { ps.setShare(w) } else { ps.equalShare() }
            return "widths " + ps.weights().map { String(format: "%.0f%%", $0 * 100) }.joined(separator: " | ")
        case "count":
            ps.setCount((c["count"] as? Int) ?? Int((c["count"] as? Double) ?? Double(ps.list.count)))
            return "\(ps.list.count) pane\(ps.list.count == 1 ? "" : "s")"
        case "front":
            front(); return "in front"
        case "show", "hide":
            let name = c["part"] as? String ?? ""
            let on = c["action"] as? String == "show"
            if ["bare", "1pane", "onepane"].contains(name.lowercased().replacingOccurrences(of: " ", with: "")) {
                if on != Dash.shared.bare { Dash.shared.toggleBare() }
                return "1 PANE \(Dash.shared.bare ? "on" : "off")"
            }
            guard let k = Dash.key(name) else { return "no part \(name): " + Dash.parts.map { $0.key }.joined(separator: ", ") + ", bare" }
            Dash.shared.endSolo(); Dash.shared.set(k, on)
            return "\(k) \(on ? "shown" : "hidden")"
        case "solo":                                   // v11: only that part; "off" brings everything back
            let name = c["part"] as? String ?? ""
            if ["off", "none", "back"].contains(name.lowercased()) {
                if Dash.shared.solo != nil { Dash.shared.unsolo() }
                return "solo off: back as before"
            }
            guard let k = Dash.key(name) else { return "no part \(name): " + Dash.parts.map { $0.key }.joined(separator: ", ") }
            Dash.shared.soloOn(k)
            return "solo \(k)"
        case "press":                                  // v11: the same as a click on the word
            guard let k = Dash.key(c["part"] as? String ?? "") else { return "no part" }
            Dash.shared.press(k)
            return Dash.shared.solo == k ? "\(k) solo" : "\(k) \(Dash.shared.shown(k) ? "shown" : "hidden")"
        case "layout":
            switch (c["layout"] as? String ?? "").lowercased() {
            case "bare", "1pane", "one": if !Dash.shared.bare { Dash.shared.enterBare() }; return "layout bare: one pane"
            case "full", "all": Dash.shared.full(); return "layout full: every part shown"
            default: return "layout bare | full"
            }
        default:
            return "unknown view action"
        }
    }
    static func state() -> [String: Any] {
        let ps = Panes.shared
        return ["panes": ps.list.map { $0.state() }, "active": ps.active + 1,
                "preview": ["open": QL.shared.visible, "full": QL.shared.panel?.isInFullScreenMode ?? false,
                            "file": QL.shared.visible ? (QL.shared.file ?? "") : ""] as [String: Any],
                "parts": Dash.shared.state(), "version": VERSION]
    }
}
