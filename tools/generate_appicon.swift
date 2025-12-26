#!/usr/bin/env swift
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: generate_appicon.swift <output-path>\n", stderr)
    exit(1)
}

let outputPath = args[1]
let outputURL = URL(fileURLWithPath: outputPath)
let directory = outputURL.deletingLastPathComponent()
try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

let size: CGFloat = 1024
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let image = NSImage(size: rect.size)
image.lockFocus()

// Background
let background = NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.10, alpha: 1)
background.setFill()
NSBezierPath(rect: rect).fill()

// Gradient halo
let gradientColors = [
    NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.37, alpha: 0.9),
    NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.37, alpha: 0.45),
    NSColor(calibratedWhite: 1.0, alpha: 0.05)
]
let gradient = NSGradient(colors: gradientColors)
let center = NSPoint(x: size / 2, y: size / 2)
gradient?.draw(in: NSBezierPath(ovalIn: NSRect(x: size * 0.2, y: size * 0.2, width: size * 0.6, height: size * 0.6)), relativeCenterPosition: .zero)
gradient?.draw(from: center, to: NSPoint(x: center.x, y: center.y + size * 0.2), options: [])

// Note glyph
let note = "♪"
let attributes: [NSAttributedString.Key: Any] = [
    .foregroundColor: NSColor.white,
    .font: NSFont.systemFont(ofSize: 420, weight: .bold)
]
let text = NSAttributedString(string: note, attributes: attributes)
let textSize = text.size()
let textRect = NSRect(
    x: (size - textSize.width) / 2,
    y: (size - textSize.height) / 2,
    width: textSize.width,
    height: textSize.height
)
text.draw(in: textRect)

image.unlockFocus()

guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to render app icon\n", stderr)
    exit(1)
}

do {
    try png.write(to: outputURL)
    print("Generated app icon at \(outputPath)")
} catch {
    fputs("Failed to write icon: \(error)\n", stderr)
    exit(1)
}
