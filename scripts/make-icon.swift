#!/usr/bin/env swift
//
// Draws the app icon and assembles it into an .icns.
//
//   swift scripts/make-icon.swift Resources/AppIcon.icns
//
// CoreGraphics and ImageIO only, so it runs headless under the Command Line Tools, plus
// `iconutil`, which ships with macOS. The result is committed, so a normal build just
// copies it; run this only when the artwork changes.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum IconError: Error {
    case renderFailed
    case writeFailed(String)
    case iconutilFailed(Int32)
}

private func srgb(_ hex: UInt32, _ alpha: Double = 1) -> CGColor {
    CGColor(
        srgbRed: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        alpha: alpha
    )
}

private let colourSpace = CGColorSpace(name: CGColorSpace.sRGB)!

/// The background gradient, drawn across the whole canvas. Replaying it through the
/// keyhole is what punches a clean hole in the disc, since the disc sits on it.
private func drawBackground(_ context: CGContext, size: CGFloat) {
    guard let gradient = CGGradient(
        colorsSpace: colourSpace,
        colors: [srgb(0x4C7EC9), srgb(0x17253F)] as CFArray,
        locations: [0, 1]
    ) else { return }
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
}

/// A superellipse, which is the shape macOS uses for icon bodies rather than a plain
/// rounded rectangle.
private func squircle(in rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let halfWidth = rect.width / 2
    let halfHeight = rect.height / 2
    let steps = 720
    for step in 0...steps {
        let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let cosine = cos(angle)
        let sine = sin(angle)
        let x = rect.midX + halfWidth * copysign(pow(abs(cosine), 2 / exponent), cosine)
        let y = rect.midY + halfHeight * copysign(pow(abs(sine), 2 / exponent), sine)
        if step == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

/// A keyhole: a round head with a slot that widens downwards, cut out of the middle of
/// the disc. It is one simple closed curve rather than a circle plus a slot, because two
/// overlapping pieces cancel under either fill rule and leave a gap where they meet.
private func keyhole(centre: CGPoint, size: CGFloat) -> CGPath {
    let head = size * 0.055          // head centre, above the disc centre
    let radius = size * 0.112
    let chord = -size * 0.045        // the height where the head meets the slot
    let halfWidth = (radius * radius - (chord - head) * (chord - head)).squareRoot()
    let foot = -size * 0.205         // the bottom of the slot
    let footHalfWidth = size * 0.082

    let path = CGMutablePath()
    // Around the head the long way, from the left of the chord over the top to the right.
    let from = atan2(chord - head, -halfWidth)
    let to = atan2(chord - head, halfWidth) - 2 * .pi
    let steps = 180
    for step in 0...steps {
        let angle = from + (to - from) * CGFloat(step) / CGFloat(steps)
        let point = CGPoint(
            x: centre.x + radius * cos(angle),
            y: centre.y + head + radius * sin(angle)
        )
        if step == 0 {
            path.move(to: point)
        } else {
            path.addLine(to: point)
        }
    }
    path.addLine(to: CGPoint(x: centre.x + footHalfWidth, y: centre.y + foot))
    path.addLine(to: CGPoint(x: centre.x - footHalfWidth, y: centre.y + foot))
    path.closeSubpath()
    return path
}

private func render(size: CGFloat) -> CGImage? {
    let pixels = Int(size)
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colourSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    // Body: a superellipse with a soft top-to-bottom gradient, transparent outside it.
    let margin = size * 0.098
    let body = CGRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
    context.saveGState()
    context.addPath(squircle(in: body))
    context.clip()
    drawBackground(context, size: size)
    context.restoreGState()

    // The disc, lit from the top left.
    let centre = CGPoint(x: size / 2, y: size / 2)
    let radius = size * 0.345
    let disc = CGRect(
        x: centre.x - radius,
        y: centre.y - radius,
        width: radius * 2,
        height: radius * 2
    )
    context.saveGState()
    context.addEllipse(in: disc)
    context.clip()
    if let sheen = CGGradient(
        colorsSpace: colourSpace,
        colors: [srgb(0xFFFFFF), srgb(0xE4ECF8), srgb(0xB6C6DC), srgb(0xF1F6FD)] as CFArray,
        locations: [0, 0.4, 0.72, 1]
    ) {
        context.drawLinearGradient(
            sheen,
            start: CGPoint(x: disc.minX, y: disc.maxY),
            end: CGPoint(x: disc.maxX, y: disc.minY),
            options: []
        )
    }
    context.restoreGState()

    // The edge of the data area, which is what stops a smooth pale circle reading as a
    // ball rather than a disc.
    context.saveGState()
    context.addEllipse(in: CGRect(
        x: centre.x - size * 0.25,
        y: centre.y - size * 0.25,
        width: size * 0.5,
        height: size * 0.5
    ))
    context.setStrokeColor(srgb(0x8497B4, 0.38))
    context.setLineWidth(max(size * 0.008, 1))
    context.strokePath()
    context.restoreGState()

    context.saveGState()
    context.addPath(keyhole(centre: centre, size: size))
    context.clip()
    drawBackground(context, size: size)
    context.restoreGState()

    // A hairline so the disc keeps its edge at small sizes.
    context.saveGState()
    context.addEllipse(in: disc)
    context.setStrokeColor(srgb(0x0F1A30, 0.18))
    context.setLineWidth(max(size * 0.004, 1))
    context.strokePath()
    context.restoreGState()

    return context.makeImage()
}

private func write(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        throw IconError.writeFailed(url.path)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw IconError.writeFailed(url.path)
    }
}

do {
    let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"
    let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("PS3QDD-\(UUID().uuidString).iconset")
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: iconset) }

    // The ten images an .icns is assembled from, each drawn at its own size rather than
    // scaled down from one master, so the small ones stay crisp.
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            guard let image = render(size: CGFloat(base * scale)) else {
                throw IconError.renderFailed
            }
            let suffix = scale == 2 ? "@2x" : ""
            try write(image, to: iconset.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
        }
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", "-o", output, iconset.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else {
        throw IconError.iconutilFailed(iconutil.terminationStatus)
    }
    print("Wrote \(output)")
} catch {
    FileHandle.standardError.write(Data("make-icon: \(error)\n".utf8))
    exit(1)
}
