#!/usr/bin/env swift
import AppKit

// Draws the Fluxa icon: a toggle switch in ON position,
// monochromatic black on transparent background (template-ready for macOS menu bar).
func drawFluxaIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

    let w = size
    let h = size

    // --- Toggle track (pill shape, horizontal, centered) ---
    let trackW  = w * 0.72
    let trackH  = h * 0.42
    let trackX  = (w - trackW) / 2
    let trackY  = (h - trackH) / 2
    let trackRadius = trackH / 2

    let trackRect = CGRect(x: trackX, y: trackY, width: trackW, height: trackH)
    let trackPath = CGPath(roundedRect: trackRect,
                           cornerWidth: trackRadius,
                           cornerHeight: trackRadius,
                           transform: nil)

    // Fill track black
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.addPath(trackPath)
    ctx.fillPath()

    // --- Knob (circle, right side = ON position) ---
    let knobPad  = trackH * 0.10
    let knobSize = trackH - knobPad * 2
    // Right-aligned inside track
    let knobX = trackX + trackW - knobPad - knobSize
    let knobY = trackY + knobPad

    let knobRect = CGRect(x: knobX, y: knobY, width: knobSize, height: knobSize)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: knobRect)

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("❌ Failed to encode PNG for \(path)")
        return
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("✓ \(path)")
    } catch {
        print("❌ \(error.localizedDescription)")
    }
}

// --- Generate iconset ---
let iconsetPath = "/tmp/fluxa.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(name: String, size: CGFloat)] = [
    ("icon_16x16",      16),
    ("icon_16x16@2x",   32),
    ("icon_32x32",      32),
    ("icon_32x32@2x",   64),
    ("icon_128x128",    128),
    ("icon_128x128@2x", 256),
    ("icon_256x256",    256),
    ("icon_256x256@2x", 512),
    ("icon_512x512",    512),
    ("icon_512x512@2x", 1024),
]

for entry in sizes {
    let img = drawFluxaIcon(size: entry.size)
    savePNG(img, to: "\(iconsetPath)/\(entry.name).png")
}

print("\n✅ Iconset generated at \(iconsetPath)")
print("👉 Run: iconutil -c icns \(iconsetPath) -o /tmp/fluxa.icns")
