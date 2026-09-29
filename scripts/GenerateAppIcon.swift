import AppKit
import Foundation

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

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
    (1024, "icon_512x512@2x.png")
]

func renderIcon(pixelSize: Int, fullBleed: Bool = false) -> Data {
    let size = CGFloat(pixelSize)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("No se pudo crear el bitmap")
    }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("No se pudo crear el contexto")
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let inset = fullBleed ? 0 : size * 0.06
    let drawRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let corner = fullBleed ? 0 : drawRect.width * 0.223
    let path = NSBezierPath(roundedRect: drawRect, xRadius: corner, yRadius: corner)
    NSColor(calibratedRed: 0.18, green: 0.45, blue: 0.91, alpha: 1).setFill()
    path.fill()

    let config = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "globe.desk", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let symbolSize = symbol.size
        let origin = NSPoint(
            x: (size - symbolSize.width) / 2,
            y: (size - symbolSize.height) / 2 - size * 0.015
        )
        symbol.draw(
            in: NSRect(origin: origin, size: symbolSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("No se pudo exportar PNG")
    }
    return png
}

try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for (pixelSize, filename) in sizes {
    let png = renderIcon(pixelSize: pixelSize)
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent(filename)
    try png.write(to: url)
    print("Wrote \(filename)")
}

// iOS aplica su propia máscara: icono opaco a sangre completa.
let iosURL = URL(fileURLWithPath: outputDir).appendingPathComponent("icon_ios_1024.png")
try renderIcon(pixelSize: 1024, fullBleed: true).write(to: iosURL)
print("Wrote icon_ios_1024.png")
