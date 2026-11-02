// Renders the source PNG for AppIcon.icns in liquid glass macOS convention.
//
//   swift Scripts/make-icon.swift <output.png>
//
// If a master asset is present at Resources/AppIcon.png, it is copied directly.
// Otherwise, it procedurally renders an Apple HIG compliant 1024x1024 icon
// featuring an 824x824 squircle, dual-layer ambient and contact drop shadows,
// deep obsidian and emerald liquid glass fluid, and frosted glass code brackets.
import AppKit

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let destinationURL = URL(fileURLWithPath: outputPath)

// Check if master asset exists in Resources/
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let rootURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let masterAssetURL = rootURL.appendingPathComponent("Resources/AppIcon.png")

if FileManager.default.fileExists(atPath: masterAssetURL.path) {
    if masterAssetURL.standardizedFileURL != destinationURL.standardizedFileURL {
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.copyItem(at: masterAssetURL, to: destinationURL)
    }
    exit(0)
}

// Procedural Liquid Glass Generator Fallback
let dimension: CGFloat = 1024
let bodySize: CGFloat = 824
let margin: CGFloat = (dimension - bodySize) / 2
let cornerRadius: CGFloat = 185

guard
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(dimension),
        pixelsHigh: Int(dimension),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
else {
    fatalError("Could not allocate bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext

let squircleRect = CGRect(x: margin, y: margin, width: bodySize, height: bodySize)
let squirclePath = CGPath(
    roundedRect: squircleRect,
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
)

// 1. Ambient Drop Shadow (Apple HIG: blur ~28, offset ~22 down, 20% opacity)
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -22),
    blur: 28,
    color: NSColor(white: 0, alpha: 0.22).cgColor
)
context.addPath(squirclePath)
context.setFillColor(NSColor.black.cgColor)
context.fillPath()
context.restoreGState()

// 2. Contact Drop Shadow (Apple HIG: blur ~14, offset ~10 down, 25% opacity)
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -10),
    blur: 14,
    color: NSColor(white: 0, alpha: 0.25).cgColor
)
context.addPath(squirclePath)
context.setFillColor(NSColor.black.cgColor)
context.fillPath()
context.restoreGState()

// 3. Liquid Glass Plate (Clipped)
context.saveGState()
context.addPath(squirclePath)
context.clip()

let colorSpace = CGColorSpaceCreateDeviceRGB()

// Deep Obsidian / Midnight Sapphire Base
let basePlate = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.14, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.01, green: 0.02, blue: 0.06, alpha: 1.0).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    basePlate,
    start: CGPoint(x: squircleRect.minX, y: squircleRect.maxY),
    end: CGPoint(x: squircleRect.maxX, y: squircleRect.minY),
    options: []
)

// Internal Liquid Emerald & Teal Caustics
let liquidCaustic = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.65, alpha: 0.75).cgColor,
        NSColor(calibratedRed: 0.0, green: 0.45, blue: 0.75, alpha: 0.40).cgColor,
        NSColor(calibratedRed: 0.1, green: 0.05, blue: 0.35, alpha: 0.0).cgColor,
    ] as CFArray,
    locations: [0.0, 0.45, 1.0]
)!
context.drawRadialGradient(
    liquidCaustic,
    startCenter: CGPoint(x: squircleRect.minX + 260, y: squircleRect.minY + 280),
    startRadius: 0,
    endCenter: CGPoint(x: squircleRect.minX + 260, y: squircleRect.minY + 280),
    endRadius: 520,
    options: []
)

// Secondary Cyan / Violet Liquid Flare
let liquidFlare = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        NSColor(calibratedRed: 0.2, green: 0.7, blue: 1.0, alpha: 0.65).cgColor,
        NSColor(calibratedRed: 0.5, green: 0.2, blue: 0.9, alpha: 0.25).cgColor,
        NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.0).cgColor,
    ] as CFArray,
    locations: [0.0, 0.5, 1.0]
)!
context.drawRadialGradient(
    liquidFlare,
    startCenter: CGPoint(x: squircleRect.maxX - 240, y: squircleRect.maxY - 220),
    startRadius: 0,
    endCenter: CGPoint(x: squircleRect.maxX - 240, y: squircleRect.maxY - 220),
    endRadius: 480,
    options: []
)

// 4. Frosted Glass Code Brackets Glyph (< / >)
let glyph = NSAttributedString(
    string: "</>",
    attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 260, weight: .semibold),
        .foregroundColor: NSColor(white: 0.95, alpha: 0.90),
    ]
)
let glyphSize = glyph.size()
let glyphOrigin = CGPoint(
    x: squircleRect.midX - glyphSize.width / 2,
    y: squircleRect.midY - glyphSize.height / 2 - 12
)

// Soft under-glow for glyph
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: 4),
    blur: 18,
    color: NSColor(calibratedRed: 0.0, green: 0.9, blue: 0.7, alpha: 0.5).cgColor
)
glyph.draw(at: glyphOrigin)
context.restoreGState()

// 5. Specular Inner Rim Highlight (Apple HIG Glass Convention)
context.addPath(squirclePath)
context.setLineWidth(2.5)
let rimColors =
    [
        NSColor(white: 1.0, alpha: 0.45).cgColor,
        NSColor(white: 1.0, alpha: 0.08).cgColor,
        NSColor(white: 0.0, alpha: 0.25).cgColor,
    ] as CFArray
let rimGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: rimColors,
    locations: [0.0, 0.45, 1.0]
)!
context.replacePathWithStrokedPath()
context.clip()
context.drawLinearGradient(
    rimGradient,
    start: CGPoint(x: 512, y: squircleRect.maxY),
    end: CGPoint(x: 512, y: squircleRect.minY),
    options: []
)

context.restoreGState()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}
try png.write(to: destinationURL)
