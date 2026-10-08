import XCTest
import UIKit

final class SolarArtworkTests: XCTestCase {
    func testAllDashboardImagesArePackagedAndDecodable() throws {
        for name in ["solar-pv", "solar-grid", "solar-home", "solar-battery", "solar-inverter", "solar-sun"] {
            let image = try XCTUnwrap(UIImage(named: name, in: .main, compatibleWith: nil), "Missing artwork: \(name)")
            XCTAssertGreaterThan(image.size.width, 20)
            XCTAssertGreaterThan(image.size.height, 20)
            XCTAssertNotNil(image.cgImage, "Cannot decode artwork: \(name)")
        }
    }

    func testNaturalSunKeepsItsTransparentBackground() throws {
        let image = try XCTUnwrap(UIImage(named: "solar-sun", in: .main, compatibleWith: nil))
        let cg = try XCTUnwrap(image.cgImage)
        XCTAssertFalse([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(cg.alphaInfo))
    }

    func testActualHomeScreenIconIsBundledOpaqueAndUsesTheUserBlueGoldArtwork() throws {
        let icons = try XCTUnwrap(Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
        let primary = try XCTUnwrap(icons["CFBundlePrimaryIcon"] as? [String: Any])
        let files = try XCTUnwrap(primary["CFBundleIconFiles"] as? [String])
        XCTAssertFalse(files.isEmpty)
        let image = try XCTUnwrap(UIImage(named: try XCTUnwrap(files.last), in: .main, compatibleWith: nil))
        let cg = try XCTUnwrap(image.cgImage)
        XCTAssertGreaterThanOrEqual(cg.width, 120)
        var rgba = [UInt8](repeating: 0, count: 64 * 64 * 4)
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 64, height: 64, bitsPerComponent: 8,
                bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            return true
        }
        XCTAssertTrue(rendered)
        var bluePixels = 0, warmPixels = 0
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            XCTAssertEqual(rgba[offset + 3], 255, "Home-screen icon must have no transparent corners")
            let r = Double(rgba[offset]), g = Double(rgba[offset + 1]), b = Double(rgba[offset + 2])
            if b > 120 && b > r * 1.3 && b > g * 1.05 { bluePixels += 1 }
            if r > 150 && r > g * 1.1 && g > b * 1.2 { warmPixels += 1 }
        }
        XCTAssertGreaterThan(bluePixels, 600, "Use the user's blue icon, not either rejected generated icon")
        XCTAssertGreaterThan(warmPixels, 100, "User's gold sun must survive downscaling")
        for (x, y) in [(0, 0), (63, 0), (0, 63), (63, 63), (0, 32), (63, 32), (32, 0), (32, 63)] {
            let offset = (y * 64 + x) * 4
            XCTAssertGreaterThan(Double(rgba[offset + 2]), Double(rgba[offset]) * 1.4,
                                 "Edges must be full-bleed blue, not the original blurred backdrop/frame")
            XCTAssertGreaterThan(rgba[offset + 2], 100)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "NamSolar-packaged-home-screen-icon"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
