import AppKit

let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("assets", isDirectory: true)

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

let icons: [(String, NSColor)] = [
    ("tray_icon.png", NSColor(calibratedRed: 0.145, green: 0.388, blue: 0.922, alpha: 1)),
    ("tray_icon_up.png", NSColor(calibratedRed: 0.12, green: 0.67, blue: 0.39, alpha: 1)),
    ("tray_icon_down.png", NSColor(calibratedRed: 0.91, green: 0.28, blue: 0.27, alpha: 1)),
    ("tray_icon_paused.png", NSColor(calibratedWhite: 0.55, alpha: 1)),
]

func makePNG(dimension: CGFloat, drawing: () -> Void) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
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
    ) else {
        fatalError("Could not allocate a \(dimension)-pixel bitmap")
    }
    bitmap.size = NSSize(width: dimension, height: dimension)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    drawing()
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode a \(dimension)-pixel image")
    }
    return png
}

func renderPNG(
    dimension: CGFloat,
    destination: URL,
    drawing: () -> Void
) throws {
    try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let png = try makePNG(dimension: dimension, drawing: drawing)
    try png.write(to: destination)
}

for (filename, color) in icons {
    try renderPNG(
        dimension: 64,
        destination: outputDirectory.appendingPathComponent(filename)
    ) {
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()

        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: 7, y: 32))
        path.line(to: NSPoint(x: 18, y: 32))
        path.line(to: NSPoint(x: 24, y: 46))
        path.line(to: NSPoint(x: 33, y: 16))
        path.line(to: NSPoint(x: 40, y: 38))
        path.line(to: NSPoint(x: 46, y: 32))
        path.line(to: NSPoint(x: 57, y: 32))
        path.stroke()

        let ring = NSBezierPath(
            ovalIn: NSRect(x: 2.5, y: 2.5, width: 59, height: 59)
        )
        ring.lineWidth = 5
        ring.stroke()
    }
}

let projectDirectory = outputDirectory.deletingLastPathComponent()
let appIconDirectory = projectDirectory
    .appendingPathComponent(
        "macos/Runner/Assets.xcassets/AppIcon.appiconset",
        isDirectory: true
    )

let appIconSizes: [(String, CGFloat)] = [
    ("app_icon_16.png", 16),
    ("app_icon_32.png", 32),
    ("app_icon_64.png", 64),
    ("app_icon_128.png", 128),
    ("app_icon_256.png", 256),
    ("app_icon_512.png", 512),
    ("app_icon_1024.png", 1024),
]

enum AppIconStyle {
    case transparentTile
    case fullBleed
    case foreground
    case monochrome
}

func drawAppIcon(dimension: CGFloat, style: AppIconStyle) {
    let scale = dimension / 1024
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: dimension, height: dimension).fill()

    switch style {
    case .transparentTile, .fullBleed:
        let tileRect = style == .fullBleed
            ? NSRect(x: 0, y: 0, width: dimension, height: dimension)
            : NSRect(
            x: 70 * scale,
            y: 70 * scale,
            width: 884 * scale,
            height: 884 * scale
        )
        let tile = NSBezierPath(
            roundedRect: tileRect,
            xRadius: style == .fullBleed ? 0 : 205 * scale,
            yRadius: style == .fullBleed ? 0 : 205 * scale
        )
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.114, green: 0.306, blue: 0.847, alpha: 1),
            NSColor(calibratedRed: 0.231, green: 0.510, blue: 0.965, alpha: 1),
        ])
        if let gradient {
            gradient.draw(in: tile, angle: 42)
        } else {
            NSColor(calibratedRed: 0.114, green: 0.306, blue: 0.847, alpha: 1)
                .setFill()
            tile.fill()
        }
    case .foreground, .monochrome:
        break
    }

    switch style {
    case .monochrome:
        NSColor.black.setStroke()
    case .foreground:
        NSColor.white.withAlphaComponent(0.34).setStroke()
    case .transparentTile, .fullBleed:
        NSColor.white.withAlphaComponent(0.18).setStroke()
    }
    let ring = NSBezierPath(
        ovalIn: NSRect(
            x: 225 * scale,
            y: 225 * scale,
            width: 574 * scale,
            height: 574 * scale
        )
    )
    ring.lineWidth = 42 * scale
    ring.stroke()

    switch style {
    case .monochrome:
        NSColor.black.setStroke()
    case .transparentTile, .fullBleed, .foreground:
        NSColor.white.setStroke()
    }
    let pulse = NSBezierPath()
    pulse.lineWidth = 58 * scale
    pulse.lineCapStyle = .round
    pulse.lineJoinStyle = .round
    pulse.move(to: NSPoint(x: 214 * scale, y: 508 * scale))
    pulse.line(to: NSPoint(x: 340 * scale, y: 508 * scale))
    pulse.line(to: NSPoint(x: 416 * scale, y: 680 * scale))
    pulse.line(to: NSPoint(x: 529 * scale, y: 330 * scale))
    pulse.line(to: NSPoint(x: 610 * scale, y: 578 * scale))
    pulse.line(to: NSPoint(x: 680 * scale, y: 508 * scale))
    pulse.line(to: NSPoint(x: 810 * scale, y: 508 * scale))
    pulse.stroke()
}

func renderAppIcon(
    dimension: CGFloat,
    destination: URL,
    style: AppIconStyle
) throws {
    try renderPNG(dimension: dimension, destination: destination) {
        drawAppIcon(dimension: dimension, style: style)
    }
}

for (filename, dimension) in appIconSizes {
    try renderAppIcon(
        dimension: dimension,
        destination: appIconDirectory.appendingPathComponent(filename),
        style: .transparentTile
    )
}

try renderAppIcon(
    dimension: 512,
    destination: outputDirectory.appendingPathComponent("app_icon.png"),
    style: .transparentTile
)

let iosIconDirectory = projectDirectory.appendingPathComponent(
    "ios/Runner/Assets.xcassets/AppIcon.appiconset",
    isDirectory: true
)
let iosIconSizes: [(String, CGFloat)] = [
    ("Icon-App-20x20@1x.png", 20),
    ("Icon-App-20x20@2x.png", 40),
    ("Icon-App-20x20@3x.png", 60),
    ("Icon-App-29x29@1x.png", 29),
    ("Icon-App-29x29@2x.png", 58),
    ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@1x.png", 40),
    ("Icon-App-40x40@2x.png", 80),
    ("Icon-App-40x40@3x.png", 120),
    ("Icon-App-60x60@2x.png", 120),
    ("Icon-App-60x60@3x.png", 180),
    ("Icon-App-76x76@1x.png", 76),
    ("Icon-App-76x76@2x.png", 152),
    ("Icon-App-83.5x83.5@2x.png", 167),
    ("Icon-App-1024x1024@1x.png", 1024),
]
for (filename, dimension) in iosIconSizes {
    try renderAppIcon(
        dimension: dimension,
        destination: iosIconDirectory.appendingPathComponent(filename),
        style: .fullBleed
    )
}

let androidIconSizes: [(String, CGFloat)] = [
    ("mipmap-mdpi", 48),
    ("mipmap-hdpi", 72),
    ("mipmap-xhdpi", 96),
    ("mipmap-xxhdpi", 144),
    ("mipmap-xxxhdpi", 192),
]
for (directory, dimension) in androidIconSizes {
    try renderAppIcon(
        dimension: dimension,
        destination: projectDirectory
            .appendingPathComponent("android/app/src/main/res/\(directory)")
            .appendingPathComponent("ic_launcher.png"),
        style: .transparentTile
    )
}
let androidDrawableDirectory = projectDirectory.appendingPathComponent(
    "android/app/src/main/res/drawable-nodpi",
    isDirectory: true
)
try renderAppIcon(
    dimension: 432,
    destination: androidDrawableDirectory.appendingPathComponent("app_icon_foreground.png"),
    style: .foreground
)
try renderAppIcon(
    dimension: 432,
    destination: androidDrawableDirectory.appendingPathComponent("app_icon_monochrome.png"),
    style: .monochrome
)

let webIconDirectory = projectDirectory.appendingPathComponent("web/icons", isDirectory: true)
for dimension in [192, 512] {
    try renderAppIcon(
        dimension: CGFloat(dimension),
        destination: webIconDirectory.appendingPathComponent("Icon-\(dimension).png"),
        style: .transparentTile
    )
    try renderAppIcon(
        dimension: CGFloat(dimension),
        destination: webIconDirectory.appendingPathComponent("Icon-maskable-\(dimension).png"),
        style: .fullBleed
    )
}
try renderAppIcon(
    dimension: 32,
    destination: projectDirectory.appendingPathComponent("web/favicon.png"),
    style: .transparentTile
)

extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }
}

func makeWindowsIcon() throws -> Data {
    let dimensions = [16, 24, 32, 48, 64, 128, 256]
    let images = try dimensions.map { dimension in
        try makePNG(dimension: CGFloat(dimension)) {
            drawAppIcon(dimension: CGFloat(dimension), style: .transparentTile)
        }
    }
    var icon = Data()
    icon.appendLittleEndian(UInt16(0))
    icon.appendLittleEndian(UInt16(1))
    icon.appendLittleEndian(UInt16(images.count))
    var imageOffset = UInt32(6 + images.count * 16)
    for (index, image) in images.enumerated() {
        let dimension = dimensions[index]
        icon.append(dimension == 256 ? 0 : UInt8(dimension))
        icon.append(dimension == 256 ? 0 : UInt8(dimension))
        icon.append(0)
        icon.append(0)
        icon.appendLittleEndian(UInt16(1))
        icon.appendLittleEndian(UInt16(32))
        icon.appendLittleEndian(UInt32(image.count))
        icon.appendLittleEndian(imageOffset)
        imageOffset += UInt32(image.count)
    }
    for image in images {
        icon.append(image)
    }
    return icon
}

let windowsIcon = projectDirectory.appendingPathComponent(
    "windows/runner/resources/app_icon.ico"
)
try makeWindowsIcon().write(to: windowsIcon)
