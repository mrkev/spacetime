import CryptoKit
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// A place's icon: `symbol:<SF Symbol name>` for one picked for it, or `image:<path>` for a point of
/// interest's own icon from Apple Maps, saved under the app's Documents directory.
enum PlaceIcon {
    /// Icons to pick from, by group.
    static let groups: [(title: String, symbols: [String])] = [
        ("Food & Drink", ["fork.knife", "cup.and.saucer.fill", "mug.fill", "wineglass.fill", "birthday.cake.fill",
                          "takeoutbag.and.cup.and.straw.fill", "carrot.fill", "fish.fill", "popcorn.fill",
                          "frying.pan.fill"]),
        ("Shopping", ["cart.fill", "bag.fill", "basket.fill", "storefront.fill", "tshirt.fill", "book.fill",
                      "gift.fill"]),
        ("Health & Fitness", ["dumbbell.fill", "figure.run", "figure.yoga", "figure.pool.swim", "sportscourt.fill",
                              "cross.case.fill", "pills.fill", "stethoscope"]),
        ("Home & Work", ["house.fill", "building.2.fill", "briefcase.fill", "laptopcomputer", "graduationcap.fill",
                         "person.2.fill", "pawprint.fill", "wrench.and.screwdriver.fill", "scissors"]),
        ("Getting Around", ["airplane", "tram.fill", "bus.fill", "car.fill", "fuelpump.fill", "bicycle",
                            "parkingsign", "bed.double.fill"]),
        ("Outdoors", ["tree.fill", "leaf.fill", "mountain.2.fill", "figure.hiking", "tent.fill",
                      "beach.umbrella.fill", "sun.max.fill"]),
        ("Culture & Fun", ["theatermasks.fill", "film.fill", "music.note", "paintpalette.fill",
                           "building.columns.fill", "ticket.fill", "gamecontroller.fill"]),
        ("Other", ["star.fill", "heart.fill", "flag.fill", "bookmark.fill", "sparkles", "mappin"]),
    ]

    static func symbol(_ name: String) -> String { "symbol:\(name)" }

    /// The icon as an image for a map marker's balloon (MapKit tints it white), or nil for a plain pin.
    static func image(_ icon: String?) -> PlatformImage? {
        guard let icon else { return nil }
        if icon.hasPrefix("symbol:") {
            let name = String(icon.dropFirst("symbol:".count))
            #if os(iOS)
            return UIImage(systemName: name)
            #else
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)
            #endif
        }
        if icon.hasPrefix("image:") {
            let relative = String(icon.dropFirst("image:".count))
            let url = URL.documentsDirectory.appending(path: relative)
            #if os(iOS)
            return UIImage(contentsOfFile: url.path)?.withRenderingMode(.alwaysTemplate)
            #else
            guard let image = NSImage(contentsOfFile: url.path) else { return nil }
            // NSImage doesn't read the scale from the file name, so size it in points ourselves.
            if let match = relative.firstMatch(of: /@(\d)x\.png$/), let scale = Double(match.1), scale > 1,
               let rep = image.representations.first {
                image.size = NSSize(width: Double(rep.pixelsWide) / scale, height: Double(rep.pixelsHigh) / scale)
            }
            image.isTemplate = true
            return image
            #endif
        }
        return nil
    }

    /// Saves a point of interest's icon (MapKit's glyph for it) under Documents/place-icons, named by
    /// its contents so each icon is saved once, and returns it as an `image:` icon.
    static func save(_ image: PlatformImage) -> String? {
        #if os(iOS)
        guard let png = image.pngData() else { return nil }
        let scale = Int(image.scale)
        #else
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let scale = max(1, Int((Double(cg.width) / max(1, image.size.width)).rounded()))
        #endif
        let digest = SHA256.hash(data: png).prefix(8).map { String(format: "%02x", $0) }.joined()
        // The scale suffix says how many pixels make a point.
        let relative = "place-icons/\(digest)@\(scale)x.png"
        let url = URL.documentsDirectory.appending(path: relative)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            guard (try? png.write(to: url, options: .atomic)) != nil else { return nil }
        }
        return "image:\(relative)"
    }
}

/// The icon itself, tinted `color`. Without one, a pin.
struct PlaceGlyph: View {
    var icon: String?
    var size: CGFloat
    var color: Color

    var body: some View {
        Group {
            if let icon, icon.hasPrefix("image:"), let image = PlaceIcon.image(icon) {
                Image(platformImage: image).resizable().scaledToFit()
            } else {
                let symbol = icon?.hasPrefix("symbol:") == true ? String(icon!.dropFirst(7)) : "mappin"
                Image(systemName: symbol).resizable().scaledToFit()
            }
        }
        .foregroundStyle(color)
        .frame(width: size, height: size)
    }
}

/// The icon in a circle of the place's color, like its pin.
struct PlaceBadge: View {
    var icon: String?
    var color: String
    var size: CGFloat = 32

    var body: some View {
        Circle()
            .fill(Color(hex: color))
            .frame(width: size, height: size)
            .overlay { PlaceGlyph(icon: icon, size: size * 0.55, color: .white) }
    }
}
