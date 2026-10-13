// The icon, drawn: three progress bars at different fill, a down arrow over them; the version under it.
import AppKit
let S: CGFloat = 1024
let version = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "1"
let img = NSImage(size: NSSize(width: S, height: S)); img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 180, cornerHeight: 180, transform: nil))
ctx.setFillColor(NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.06, alpha: 1).cgColor); ctx.fillPath()
let amber = NSColor(calibratedRed: 0.91, green: 0.64, blue: 0.24, alpha: 1), green = NSColor(calibratedRed: 0.2, green: 0.82, blue: 0.48, alpha: 1)
for (i, f) in [CGFloat(1.0), 0.62, 0.3].enumerated() {
    let y = 470 - CGFloat(i) * 110
    ctx.addPath(CGPath(roundedRect: CGRect(x: 200, y: y, width: 624, height: 56), cornerWidth: 18, cornerHeight: 18, transform: nil))
    ctx.setFillColor(NSColor(calibratedWhite: 0.18, alpha: 1).cgColor); ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 200, y: y, width: 624 * f, height: 56), cornerWidth: 18, cornerHeight: 18, transform: nil))
    ctx.setFillColor((i == 0 ? green : amber).cgColor); ctx.fillPath()
}
ctx.setFillColor(NSColor(calibratedWhite: 0.88, alpha: 1).cgColor)
ctx.fill(CGRect(x: 472, y: 640, width: 80, height: 170))
let a = CGMutablePath(); a.move(to: CGPoint(x: 400, y: 650)); a.addLine(to: CGPoint(x: 624, y: 650)); a.addLine(to: CGPoint(x: 512, y: 560)); a.closeSubpath()
ctx.addPath(a); ctx.fillPath()
("v" + version as NSString).draw(at: NSPoint(x: 170, y: 150), withAttributes: [.font: NSFont.systemFont(ofSize: 92, weight: .semibold), .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1)])
img.unlockFocus()
try! NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icon_1024.png"))
