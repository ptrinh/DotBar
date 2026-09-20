// Renders the DotBar app icon: rounded dark tile, "D" glyph is implied by text bar + 3 dots.
import AppKit
let size = CGFloat(CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1])! : 1024)
let out = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "AppIcon-master.png"
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.setAllowsAntialiasing(true)
let inset = size * 0.08
let tile = NSRect(x: inset, y: inset, width: size - inset*2, height: size - inset*2)
let path = NSBezierPath(roundedRect: tile, xRadius: size*0.2, yRadius: size*0.2)
NSGradient(starting: NSColor(calibratedWhite: 0.16, alpha: 1), ending: NSColor(calibratedWhite: 0.07, alpha: 1))!.draw(in: path, angle: -90)
// text bar (three rounded lines, like menu bar text)
let barX = tile.minX + tile.width*0.16
let barW = tile.width*0.44
let lineH = tile.height*0.075
let ys: [CGFloat] = [0.63, 0.46, 0.29]
for (i, fy) in ys.enumerated() {
    let w = barW * (i == 1 ? 0.75 : 1)
    let r = NSRect(x: barX, y: tile.minY + tile.height*fy, width: w, height: lineH)
    NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
    NSBezierPath(roundedRect: r, xRadius: lineH/2, yRadius: lineH/2).fill()
}
// three dots stacked vertically
let d = tile.width*0.13
let dx = tile.maxX - tile.width*0.2 - d
let colors = [NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1),
              NSColor(srgbRed: 1.00, green: 0.62, blue: 0.04, alpha: 1),
              NSColor(srgbRed: 1.00, green: 0.27, blue: 0.23, alpha: 1)]
for (i, c) in colors.enumerated() {
    let cy = tile.minY + tile.height*(0.70 - CGFloat(i)*0.19)
    let r = NSRect(x: dx, y: cy - d/2 + lineH/2, width: d, height: d)
    ctx.setShadow(offset: CGSize(width: 0, height: -size*0.006), blur: size*0.02, color: NSColor.black.withAlphaComponent(0.5).cgColor)
    c.setFill(); NSBezierPath(ovalIn: r).fill()
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
