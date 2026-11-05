// six_icon.swift (a copy of STAR_SWIFT/icons6/six_icon.swift): the star apps' icons (Marko 4.11.2026): six letters, three on top and three below, over ONE
// symbolic picture, nothing else. swift six_icon.swift icons.json <outdir> [key]
// -> <outdir>/<key>/icon_1024.png and AppIcon.icns, and <outdir>/sheet.png (every icon at 128 and at 48 px).
import AppKit
let a = CommandLine.arguments
let table = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: a[1]))) as! [String: Any]
let out = a[2], only = a.count > 3 ? a[3] : nil
let cats = table["categories"] as! [String: [String: Any]]
var colourOf: [String: String] = [:]
for (_, c) in cats { for k in c["apps"] as! [String] { colourOf[k] = c["colour"] as? String } }
// (copy in DOWNLOAD_MONITOR/icon: drawn by the GitHub workflow, where there is no ~/.config/star-rows.json)
let rows = (try? Data(contentsOf: URL(fileURLWithPath: NSString(string: "~/.config/star-rows.json").expandingTildeInPath)))
    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? ["rows": [[String: Any]]()]
var groupOf: [String: String] = [:]
for r in rows["rows"] as? [[String: Any]] ?? [] { groupOf[r["key"] as! String] = r["group"] as? String ?? "Mac" }
func hex(_ h: String) -> NSColor {
    let v = Int(h.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
func font(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .black)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}
func draw(_ px: Int, top: String, bottom: String, symbol: String, color: NSColor) -> NSBitmapImageRep {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.imageInterpolation = .high
    // the tile: Apple's grid, 824 of 1024, corner 185
    let m = s * 100 / 1024, box = NSRect(x: m, y: m, width: s - 2 * m, height: s - 2 * m)
    let tile = NSBezierPath(roundedRect: box, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)
    NSGradient(starting: color.blended(withFraction: 0.18, of: .white)!, ending: color.blended(withFraction: 0.35, of: .black)!)!
        .draw(in: tile, angle: -90)
    // terminal (Marko 5.11.2026: "a black background with the green terminal entry point ... like the background in the
    // clear terminal"): the tile is an empty terminal, black, and a green block cursor stands after the bottom row
    // terminal:<#hex> (Marko 5.11.2026, Download Monitor: "look exactly the same as VM remote ... an orange ... square"):
    // the same black terminal, the cursor in that colour
    // terminal-lead[:#hex] (Marko 5.11.2026, Launcher: "like download monitor ... this cursor entry point should become
    // green and come at the beginning ... one word"): the same black terminal, one word, the cursor before it
    // matrix:<#hex> (Marko 5.11.2026, Swift Matrix: "a background of a Matrix movie with falling letters, but zoomed in,
    // not too small ... over that ... David star", the name in lines and the cursor in a colour not used yet)
    let isMatrix = symbol.hasPrefix("matrix")
    let lead = symbol.hasPrefix("terminal-lead")
    let isTerm = symbol == "terminal" || symbol.hasPrefix("terminal:") || lead || isMatrix
    let green = NSColor(srgbRed: 0.20, green: 0.95, blue: 0.35, alpha: 1)
    let terminalGreen = lead ? (symbol.hasPrefix("terminal-lead:") ? hex(String(symbol.dropFirst(14))) : green)
        : symbol.hasPrefix("terminal:") ? hex(String(symbol.dropFirst(9)))
        : symbol.hasPrefix("matrix:") ? hex(String(symbol.dropFirst(7))) : green
    if isTerm || symbol == "sunmoon" { NSColor(white: 0.04, alpha: 1).setFill(); tile.fill() }   // matrix too
    // the one picture behind the letters (Marko 4.11.2026): app:<path> that application's own icon (darkened so the
    // letters read), star the David star, text:<glyph>, sf:<symbol> a symbol, all large and clipped by the tile
    tile.addClip()
    let white = NSColor(white: 1, alpha: 0.46)
    func centred(_ img: NSImage, _ frac: CGFloat) {
        let k = min(box.width * frac / img.size.width, box.height * frac / img.size.height)
        let w = img.size.width * k, h = img.size.height * k
        img.draw(in: NSRect(x: (s - w) / 2, y: (s - h) / 2, width: w, height: h))
    }
    if symbol.hasPrefix("app:") {
        let icon = NSWorkspace.shared.icon(forFile: String(symbol.dropFirst(4)))
        icon.size = NSSize(width: 1024, height: 1024)
        let k = s * 1.12, r = NSRect(x: (s - k) / 2, y: (s - k) / 2, width: k, height: k)
        icon.draw(in: r)
        color.blended(withFraction: 0.25, of: .black)!.withAlphaComponent(0.78).setFill(); box.fill()  // the category colour over it
    } else if symbol == "star" {
        let R = box.width * 0.47, cx = s / 2, cy = s / 2, c: CGFloat = 0.8660254
        for d: CGFloat in [1, -1] {
            let b = NSBezierPath(); b.move(to: NSPoint(x: cx, y: cy + d * R))
            b.line(to: NSPoint(x: cx - c * R, y: cy - d * R / 2)); b.line(to: NSPoint(x: cx + c * R, y: cy - d * R / 2)); b.close()
            b.lineWidth = s * 0.045; b.lineJoinStyle = .round; NSColor(white: 1, alpha: 0.38).setStroke(); b.stroke()
        }
    } else if isMatrix {
        // the rain: six big columns of katakana and digits, each a trail fading upward under a bright head
        let glyphs = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789Z:・=*+<>").map { String($0) }
        var seed: UInt64 = 0x5EED_1999
        func rnd() -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int(seed >> 33) }
        let cols = 6, cw = box.width / CGFloat(cols), gh = cw * 1.12
        let mfont = NSFont(name: "Hiragino Kaku Gothic ProN W6", size: cw * 0.92) ?? NSFont.monospacedSystemFont(ofSize: cw * 0.92, weight: .bold)
        let rows = Int(box.height / gh) + 2
        for c in 0..<cols {
            let head = 2 + rnd() % (rows - 2), len = 4 + rnd() % 4
            for r in 0..<rows {
                let d = head - r                       // distance above the head (rows count from the top)
                let inTrail = d >= 0 && d < len
                let a: CGFloat = !inTrail ? 0.22 : d == 0 ? 1.0 : 0.95 - 0.6 * CGFloat(d) / CGFloat(len)
                let col = d == 0 ? NSColor(srgbRed: 0.80, green: 1.0, blue: 0.85, alpha: a)
                                 : NSColor(srgbRed: 0.05, green: 0.95, blue: 0.30, alpha: a)
                let g = glyphs[rnd() % glyphs.count] as NSString
                let at: [NSAttributedString.Key: Any] = [.font: mfont, .foregroundColor: col]
                let sz = g.size(withAttributes: at)
                g.draw(at: NSPoint(x: box.minX + CGFloat(c) * cw + (cw - sz.width) / 2, y: box.maxY - CGFloat(r + 1) * gh + gh * 0.1),
                       withAttributes: at)
            }
        }
        NSColor(white: 0, alpha: 0.18).setFill(); box.fill()      // the letters read over the rain
        let R = box.width * 0.47, cx = s / 2, cy = s / 2, c: CGFloat = 0.8660254
        for d: CGFloat in [1, -1] {
            let b = NSBezierPath(); b.move(to: NSPoint(x: cx, y: cy + d * R))
            b.line(to: NSPoint(x: cx - c * R, y: cy - d * R / 2)); b.line(to: NSPoint(x: cx + c * R, y: cy - d * R / 2)); b.close()
            b.lineWidth = s * 0.045; b.lineJoinStyle = .round; NSColor(white: 1, alpha: 0.55).setStroke(); b.stroke()
        }
    } else if isTerm {
        // nothing behind the letters: the cursor is drawn after them
    } else if symbol == "sunmoon" {
        // sunmoon (Marko 5.11.2026, Screen Brightness Automatic: "black background, and the symbol is half sun, half moon,
        // sharing one circle"): one circle split down the middle, the left half a warm sun with rays, the right half a pale
        // moon with a crescent cut; dimmed so the six letters read over it
        let cx = s / 2, cy = s / 2, R = box.width * 0.30
        let sun = NSColor(srgbRed: 1.0, green: 0.74, blue: 0.16, alpha: 0.62), moon = NSColor(white: 0.86, alpha: 0.50)
        let ray = NSBezierPath(); ray.lineWidth = s * 0.028; ray.lineCapStyle = .round
        for i in 0...6 {                       // rays on the sun's side only, from top to bottom
            let a = CGFloat.pi / 2 + CGFloat(i) * CGFloat.pi / 6
            ray.move(to: NSPoint(x: cx + cos(a) * R * 1.22, y: cy + sin(a) * R * 1.22))
            ray.line(to: NSPoint(x: cx + cos(a) * R * 1.48, y: cy + sin(a) * R * 1.48))
        }
        sun.setStroke(); ray.stroke()
        let left = NSBezierPath(); left.move(to: NSPoint(x: cx, y: cy + R))
        left.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: R, startAngle: 90, endAngle: 270); left.close()
        sun.setFill(); left.fill()
        NSGraphicsContext.saveGraphicsState()
        let right = NSBezierPath(); right.move(to: NSPoint(x: cx, y: cy - R))
        right.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: R, startAngle: 270, endAngle: 450); right.close()
        right.addClip(); moon.setFill(); right.fill()
        // the crescent: a dark circle bites into the moon half, kept inside it by the clip
        let cr = R * 0.80, ccx = cx - R * 0.12, ccy = cy + R * 0.14
        NSColor(white: 0.04, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: ccx - cr, y: ccy - cr, width: 2 * cr, height: 2 * cr)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let ring = NSBezierPath(ovalIn: NSRect(x: cx - R, y: cy - R, width: 2 * R, height: 2 * R))
        ring.lineWidth = s * 0.012; NSColor(white: 1, alpha: 0.35).setStroke(); ring.stroke()
    } else if symbol.hasPrefix("wordmark:") {
        // wordmark:<WORD>:<#hex> = a company's logotype behind the letters (Marko 5.11.2026: "The text background is
        // Oracle Logotype"): the word in its own colour, wide and heavy, across the middle of the tile
        let parts = symbol.split(separator: ":").map(String.init)
        let word = parts[1] as NSString, c = parts.count > 2 ? hex(parts[2]) : white
        var f = s * 0.30
        var at: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: f, weight: .black), .foregroundColor: c, .kern: s * 0.004]
        while word.size(withAttributes: at).width > box.width * 0.94 { f *= 0.96; at[.font] = NSFont.systemFont(ofSize: f, weight: .black) }
        let sz = word.size(withAttributes: at); word.draw(at: NSPoint(x: (s - sz.width) / 2, y: (s - sz.height) / 2), withAttributes: at)
    } else if symbol.hasPrefix("text:") {
        let g = String(symbol.dropFirst(5)) as NSString
        let at: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: s * 0.75, weight: .bold), .foregroundColor: white]
        let sz = g.size(withAttributes: at); g.draw(at: NSPoint(x: (s - sz.width) / 2, y: (s - sz.height) / 2), withAttributes: at)
    } else {
        let name = symbol.hasPrefix("sf:") ? String(symbol.dropFirst(3)) : symbol
        let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.62, weight: .bold)
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
            centred(NSImage(size: img.size, flipped: false) { r in img.draw(in: r); white.set(); r.fill(using: .sourceAtop); return true }, 0.98)
        } else { FileHandle.standardError.write("no symbol \(name)\n".data(using: .utf8)!) }
    }
    // the six letters: one size for both rows, the wider row fills 76 % of the tile
    var fs = s * 0.40
    let shadow = NSShadow(); shadow.shadowColor = NSColor(white: 0, alpha: 0.75)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.008); shadow.shadowBlurRadius = s * 0.025
    func attrs(_ f: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: font(f), .foregroundColor: NSColor.white, .shadow: shadow, .kern: f * 0.02] }
    let wmax = max((top as NSString).size(withAttributes: attrs(fs)).width, (bottom as NSString).size(withAttributes: attrs(fs)).width)
    fs *= box.width * 0.68 / wmax
    fs = min(fs, s * 0.34)
    // Marko 5.11.2026 ("rename the icon of the launcher into only LAUNCH ... bigger text ... all cursors should be thin
    // cursors, too thick ... taking too much space"): one word fills 84 % of the tile; every cursor a thin bar
    if lead {
        let w1 = (top as NSString).size(withAttributes: attrs(fs)).width
        fs = min(fs * box.width * 0.84 / (w1 + font(fs).capHeight * 0.30), s * 0.42)
    }
    let f = font(fs), cap = f.capHeight, gap = cap * 0.42
    let y0 = s / 2 - (2 * cap + gap) / 2           // baseline of the bottom row
    let cw = isTerm ? cap * 0.13 : 0          // the thin cursor bar (was a block, 0.62)
    let cgap = cap * 0.17                     // the space between the bar and the word
    if lead {
        // one row, in the middle, the cursor first
        let w = (top as NSString).size(withAttributes: attrs(fs)).width
        let x = (s - w - cw - cgap) / 2, base = s / 2 - cap / 2
        terminalGreen.setFill(); NSRect(x: x, y: base - cap * 0.08, width: cw, height: cap * 1.16).fill()
        (top as NSString).draw(at: NSPoint(x: x + cw + cgap, y: base + f.descender), withAttributes: attrs(fs))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
    for (str, base) in [(bottom, y0), (top, y0 + cap + gap)] {
        let w = (str as NSString).size(withAttributes: attrs(fs)).width
        let x = (s - w - (str == bottom && cw > 0 ? cw + cgap : 0)) / 2 + fs * 0.01
        (str as NSString).draw(at: NSPoint(x: x, y: base + f.descender), withAttributes: attrs(fs))
        if str == bottom && cw > 0 {
            terminalGreen.setFill(); NSRect(x: x + w + cgap, y: base - cap * 0.08, width: cw, height: cap * 1.16).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
func png(_ r: NSBitmapImageRep) -> Data { r.representation(using: .png, properties: [:])! }
var made: [(String, NSBitmapImageRep)] = []
let order = cats.keys.sorted().flatMap { cats[$0]!["apps"] as! [String] }
let byKey = Dictionary(uniqueKeysWithValues: (table["icons"] as! [[String]]).map { ($0[0], $0) })
for e in order.compactMap({ byKey[$0] }) {
    let key = e[0]; if let o = only, o != key { continue }
    let col = hex(colourOf[key] ?? "#3A4150")
    let dir = "\(out)/\(key)", set = "\(dir)/AppIcon.iconset"
    try? FileManager.default.removeItem(atPath: set)
    try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
    for (n, p) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
        try! png(draw(p, top: e[1], bottom: e[2], symbol: e[3], color: col)).write(to: URL(fileURLWithPath: "\(set)/icon_\(n).png"))
    }
    let big = draw(1024, top: e[1], bottom: e[2], symbol: e[3], color: col)
    try! png(big).write(to: URL(fileURLWithPath: "\(dir)/icon_1024.png"))
    let p = Process(); p.launchPath = "/usr/bin/iconutil"; p.arguments = ["-c", "icns", set, "-o", "\(dir)/AppIcon.icns"]
    p.launch(); p.waitUntilExit()
    try? FileManager.default.removeItem(atPath: set)
    made.append((key, big))
}
// the contact sheet: each icon at 128 and beside it at 48, on a light and a dark band
let cols = 8, cell = 200, rowsN = (made.count + cols - 1) / cols
let W = cols * cell, H = rowsN * cell
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
NSColor(white: 0.93, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
for (i, (key, rep)) in made.enumerated() {
    let x = CGFloat((i % cols) * cell), y = CGFloat(H - (i / cols + 1) * cell)
    let img = NSImage(size: NSSize(width: 1024, height: 1024)); img.addRepresentation(rep)
    img.draw(in: NSRect(x: x + 4, y: y + 50, width: 128, height: 128))
    img.draw(in: NSRect(x: x + 140, y: y + 50, width: 48, height: 48))
    (key as NSString).draw(at: NSPoint(x: x + 8, y: y + 22), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.black])
}
NSGraphicsContext.restoreGraphicsState()
try! png(sheet).write(to: URL(fileURLWithPath: "\(out)/sheet.png"))
print("made \(made.count) icons in \(out)")
