// Draws the app icon and writes a 1024px PNG. Usage: swift make-icon.swift <output.png>
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let inset = 100.0
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let background = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.36, green: 0.56, blue: 0.98, alpha: 1),
                    NSColor(red: 0.22, green: 0.30, blue: 0.80, alpha: 1)])!.draw(in: background, angle: -90)

// Three stacked cards, the front one white.
func card(_ x: Double, _ y: Double, _ alpha: Double) {
    NSColor.white.withAlphaComponent(alpha).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 400, height: 460), xRadius: 56, yRadius: 56).fill()
}
card(392, 352, 0.30)
card(312, 292, 0.55)
card(232, 232, 1.0)

// Plus sign on the front card
NSColor(red: 0.24, green: 0.36, blue: 0.86, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 404, y: 342, width: 56, height: 240), xRadius: 28, yRadius: 28).fill()
NSBezierPath(roundedRect: NSRect(x: 312, y: 434, width: 240, height: 56), xRadius: 28, yRadius: 28).fill()

image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
