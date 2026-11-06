// Dashboard.swift: the first row is the DASHBOARD (v7, 6.11.2026). Marko: "We need to have different parts of the
// interface there to turn them on and off. I can even have a bare-bone version with only one folder, so whatever is shown
// on the screen can be turned off and on. Make a top section, let's call it the dashboard. It should be one line, one
// row, grayed out if it's not active, and green with soft buttons to disable parts of the user interface".
// One word per part: green = shown, grey = hidden; a hidden part gives its room to the rest. 1 PANE is the bare-bone
// window (one pane, its files only); pressing it again brings back the parts and the panes as they were. Remembered in
// UserDefaults (dash.<part>, dash.bare, dash.before, dash.before.paths). dlmon.py view show|hide|layout|parts drive it.
import SwiftUI
import AppKit

// key, the word on the row, what it is (for the help and for dlmon.py view parts)
struct Part: Identifiable { let key: String; let word: String; let what: String; var id: String { key } }

final class Dash: ObservableObject {
    static let shared = Dash()
    static let parts: [Part] = [
        Part(key: "panes", word: "PANES", what: "the folder panes"),
        Part(key: "toolbar", word: "TOOLBAR", what: "ADD PANE | REMOVE PANE and COPY / MOVE over the panes"),
        Part(key: "nav", word: "NAV", what: "each pane's PANE n line and BACK | UP | HOME | VOLUMES | HIDDEN"),
        Part(key: "path", word: "PATH", what: "each pane's path"),
        Part(key: "views", word: "VIEWS", what: "each pane's ICONS | LIST | PREVIEW and the icon size slider"),
        Part(key: "status", word: "STATUS", what: "the line under each pane and the message line at the bottom"),
        Part(key: "queue", word: "QUEUE", what: "the copy and move queue"),
        Part(key: "downloads", word: "DOWNLOADS", what: "the downloads"),
    ]
    @Published var on: [String: Bool]
    @Published var bare: Bool
    init() {
        let d = UserDefaults.standard
        var o: [String: Bool] = [:]
        for p in Dash.parts { o[p.key] = d.object(forKey: "dash.\(p.key)") as? Bool ?? true }
        on = o
        bare = d.bool(forKey: "dash.bare")
    }
    static func key(_ name: String) -> String? {
        let k = name.lowercased().replacingOccurrences(of: " ", with: "")
        let alias = ["pane": "panes", "folders": "panes", "tools": "toolbar", "copy": "toolbar", "navigation": "nav",
                     "paths": "path", "view": "views", "mode": "views", "line": "status", "statusline": "status",
                     "copies": "queue", "download": "downloads"]
        let r = alias[k] ?? k
        return parts.contains { $0.key == r } ? r : nil
    }
    func shown(_ k: String) -> Bool { on[k] ?? true }
    func set(_ k: String, _ v: Bool) {
        on[k] = v
        UserDefaults.standard.set(v, forKey: "dash.\(k)")
    }
    func toggle(_ k: String) { set(k, !shown(k)) }
    func toggleBare() { if bare { leaveBare() } else { enterBare() } }
    // one pane (the active one), its files only; what was shown before is kept for the way back
    func enterBare() {
        let d = UserDefaults.standard
        d.set(on, forKey: "dash.before")
        d.set(Panes.shared.list.map { $0.path }, forKey: "dash.before.paths")
        let ps = Panes.shared
        if let a = ps.activePane, ps.list.count > 1 {
            let m = a.mode, size = a.iconSize
            ps.open([a.path])
            ps.list.first?.mode = m; ps.list.first?.iconSize = size
        }
        for p in Dash.parts { set(p.key, p.key == "panes") }
        bare = true; d.set(true, forKey: "dash.bare")
    }
    func leaveBare() {
        let d = UserDefaults.standard
        let before = d.dictionary(forKey: "dash.before") as? [String: Bool] ?? [:]
        for p in Dash.parts { set(p.key, before[p.key] ?? true) }
        if let paths = d.stringArray(forKey: "dash.before.paths"), paths.count > 1 {
            let keep = Panes.shared.list.first?.path
            Panes.shared.open([keep ?? paths[0]] + Array(paths.dropFirst()))
        }
        bare = false; d.set(false, forKey: "dash.bare")
    }
    // FULL: every part shown (and out of 1 PANE first, with its panes back)
    func full() {
        if bare { leaveBare() }
        for p in Dash.parts { set(p.key, true) }
    }
    func state() -> [String: Any] {
        var s: [String: Any] = [:]
        for p in Dash.parts { s[p.key] = shown(p.key) }
        s["bare"] = bare
        return s
    }
}

// the row: one soft word per part, green while it is shown, grey when hidden, pipes between
struct DashRow: View {
    @ObservedObject var dash = Dash.shared
    var body: some View {
        HStack(spacing: 1) {
            ForEach(Dash.parts) { p in
                if p.key != Dash.parts[0].key { Bar_() }
                Word(text: p.word, on: dash.shown(p.key), size: 11) { dash.toggle(p.key) }
                    .help((dash.shown(p.key) ? "Shown: " : "Hidden: ") + p.what)
                    .accessibilityIdentifier("dash-\(p.key)").accessibilityValue(dash.shown(p.key) ? "on" : "off")
            }
            Text("·").font(.system(size: 12, design: .monospaced)).foregroundColor(GREY.opacity(0.6)).padding(.horizontal, 4)
                .accessibilityHidden(true)
            Word(text: "1 PANE", on: dash.bare, size: 11) { dash.toggleBare() }
                .help(dash.bare ? "Back to the panes and parts as they were" : "Bare bone: one pane, only its files")
                .accessibilityIdentifier("dash-bare").accessibilityValue(dash.bare ? "on" : "off")
        }
    }
}
