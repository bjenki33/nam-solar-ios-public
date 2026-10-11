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

    func testApprovedHeaderLogoIsBundledSeparateFromTheHomeScreenIcon() throws {
        let image = try XCTUnwrap(UIImage(named: "nam-solar-header-logo", in: .main, compatibleWith: nil))
        let cg = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(cg.width, 1254)
        XCTAssertEqual(cg.height, 1254)
        XCTAssertFalse([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(cg.alphaInfo))
        var rgba = [UInt8](repeating: 0, count: 64 * 64 * 4)
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 64, height: 64, bitsPerComponent: 8,
                bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            return true
        }
        XCTAssertTrue(rendered)
        for (x, y) in [(0, 0), (63, 0), (0, 63), (63, 63)] {
            XCTAssertLessThan(rgba[(y * 64 + x) * 4 + 3], 8, "No white tile behind the header logo")
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "NamSolar-approved-header-logo"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testActualHomeScreenIconIsOpaqueAndUsesTheApprovedNAMSolarLogo() throws {
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
        var bluePixels = 0, warmPixels = 0, greenPixels = 0
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            XCTAssertEqual(rgba[offset + 3], 255, "Home-screen icon must have no transparent corners")
            let r = Double(rgba[offset]), g = Double(rgba[offset + 1]), b = Double(rgba[offset + 2])
            if b > 120 && b > r * 1.3 && b > g * 1.05 { bluePixels += 1 }
            if r > 150 && r > g * 1.1 && g > b * 1.2 { warmPixels += 1 }
            if g > 90 && g > r * 1.15 && g > b * 1.3 { greenPixels += 1 }
        }
        XCTAssertGreaterThan(bluePixels, 200, "Preserve the approved blue solar roofs")
        XCTAssertGreaterThan(warmPixels, 300, "Preserve the sun and NAM SOLAR lettering")
        XCTAssertGreaterThan(greenPixels, 35, "Preserve the green leaf; reject the obsolete blue/gold icon")
        for (x, y) in [(0, 0), (63, 0), (0, 63), (63, 63), (0, 32), (63, 32), (32, 0), (32, 63)] {
            let offset = (y * 64 + x) * 4
            XCTAssertLessThanOrEqual(abs(Int(rgba[offset]) - 247), 3, "Keep safe light padding around the complete logo")
            XCTAssertLessThanOrEqual(abs(Int(rgba[offset + 1]) - 249), 3)
            XCTAssertLessThanOrEqual(abs(Int(rgba[offset + 2]) - 252), 3)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "NamSolar-packaged-home-screen-icon"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
