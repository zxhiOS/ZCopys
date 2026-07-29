import AppKit
import Foundation

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let sourceURL = rootURL.appendingPathComponent("Assets/AppIcon.png")
let iconSetURL = rootURL.appendingPathComponent("dist/Zcopys.iconset", isDirectory: true)
let outputURL = rootURL.appendingPathComponent("dist/Zcopys.icns")

guard fileManager.fileExists(atPath: sourceURL.path) else {
    fputs("Missing Assets/AppIcon.png — run icon prep first.\n", stderr)
    exit(1)
}

guard let source = NSImage(contentsOf: sourceURL) else {
    fputs("Failed to load \(sourceURL.path)\n", stderr)
    exit(1)
}

try? fileManager.removeItem(at: iconSetURL)
try? fileManager.removeItem(at: outputURL)
try fileManager.createDirectory(at: iconSetURL, withIntermediateDirectories: true)

let sizesAndNames: [(Int, String)] = [
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

for (size, name) in sizesAndNames {
    let canvas = NSImage(size: NSSize(width: size, height: size))
    canvas.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: NSRect(origin: .zero, size: source.size),
        operation: .copy,
        fraction: 1.0
    )
    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Failed to render icon size \(size)")
    }
    try png.write(to: iconSetURL.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconSetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fputs("iconutil failed with status \(process.terminationStatus)\n", stderr)
    exit(1)
}
print(outputURL.path)
