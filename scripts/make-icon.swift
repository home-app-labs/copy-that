// Draws the app icon and writes a 1024px PNG. Usage: swift make-icon.swift <output.png>
// Three copied things stacked like the cards in the app: a colour, a picture and a piece of code.
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
let ink = NSColor(red: 0.10, green: 0.08, blue: 0.22, alpha: 1)

let cardWidth = 440.0, cardHeight = 300.0, stepX = 85.0, stepY = 120.0, corner = 54.0
let originX = (size - cardWidth - 2 * stepX) / 2, originY = (size - cardHeight - 2 * stepY) / 2

/// Draws one card of the stack; `index` 0 is the front one, lower left. `content` draws inside it, clipped.
func card(_ index: Int, content: (NSRect) -> Void) {
    let frame = NSRect(x: originX + stepX * Double(index), y: originY + stepY * Double(index), width: cardWidth, height: cardHeight)
    // A dark rim keeps the cards apart where they overlap.
    ink.withAlphaComponent(0.6).setFill()
    NSBezierPath(roundedRect: frame.insetBy(dx: -13, dy: -13), xRadius: corner + 13, yRadius: corner + 13).fill()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: frame, xRadius: corner, yRadius: corner).addClip()
    content(frame)
    NSGraphicsContext.restoreGraphicsState()
}

func bar(_ x: Double, _ y: Double, _ width: Double, _ color: NSColor, height: Double = 30) {
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: height / 2, yRadius: height / 2).fill()
}

// Back: a copied colour, with the pill its code sits in.
card(2) { frame in
    amber.setFill()
    frame.fill()
    bar(frame.minX + 44, frame.maxY - 86, 190, NSColor(white: 1, alpha: 0.45), height: 44)
}

// Middle: a copied picture.
card(1) { frame in
    NSGradient(colors: [NSColor(red: 0.62, green: 0.84, blue: 1.00, alpha: 1),
                        NSColor(red: 0.24, green: 0.52, blue: 0.96, alpha: 1)])!.draw(in: frame, angle: 90)
    NSColor(red: 1.00, green: 0.90, blue: 0.55, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: frame.maxX - 150, y: frame.maxY - 124, width: 88, height: 88)).fill()
    func hills(_ points: [(Double, Double)], _ color: NSColor) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: frame.minX, y: frame.minY))
        points.forEach { path.line(to: NSPoint(x: frame.minX + $0.0 * frame.width, y: frame.minY + $0.1 * frame.height)) }
        path.line(to: NSPoint(x: frame.maxX, y: frame.minY))
        path.close()
        color.setFill()
        path.fill()
    }
    hills([(0, 0.62), (0.22, 0.90), (0.42, 0.66), (0.60, 0.80), (0.80, 0.50), (1, 0.62)], violet)
    hills([(0, 0.40), (0.30, 0.66), (0.55, 0.42), (0.78, 0.60), (1, 0.36)], NSColor(red: 0.33, green: 0.27, blue: 0.72, alpha: 1))
}

// Front: a copied piece of code.
card(0) { frame in
    NSColor(red: 0.07, green: 0.06, blue: 0.15, alpha: 1).setFill()
    frame.fill()
    let left = frame.minX + 46, top = frame.maxY - 76, line = 50.0
    bar(left, top, 104, violet)
    bar(left + 122, top, 150, NSColor(white: 1, alpha: 0.85))
    bar(left + 50, top - line, 196, mint)
    bar(left + 50, top - 2 * line, 92, amber)
    bar(left + 160, top - 2 * line, 124, NSColor(white: 1, alpha: 0.55))
    bar(left + 50, top - 3 * line, 150, violet)
    bar(left, top - 4 * line, 64, NSColor(white: 1, alpha: 0.85))
}

image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
