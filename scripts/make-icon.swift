// Draws the app icon and writes a 1024px PNG. Usage: swift make-icon.swift <output.png>
// A stack of copied cards, the newest one ticked: "copy that" as in "got it".
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let inset = 100.0
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let background = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.27, green: 0.22, blue: 0.56, alpha: 1),
                    NSColor(red: 0.10, green: 0.08, blue: 0.24, alpha: 1)])!.draw(in: background, angle: -90)

let violet = NSColor(red: 0.56, green: 0.50, blue: 1.00, alpha: 1)
let mint = NSColor(red: 0.18, green: 0.83, blue: 0.68, alpha: 1)
let amber = NSColor(red: 1.00, green: 0.80, blue: 0.36, alpha: 1)
let ink = NSColor(red: 0.13, green: 0.10, blue: 0.30, alpha: 1)

let cardWidth = 400.0, cardHeight = 480.0, step = 74.0
let originX = (size - cardWidth) / 2 - step, originY = (size - cardHeight) / 2 - step

/// One card of the stack; `index` 0 is the front one, lower left.
func card(_ index: Int, _ color: NSColor) -> NSRect {
    let frame = NSRect(x: originX + step * Double(index), y: originY + step * Double(index), width: cardWidth, height: cardHeight)
    // A dark rim keeps the cards apart where they overlap.
    ink.withAlphaComponent(0.55).setFill()
    NSBezierPath(roundedRect: frame.insetBy(dx: -14, dy: -14), xRadius: 86, yRadius: 86).fill()
    color.setFill()
    NSBezierPath(roundedRect: frame, xRadius: 72, yRadius: 72).fill()
    return frame
}

_ = card(2, mint)
_ = card(1, violet)
let front = card(0, amber)

// The tick on the front card
let tick = NSBezierPath()
tick.move(to: NSPoint(x: front.minX + 104, y: front.midY - 6))
tick.line(to: NSPoint(x: front.minX + 176, y: front.midY - 82))
tick.line(to: NSPoint(x: front.maxX - 100, y: front.midY + 92))
tick.lineWidth = 58
tick.lineCapStyle = .round
tick.lineJoinStyle = .round
ink.setStroke()
tick.stroke()

image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
