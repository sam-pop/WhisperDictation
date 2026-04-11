#!/usr/bin/env python3
"""Generate an app icon for WhisperDictation using AppKit/CoreGraphics."""
import subprocess
import sys
import os
import tempfile

SWIFT_ICON_RENDERER = '''
import AppKit

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

func renderIcon(size: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size)

    // Background: dark rounded rect
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let cornerRadius = s * 0.22
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Dark gradient background
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let bgColors = [
        CGColor(red: 0.08, green: 0.08, blue: 0.18, alpha: 1.0),
        CGColor(red: 0.06, green: 0.10, blue: 0.22, alpha: 1.0),
    ]
    let bgGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    ctx.restoreGState()

    // Accent color: cyan-blue gradient
    let accentColors = [
        CGColor(red: 0.31, green: 0.67, blue: 1.0, alpha: 1.0),  // #4facfe
        CGColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 1.0),   // #00f2fe
    ]
    let accentGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: accentColors as CFArray, locations: [0.0, 1.0])!

    func fillWithAccent(_ path: CGPath) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let bounds = path.boundingBox
        ctx.drawLinearGradient(accentGradient, start: CGPoint(x: bounds.midX, y: bounds.maxY), end: CGPoint(x: bounds.midX, y: bounds.minY), options: [])
        ctx.restoreGState()
    }

    // Waveform bars - left side
    let barWidth = s * 0.047
    let barRadius = barWidth / 2
    let leftBars: [(x: CGFloat, height: CGFloat)] = [
        (0.155, 0.14),
        (0.22, 0.30),
        (0.285, 0.20),
    ]
    for bar in leftBars {
        let x = s * bar.x - barWidth / 2
        let h = s * bar.height
        let y = (s - h) / 2
        let rect = CGRect(x: x, y: y, width: barWidth, height: h)
        let path = CGPath(roundedRect: rect, cornerWidth: barRadius, cornerHeight: barRadius, transform: nil)
        ctx.setAlpha(0.7)
        fillWithAccent(path)
        ctx.setAlpha(1.0)
    }

    // Microphone body (rounded rect / capsule)
    let micWidth = s * 0.14
    let micHeight = s * 0.31
    let micX = (s - micWidth) / 2
    let micY = s * 0.42
    let micRect = CGRect(x: micX, y: micY, width: micWidth, height: micHeight)
    let micPath = CGPath(roundedRect: micRect, cornerWidth: micWidth / 2, cornerHeight: micWidth / 2, transform: nil)
    fillWithAccent(micPath)

    // Mic stand arc
    let arcCenter = CGPoint(x: s / 2, y: s * 0.42)
    let arcRadius = s * 0.12
    ctx.saveGState()
    let arcPath = CGMutablePath()
    arcPath.addArc(center: arcCenter, radius: arcRadius, startAngle: .pi * 0.05, endAngle: .pi * 0.95, clockwise: false)
    ctx.addPath(arcPath)
    ctx.setLineWidth(s * 0.038)
    ctx.setLineCap(.round)
    // Stroke with accent color (use the lighter cyan)
    ctx.setStrokeColor(CGColor(red: 0.15, green: 0.82, blue: 1.0, alpha: 1.0))
    ctx.strokePath()
    ctx.restoreGState()

    // Mic stand (vertical line)
    let standWidth = s * 0.038
    let standX = (s - standWidth) / 2
    let standY = s * 0.22
    let standHeight = s * 0.10
    let standRect = CGRect(x: standX, y: standY, width: standWidth, height: standHeight)
    let standPath = CGPath(roundedRect: standRect, cornerWidth: standWidth / 2, cornerHeight: standWidth / 2, transform: nil)
    fillWithAccent(standPath)

    // Mic base (horizontal)
    let baseWidth = s * 0.15
    let baseHeight = s * 0.038
    let baseX = (s - baseWidth) / 2
    let baseY = s * 0.20
    let baseRect = CGRect(x: baseX, y: baseY, width: baseWidth, height: baseHeight)
    let basePath = CGPath(roundedRect: baseRect, cornerWidth: baseHeight / 2, cornerHeight: baseHeight / 2, transform: nil)
    fillWithAccent(basePath)

    // Waveform bars - right side
    let rightBars: [(x: CGFloat, height: CGFloat)] = [
        (0.715, 0.20),
        (0.78, 0.30),
        (0.845, 0.14),
    ]
    for bar in rightBars {
        let x = s * bar.x - barWidth / 2
        let h = s * bar.height
        let y = (s - h) / 2
        let rect = CGRect(x: x, y: y, width: barWidth, height: h)
        let path = CGPath(roundedRect: rect, cornerWidth: barRadius, cornerHeight: barRadius, transform: nil)
        ctx.setAlpha(0.7)
        fillWithAccent(path)
        ctx.setAlpha(1.0)
    }

    img.unlockFocus()
    return img
}

let outputDir = CommandLine.arguments[1]

// Create iconset
let iconsetPath = outputDir + "/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for (size, name) in sizes {
    let image = renderIcon(size: size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()

    let pngData = rep.representation(using: .png, properties: [:])!
    let filePath = iconsetPath + "/" + name
    try! pngData.write(to: URL(fileURLWithPath: filePath))
}

// Convert to icns
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath, "-o", outputDir + "/AppIcon.icns"]
try! process.run()
process.waitUntilExit()

// Cleanup iconset
try? FileManager.default.removeItem(atPath: iconsetPath)
print("[Icon] Generated \\(outputDir)/AppIcon.icns")
'''

def generate_icon(resources_dir):
    """Render the icon using a Swift script that uses AppKit/CoreGraphics."""
    os.makedirs(resources_dir, exist_ok=True)

    # Write Swift script to temp file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.swift', delete=False) as f:
        f.write(SWIFT_ICON_RENDERER)
        swift_path = f.name

    try:
        # Compile and run the Swift script
        binary_path = swift_path.replace('.swift', '')
        subprocess.run([
            'swiftc', swift_path,
            '-framework', 'AppKit',
            '-o', binary_path
        ], check=True, capture_output=True)

        subprocess.run([binary_path, resources_dir], check=True)
    finally:
        os.unlink(swift_path)
        if os.path.exists(binary_path):
            os.unlink(binary_path)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: generate-icon.py <Resources_dir>")
        sys.exit(1)
    generate_icon(sys.argv[1])
