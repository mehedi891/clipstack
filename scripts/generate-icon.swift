#!/usr/bin/env swift
// Renders Clipstack's app icon.
//
// The menu-bar glyph is an SF Symbol, not generated here: a scaled-down logo
// does not stay legible at 18pt.
//
// Drawn in code rather than shipped as binary assets so the icon stays in sync
// with the app's design tokens (Sources/Clipstack/UI/Theme.swift) and can be
// re-rendered at any size without a design tool.
//
//   swift scripts/generate-icon.swift
//
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Brand

/// Matches Theme.accentStart / Theme.accentEnd.
let accentStart = (r: 0.42, g: 0.36, b: 0.98)   // violet
let accentEnd   = (r: 0.24, g: 0.72, b: 0.94)   // cyan

// MARK: - Geometry

/// Apple's squircle is a superellipse, not a circular-cornered rectangle.
/// Approximating it properly is most of what makes an icon read as native.
func squirclePath(in rect: CGRect, exponent: Double = 5.0, samples: Int = 720) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY

    for i in 0...samples {
        let theta = 2 * Double.pi * Double(i) / Double(samples)
        let cosT = cos(theta), sinT = sin(theta)

        // Superellipse in polar-ish form: sign preserved, magnitude raised to 2/n.
        let x = pow(abs(cosT), 2.0 / exponent) * (cosT < 0 ? -1 : 1) * a
        let y = pow(abs(sinT), 2.0 / exponent) * (sinT < 0 ? -1 : 1) * b
        let point = CGPoint(x: cx + x, y: cy + y)

        i == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// MARK: - Rendering

func makeContext(size: Int) -> CGContext {
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    return context
}

/// Draws the icon on a 1024-unit grid, scaled to the requested pixel size, so
/// proportions are identical at every resolution.
func drawIcon(in context: CGContext, size: Int) {
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)

    // macOS icon grid: an 824pt rounded square inside a 1024pt canvas, sitting
    // slightly low to leave room for its shadow.
    let body = CGRect(x: 100, y: 110, width: 824, height: 824)
    let shape = squirclePath(in: body)

    // Drop shadow, skipped at small sizes where it only muddies the edges.
    if size >= 128 {
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -18), blur: 44,
                          color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.30))
        context.addPath(shape)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fillPath()
        context.restoreGState()
    }

    // Gradient body.
    context.saveGState()
    context.addPath(shape)
    context.clip()

    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            CGColor(red: accentStart.r, green: accentStart.g, blue: accentStart.b, alpha: 1),
            CGColor(red: accentEnd.r, green: accentEnd.g, blue: accentEnd.b, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: body.minX, y: body.maxY),   // top-left
        end: CGPoint(x: body.maxX, y: body.minY),     // bottom-right
        options: []
    )

    // Glass highlight across the top, which is what sells the "modern macOS"
    // look more than any single shape does.
    let sheen = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.28),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        sheen,
        start: CGPoint(x: body.midX, y: body.maxY),
        end: CGPoint(x: body.midX, y: body.midY + 40),
        options: []
    )
    context.restoreGState()

    // The stack: three sheets, each further back drawn narrower and dimmer so
    // the layering reads even at 16pt.
    //
    // The group sits a little above true centre. The front sheet is the largest
    // and brightest, so it carries most of the visual weight; centring the
    // geometry exactly would leave the icon looking bottom-heavy.
    let sheets: [(width: CGFloat, bottom: CGFloat, alpha: CGFloat, radius: CGFloat)] = [
        (346, 470, 0.42, 42),   // back
        (392, 398, 0.68, 46),   // middle
        (440, 310, 1.00, 52),   // front
    ]
    let sheetHeight: CGFloat = 290

    for sheet in sheets {
        let rect = CGRect(
            x: 512 - sheet.width / 2,
            y: sheet.bottom,
            width: sheet.width,
            height: sheetHeight
        )

        context.saveGState()
        if size >= 128 {
            context.setShadow(offset: CGSize(width: 0, height: -8), blur: 20,
                              color: CGColor(red: 0.06, green: 0.06, blue: 0.20, alpha: 0.35))
        }
        context.addPath(roundedPath(rect, radius: sheet.radius))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: sheet.alpha))
        context.fillPath()
        context.restoreGState()
    }

    // Content lines on the front sheet, so the icon reads as copied text rather
    // than as generic stacked windows. Omitted below 128pt, where they would
    // smear into a grey band instead of resolving.
    guard size >= 128 else { return }

    let front = sheets[2]
    let inset: CGFloat = 52
    let lineX = 512 - front.width / 2 + inset
    let lineWidth = front.width - inset * 2

    let lines: [(y: CGFloat, width: CGFloat)] = [
        (505, lineWidth),
        (444, lineWidth),
        (383, lineWidth * 0.58),   // ragged last line, as real text wraps
    ]

    context.setFillColor(CGColor(red: accentStart.r, green: accentStart.g,
                                 blue: accentStart.b, alpha: 0.30))
    for line in lines {
        context.addPath(roundedPath(
            CGRect(x: lineX, y: line.y, width: line.width, height: 26),
            radius: 13
        ))
        context.fillPath()
    }
}

func write(_ context: CGContext, to url: URL) {
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
              url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("Could not encode \(url.lastPathComponent)") }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Could not write \(url.lastPathComponent)")
    }
}

// MARK: - Output

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/Clipstack.iconset")
let assets = root.appendingPathComponent("Assets")

try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

// The exact filenames iconutil expects.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    let context = makeContext(size: variant.pixels)
    drawIcon(in: context, size: variant.pixels)
    write(context, to: iconset.appendingPathComponent("\(variant.name).png"))
}

// A full-size preview, handy for store listings and README.
let preview = makeContext(size: 1024)
drawIcon(in: preview, size: 1024)
write(preview, to: assets.appendingPathComponent("icon-1024.png"))

print("Rendered \(variants.count) icon sizes → \(iconset.path)")
print("Preview → \(assets.path)")
