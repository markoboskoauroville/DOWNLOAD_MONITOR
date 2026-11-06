// Columns.swift: which columns LIST shows, and in what order (v15, 6.11.2026). Marko: "right-click on any pane column give
// me option to disable some of the columns and also to reorder them. So, new dialog opening up for reordering,
// enabling disabling certain columns". Right-click on a column title or on a file: every column with a tick to turn it
// off or on, and "Columns..." which opens the dialog: a row per column, ON / OFF, drag it or press UP / DOWN, RESET.
// NAME always stays first. One choice for every pane, remembered (UserDefaults cols.order, cols.hidden).
import SwiftUI
import AppKit

final class ColumnPrefs: ObservableObject {
    static let shared = ColumnPrefs()
    @Published var order: [String]
    @Published var hidden: Set<String>
    @Published var custom: Bool
    init() {
        let d = UserDefaults.standard
        let all = LCOLS.map { $0.key }
        let saved = (d.stringArray(forKey: "cols.order") ?? []).filter { all.contains($0) }
        order = saved + all.filter { !saved.contains($0) }
        hidden = Set((d.stringArray(forKey: "cols.hidden") ?? []).filter { all.contains($0) })
        custom = d.object(forKey: "cols.order") != nil
    }
    func save() {
        let d = UserDefaults.standard
        d.set(order, forKey: "cols.order"); d.set(Array(hidden), forKey: "cols.hidden"); custom = true
    }
    func visible() -> [LCol] { order.filter { !hidden.contains($0) }.compactMap { k in LCOLS.first { $0.key == k } } }
    func title(_ k: String) -> String { LCOLS.first { $0.key == k }?.title ?? k }
    func toggle(_ k: String) { if hidden.contains(k) { hidden.remove(k) } else { hidden.insert(k) }; save() }
    func move(_ from: IndexSet, _ to: Int) { order.move(fromOffsets: from, toOffset: to); save() }
    func step(_ k: String, _ by: Int) {
        guard let i = order.firstIndex(of: k), order.indices.contains(i + by) else { return }
        order.swapAt(i, i + by); save()
    }
    func reset() {
        order = LCOLS.map { $0.key }; hidden = []; custom = false
        let d = UserDefaults.standard; d.removeObject(forKey: "cols.order"); d.removeObject(forKey: "cols.hidden")
    }
    // dlmon.py view columns time res fps ...: these columns, in this order, the others off
    func set(_ keys: [String]) {
        let ok = keys.compactMap { k in LCOLS.first { $0.key == k.lowercased() || $0.title.lowercased().replacingOccurrences(of: " ", with: "") == k.lowercased() }?.key }
        guard !ok.isEmpty else { return }
        order = ok + LCOLS.map { $0.key }.filter { !ok.contains($0) }
        hidden = Set(order.dropFirst(ok.count)); save()
    }
}

// the right-click menu
struct ColumnMenu: View {
    @ObservedObject var prefs = ColumnPrefs.shared
    var body: some View {
        ForEach(prefs.order, id: \.self) { k in
            Button((prefs.hidden.contains(k) ? "      " : "✓   ") + prefs.title(k)) { prefs.toggle(k) }
        }
        Divider()
        Button("Columns…  (choose and reorder)") { ColumnsDialog.show() }
        Button("Reset the columns") { prefs.reset() }
    }
}

struct ColumnsView: View {
    @ObservedObject var prefs = ColumnPrefs.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COLUMNS").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.white)
            Text("ON shows the column. Drag a row, or press ▲ ▼, to put it where you want. NAME always stays first.")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(GREY).fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(prefs.order, id: \.self) { k in
                    HStack(spacing: 8) {
                        Word(text: prefs.hidden.contains(k) ? "OFF" : "ON", on: !prefs.hidden.contains(k), size: 11) { prefs.toggle(k) }
                            .frame(width: 44, alignment: .leading).accessibilityIdentifier("col-toggle-\(k)")
                        Text(prefs.title(k)).font(.system(size: 13, design: .monospaced))
                            .foregroundColor(prefs.hidden.contains(k) ? GREY : .white)
                        Spacer()
                        Word(text: "▲", on: false, size: 11) { prefs.step(k, -1) }.accessibilityIdentifier("col-up-\(k)")
                        Word(text: "▼", on: false, size: 11) { prefs.step(k, 1) }.accessibilityIdentifier("col-down-\(k)")
                    }.padding(.vertical, 1)
                }
                .onMove { prefs.move($0, $1) }
            }
            .scrollContentBackground(.hidden).background(Color(white: 0.07)).accessibilityIdentifier("col-list")
            HStack(spacing: 6) {
                Word(text: "RESET", on: false) { prefs.reset() }.accessibilityIdentifier("col-reset")
                Bar_()
                Word(text: "DONE", on: true) { ColumnsDialog.close() }.accessibilityIdentifier("col-done")
                Spacer()
            }
        }
        .padding(16).frame(width: 380, height: 560).background(INK).preferredColorScheme(.dark)
    }
}

enum ColumnsDialog {
    static var window: NSWindow?
    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: ColumnsView()))
            w.title = "Columns"; w.styleMask = [.titled, .closable]; w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("DownloadCopyMoveColumns")
            window = w
        }
        window?.level = .floating
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    static func close() { window?.orderOut(nil) }
}
