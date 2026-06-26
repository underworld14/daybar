#!/usr/bin/env swift
import AppKit

// Renders the DayBar app icon (a calm indigo squircle with a bold white checkmark) at every
// macOS size into DayBar/Assets.xcassets/AppIcon.appiconset. Run from the repo root:
//   swift Scripts/make_icon.swift
// Output PNGs are committed, so the build never depends on this script.

let outDir = "DayBar/Assets.xcassets/AppIcon.appiconset"

func render(px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: px, height: px)
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let s = CGFloat(px)

    // Rounded "squircle" tile with a small inset.
    let inset = s * 0.06
    let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = tile.width * 0.2237
    let path = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    let colors = [
        NSColor(srgbRed: 0.36, green: 0.42, blue: 0.95, alpha: 1).cgColor, // indigo (top)
        NSColor(srgbRed: 0.20, green: 0.24, blue: 0.66, alpha: 1).cgColor, // deeper (bottom)
    ]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    cg.restoreGState()

    // Bold white checkmark (bottom-left origin: smaller y = lower).
    cg.setLineWidth(s * 0.085)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.setStrokeColor(NSColor.white.cgColor)
    cg.move(to: CGPoint(x: tile.minX + tile.width * 0.30, y: tile.minY + tile.height * 0.52))
    cg.addLine(to: CGPoint(x: tile.minX + tile.width * 0.44, y: tile.minY + tile.height * 0.36))
    cg.addLine(to: CGPoint(x: tile.minX + tile.width * 0.72, y: tile.minY + tile.height * 0.66))
    cg.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let entries: [(pt: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func filename(px: Int) -> String { "icon_\(px).png" }

var written = Set<Int>()
var images: [[String: String]] = []
for entry in entries {
    let px = entry.pt * entry.scale
    if !written.contains(px), let data = render(px: px) {
        try? data.write(to: URL(fileURLWithPath: "\(outDir)/\(filename(px: px))"))
        written.insert(px)
    }
    images.append([
        "size": "\(entry.pt)x\(entry.pt)",
        "idiom": "mac",
        "filename": filename(px: px),
        "scale": "\(entry.scale)x",
    ])
}

let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: URL(fileURLWithPath: "\(outDir)/Contents.json"))
print("DayBar icon: wrote \(written.count) PNG sizes + Contents.json to \(outDir)")
