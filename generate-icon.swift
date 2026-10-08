import AppKit
import ImageIO
import UniformTypeIdentifiers

// User-supplied artwork is the sole production app icon source.
// RGB-only output guarantees an opaque 1024px icon for the iOS asset compiler.
let size = 1024
let sourceURL = URL(fileURLWithPath: "nam-solar-app-icon.png")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Missing or invalid production app icon")
}
guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Cannot allocate opaque app icon bitmap")
}
context.interpolationQuality = .high
let sourceSide = min(image.width, image.height)
let crop = CGRect(x: (image.width - sourceSide) / 2,
                  y: (image.height - sourceSide) / 2, width: sourceSide, height: sourceSide)
// Crop only the outer backdrop to square; never stretch or redraw the user's artwork.
guard let cropped = image.cropping(to: crop) else { fatalError("Cannot crop source icon") }
context.draw(cropped, in: CGRect(x: 0, y: 0, width: size, height: size))
guard let bitmap = context.makeImage() else { fatalError("Cannot create production icon") }
let file = URL(fileURLWithPath: "Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
guard let destination = CGImageDestinationCreateWithURL(file.appendingPathComponent("AppIcon.png") as CFURL,
    UTType.png.identifier as CFString, 1, nil) else { fatalError("Cannot create app icon PNG") }
CGImageDestinationAddImage(destination, bitmap, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save app icon PNG") }
let contents = """
{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
"""
try Data(contents.utf8).write(to: file.appendingPathComponent("Contents.json"))

// Compile dashboard artwork into the asset catalog, not loose bundle files.
for name in ["solar-pv", "solar-grid", "solar-home", "solar-battery", "solar-inverter", "solar-sun"] {
    let folder = URL(fileURLWithPath: "Assets.xcassets/\(name).imageset")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(contentsOf: URL(fileURLWithPath: "\(name).png")).write(to: folder.appendingPathComponent("\(name).png"))
    let metadata = """
    {"images":[{"filename":"\(name).png","idiom":"universal"}],"info":{"author":"xcode","version":1},"properties":{"preserves-vector-representation":false,"template-rendering-intent":"original"}}
    """
    try Data(metadata.utf8).write(to: folder.appendingPathComponent("Contents.json"))
}
