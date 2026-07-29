import AppKit
import Foundation
import CoreGraphics

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let iconSetURL = rootURL.appendingPathComponent("dist/mac_tool.iconset", isDirectory: true)
let outputURL = rootURL.appendingPathComponent("dist/mac_tool.icns")

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
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let background = NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.24, alpha: 1.0)
    background.setFill()
    NSBezierPath(
        roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
        xRadius: CGFloat(size) * 0.22,
        yRadius: CGFloat(size) * 0.22
    ).fill()

    let inset = CGFloat(size) * 0.18
    let bodyRect = NSRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
    let body = NSBezierPath(roundedRect: bodyRect, xRadius: CGFloat(size) * 0.08, yRadius: CGFloat(size) * 0.08)
    NSColor.white.withAlphaComponent(0.92).setFill()
    body.fill()

    let headerHeight = CGFloat(size) * 0.18
    let headerRect = NSRect(x: inset, y: CGFloat(size) - inset - headerHeight, width: CGFloat(size) - inset * 2, height: headerHeight)
    let header = NSBezierPath(roundedRect: headerRect, xRadius: CGFloat(size) * 0.08, yRadius: CGFloat(size) * 0.08)
    NSColor(calibratedRed: 0.20, green: 0.47, blue: 0.96, alpha: 1.0).setFill()
    header.fill()

    let circleSize = CGFloat(size) * 0.10
    let circleY = CGFloat(size) - inset - headerHeight / 2 - circleSize / 2
    let colors: [NSColor] = [
        NSColor(calibratedRed: 0.99, green: 0.39, blue: 0.36, alpha: 1),
        NSColor(calibratedRed: 1.00, green: 0.77, blue: 0.25, alpha: 1),
        NSColor(calibratedRed: 0.33, green: 0.80, blue: 0.47, alpha: 1)
    ]

    for index in 0..<3 {
        let circleX = inset + CGFloat(index) * (circleSize + CGFloat(size) * 0.04)
        let circle = NSBezierPath(ovalIn: NSRect(x: circleX, y: circleY, width: circleSize, height: circleSize))
        colors[index].setFill()
        circle.fill()
    }

    let lineColor = NSColor(calibratedWhite: 0.78, alpha: 1)
    lineColor.setStroke()
    let lineWidth = max(1, CGFloat(size) * 0.025)
    let linePath = NSBezierPath()
    linePath.lineWidth = lineWidth
    let startY = inset + CGFloat(size) * 0.18
    let lineSpacing = CGFloat(size) * 0.10
    for line in 0..<3 {
        let y = startY + CGFloat(line) * lineSpacing
        linePath.move(to: CGPoint(x: inset + CGFloat(size) * 0.12, y: y))
        linePath.line(to: CGPoint(x: CGFloat(size) - inset - CGFloat(size) * 0.12, y: y))
    }
    linePath.stroke()

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Failed to render icon size \(size)")
    }

    try png.write(to: iconSetURL.appendingPathComponent(name))
}

try Process.run(URL(fileURLWithPath: "/usr/bin/iconutil"), arguments: ["-c", "icns", iconSetURL.path, "-o", outputURL.path]).waitUntilExit()
print(outputURL.path)
