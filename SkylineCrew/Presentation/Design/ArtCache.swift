import UIKit
import SpriteKit

/// Alpha bounding boxes from assets/art/manifest.json (pixels of the master files).
/// The Xcode catalog holds proportionally downscaled copies, so boxes are applied in normalized space.
enum ArtManifest {
    struct Entry {
        let size: CGSize
        let bbox: CGRect // x0, y0, width, height in master pixels
    }

    static let entries: [String: Entry] = [
        "BG01": e(941, 1672, 0, 0, 941, 1672),
        "BG02": e(941, 1672, 0, 0, 941, 1672),
        "BG03": e(941, 1672, 0, 0, 941, 1672),
        "OB01": e(941, 1672, 0, 0, 941, 1672),
        "OB02": e(941, 1672, 0, 0, 941, 1672),
        "OB03": e(941, 1672, 0, 0, 941, 1672),
        "F01": e(1774, 887, 99, 134, 1674, 762),
        "F02": e(1774, 887, 92, 122, 1690, 769),
        "F03": e(1774, 887, 95, 106, 1689, 790),
        "F04": e(1770, 889, 90, 125, 1681, 780),
        "F05": e(1774, 887, 136, 101, 1663, 773),
        "F06": e(1774, 887, 147, 116, 1630, 775),
        "P01": e(1536, 1024, 32, 73, 1515, 1001),
        "P02": e(1536, 1024, 44, 288, 1492, 828),
        "P03": e(1983, 793, 20, 112, 1963, 681),
        "C01": e(1024, 1536, 103, 98, 985, 1456),
        "C02": e(1024, 1536, 42, 69, 994, 1469),
        "C03": e(1145, 1374, 119, 23, 1121, 1338),
        "R01": e(1312, 1199, 32, 27, 1277, 1169),
        "R02": e(1278, 1230, 56, 53, 1222, 1179)
    ]

    private static func e(_ w: CGFloat, _ h: CGFloat, _ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> Entry {
        Entry(size: CGSize(width: w, height: h), bbox: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
    }

    static func normalizedBBox(_ id: String) -> CGRect {
        guard let e = entries[id] else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return CGRect(x: e.bbox.minX / e.size.width, y: e.bbox.minY / e.size.height,
                      width: e.bbox.width / e.size.width, height: e.bbox.height / e.size.height)
    }

    static func aspect(_ id: String) -> CGFloat {
        guard let e = entries[id] else { return 1 }
        return e.bbox.width / e.bbox.height
    }
}

final class ArtCache {
    static let shared = ArtCache()
    private var cropped: [String: UIImage] = [:]
    private var textures: [String: SKTexture] = [:]
    private let lock = NSLock()

    /// Full catalog image (backgrounds, onboarding art).
    func full(_ id: String) -> UIImage {
        UIImage(named: id) ?? UIImage()
    }

    /// The useful (alpha bounds) part of an art asset — never redrawn, only cropped.
    func image(_ id: String) -> UIImage {
        lock.lock(); defer { lock.unlock() }
        if let hit = cropped[id] { return hit }
        guard let source = UIImage(named: id), let cg = source.cgImage else { return UIImage() }
        let n = ArtManifest.normalizedBBox(id)
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        let rect = CGRect(x: (n.minX * W).rounded(.down), y: (n.minY * H).rounded(.down),
                          width: (n.width * W).rounded(.up), height: (n.height * H).rounded(.up))
            .intersection(CGRect(x: 0, y: 0, width: W, height: H))
        let result = cg.cropping(to: rect).map { UIImage(cgImage: $0, scale: 1, orientation: .up) } ?? source
        cropped[id] = result
        return result
    }

    func texture(_ id: String) -> SKTexture {
        lock.lock()
        if let hit = textures[id] { lock.unlock(); return hit }
        lock.unlock()
        let tex = SKTexture(image: image(id))
        tex.filteringMode = .linear
        lock.lock(); textures[id] = tex; lock.unlock()
        return tex
    }

    func uiTexture(_ name: String) -> SKTexture {
        lock.lock()
        if let hit = textures["ui." + name] { lock.unlock(); return hit }
        lock.unlock()
        let tex = SKTexture(image: UIImage(named: name) ?? UIImage())
        lock.lock(); textures["ui." + name] = tex; lock.unlock()
        return tex
    }

    func preload(_ ids: [String]) {
        for id in ids { _ = image(id) }
    }
}
