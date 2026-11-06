// StatusBar.swift: the top of the window is the status window (v14, 6.11.2026). Marko: "the text at the top of this
// window, I don't need it. I know that's the Download, Copy and Move application ... We're going to use it as a status
// window at the top. You need to write the full path of everything that's in the paths ... a full path, then a pipe,
// then a full path, and so on, depending on how many paths we have".
// v16 (Marko: "removing the top bar with all these buttons ... red, yellow, green. When I hover over my parts at the
// top, then it shows up. You need to fit the whole path at the top. Put the three dots for the beginning of the path,
// and then show as much as you can from the end"): no title bar; the red, yellow and green buttons appear while the
// mouse is in the top 30 pt; the first line is every pane's full path parted by pipes, the active pane's in white, and
// when they do not all fit each path is cut at its BEGINNING (… and then the end), the short ones keeping their room.
import SwiftUI
import AppKit

struct PathItem: View {
    @ObservedObject var pane: Pane
    @ObservedObject var panes = Panes.shared
    let width: CGFloat
    var body: some View {
        Text(pane.path).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.head)
            .foregroundColor(panes.active == pane.index ? .white : GREY)
            .frame(width: width, alignment: .leading)
            .help(pane.path).accessibilityLabel(pane.path).accessibilityIdentifier("status-path-\(pane.index + 1)")
    }
}
// the room of each path: short ones keep their own width, the long ones share what is left
func pathWidths(_ naturals: [CGFloat], _ avail: CGFloat) -> [CGFloat] {
    var w = naturals, left = avail, open = Array(naturals.indices)
    while !open.isEmpty {
        let share = left / CGFloat(open.count)
        let small = open.filter { naturals[$0] <= share }
        if small.isEmpty { for i in open { w[i] = max(40, share) }; break }
        for i in small { w[i] = naturals[i]; left -= naturals[i] }
        open.removeAll { small.contains($0) }
    }
    return w
}
struct PathsBar: View {
    @ObservedObject var panes = Panes.shared
    var body: some View {
        GeometryReader { g in
            let ps = panes.list
            let pipes = CGFloat(max(0, ps.count - 1)) * 20
            let w = pathWidths(ps.map { textWidth($0.path, MONO) + 4 }, max(60, g.size.width - 32 - pipes))
            HStack(spacing: 8) {
                ForEach(ps) { p in
                    if p.index > 0 { Text("|").font(.system(size: 12, design: .monospaced)).foregroundColor(GREY.opacity(0.6)).frame(width: 4) }
                    PathItem(pane: p, width: w.indices.contains(p.index) ? w[p.index] : 100)
                }
            }.padding(.horizontal, 16).frame(maxHeight: .infinity)
        }
        .frame(height: 26).background(INK).modifier(WindowDrag())
    }
}
// the top line moves the window (there is no title bar to drag any more): a mouse-down on it starts the window drag
struct WindowDrag: ViewModifier {
    func body(content: Content) -> some View {
        content.gesture(DragGesture(minimumDistance: 0).onChanged { _ in
            if let e = NSApp.currentEvent, e.type == .leftMouseDown || e.type == .leftMouseDragged { e.window?.performDrag(with: e) }
        })
    }
}
enum StatusBar {
    static var monitor: Any?
    static func buttons(_ w: NSWindow, hidden: Bool) {
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(b)?.isHidden = hidden }
    }
    // every main window gets the bare look; run at launch (a few times, the window may not be there yet), on every
    // view command and when the app comes forward
    static func installAll() -> String {
        var n = 0
        for w in NSApp.windows where isMainWindow(w) { install(on: w); n += 1 }
        return "\(n) window\(n == 1 ? "" : "s") bare"
    }
    static func install(on w: NSWindow) {
        w.styleMask.insert(.fullSizeContentView)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.acceptsMouseMovedEvents = true
        buttons(w, hidden: true)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseExited, .leftMouseDown]) { e in
            guard let win = e.window, isMainWindow(win) else { return e }
            buttons(win, hidden: e.type == .mouseExited || e.locationInWindow.y < win.frame.height - 30)
            return e
        }
    }
}
