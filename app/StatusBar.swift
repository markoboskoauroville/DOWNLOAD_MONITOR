// StatusBar.swift: the top of the window is the status window (v14, 6.11.2026). Marko: "the text at the top of this
// window, I don't need it. I know that's the Download, Copy and Move application ... We're going to use it as a status
// window at the top. You need to write the full path of everything that's in the paths ... a full path, then a pipe,
// then a full path, and so on, depending on how many paths we have".
// The title text is hidden; under the traffic lights one line shows every pane's full path, parted by a pipe, the
// active pane's in white. A long line scrolls sideways, nothing is cut.
import SwiftUI
import AppKit

struct PathItem: View {
    @ObservedObject var pane: Pane
    @ObservedObject var panes = Panes.shared
    var body: some View {
        Text(pane.path).font(.system(size: 12, design: .monospaced)).lineLimit(1).fixedSize()
            .foregroundColor(panes.active == pane.index ? .white : GREY).textSelection(.enabled)
            .accessibilityIdentifier("status-path-\(pane.index + 1)")
    }
}
struct PathsBar: View {
    @ObservedObject var panes = Panes.shared
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(panes.list) { p in
                    if p.index > 0 { Text("|").font(.system(size: 12, design: .monospaced)).foregroundColor(GREY.opacity(0.6)) }
                    PathItem(pane: p)
                }
            }.padding(.horizontal, 16).frame(maxHeight: .infinity)
        }
        .frame(height: 26).background(INK)
    }
}
enum StatusBar {
    static func install(on w: NSWindow) {
        w.titleVisibility = .hidden
        guard w.titlebarAccessoryViewControllers.isEmpty else { return }
        let host = NSHostingView(rootView: PathsBar())
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 26)
        let vc = NSTitlebarAccessoryViewController()
        vc.view = host; vc.layoutAttribute = .bottom
        w.addTitlebarAccessoryViewController(vc)
    }
}
