// Renders the source PNG for AppIcon.icns.
//
//   swift Scripts/make-icon.swift <output.png>
//
// The script draws a 1024pt squircle with a violet gradient, a monospace
// "</>" and a caret bar, then writes a single PNG. build-app.sh downsamples it
// into an .iconset and runs iconutil.
import AppKit

let dimension = 1024
let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

guard
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: dimension,
        pixelsHigh: dimension,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
else {
    fatalError("could not allocate bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext

let side = CGFloat(dimension)
let margin: CGFloat = 96
let squircle = CGRect(
    x: margin,
    y: margin,
    width: side - margin * 2,
    height: side - margin * 2
)

// Gradient plate, clipped to the squircle.
context.saveGState()
context.addPath(CGPath(roundedRect: squircle, cornerWidth: 224, cornerHeight: 224, transform: nil))
context.clip()

let space = CGColorSpaceCreateDeviceRGB()
let plate = CGGradient(
    colorsSpace: space,
    colors: [
        NSColor(calibratedRed: 0.36, green: 0.20, blue: 0.78, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.62, green: 0.32, blue: 0.92, alpha: 1).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    plate,
    start: CGPoint(x: squircle.minX, y: squircle.maxY),
    end: CGPoint(x: squircle.maxX, y: squircle.minY),
    options: []
)

// Soft highlight so the plate reads as glass rather than flat fill.
let highlight = CGGradient(
    colorsSpace: space,
    colors: [
        NSColor(white: 1, alpha: 0.22).cgColor,
        NSColor(white: 1, alpha: 0).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
context.drawRadialGradient(
    highlight,
    startCenter: CGPoint(x: squircle.midX - 160, y: squircle.maxY - 140),
    startRadius: 0,
    endCenter: CGPoint(x: squircle.midX - 160, y: squircle.maxY - 140),
    endRadius: 620,
    options: []
)
context.restoreGState()

// Glyph.
let glyph = NSAttributedString(
    string: "</>",
    attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 292, weight: .bold),
        .foregroundColor: NSColor.white,
    ]
)
let glyphSize = glyph.size()
glyph.draw(
    at: CGPoint(
        x: squircle.midX - glyphSize.width / 2,
        y: squircle.midY - glyphSize.height / 2 - 10
    )
)

// Caret bar.
let caret = NSBezierPath(
    roundedRect: CGRect(x: squircle.midX - 66, y: squircle.midY - 268, width: 132, height: 28),
    xRadius: 14,
    yRadius: 14
)
NSColor(calibratedRed: 0.63, green: 0.95, blue: 0.79, alpha: 1).setFill()
caret.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("could not encode PNG")
}
try png.write(to: URL(fileURLWithPath: outputPath))
