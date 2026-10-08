// Renders one SVG to square PNGs with AppKit, so icon generation needs no third-party tools.
// Usage: swift render_svg.swift <source.svg> <output.png>:<pixels> ...
import AppKit

let arguments = CommandLine.arguments.dropFirst()
guard let source = arguments.first, let image = NSImage(contentsOf: URL(fileURLWithPath: source)) else {
    FileHandle.standardError.write(Data("Cannot load the SVG source\n".utf8))
    exit(1)
}
for target in arguments.dropFirst() {
    let parts = target.split(separator: ":", maxSplits: 1)
    guard parts.count == 2, let pixels = Int(parts[1]), pixels > 0,
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
    else {
        FileHandle.standardError.write(Data("Invalid target \(target)\n".utf8))
        exit(1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
    try png.write(to: URL(fileURLWithPath: String(parts[0])))
}
