import Foundation
import ImageIO

/// What a photo's file says about how it was taken, worded like Photos' info panel.
nonisolated struct PhotoMetadata: Equatable, Sendable {
    /// Like "Apple iPhone 13".
    var camera: String?
    /// Like "Wide Camera — 26 mm ƒ1.6".
    var lens: String?
    /// Like "HEIF".
    var format: String?
    /// Like ["ISO 500", "26 mm", "0 ev", "ƒ1.6", "1/50 s"], for the ones the file has.
    var exposure: [String] = []

    /// Reads ImageIO's properties for an image (`CGImageSourceCopyPropertiesAtIndex`), and its type.
    init(properties: [String: Any], typeIdentifier: String?) {
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        camera = Self.camera(make: tiff[kCGImagePropertyTIFFMake as String] as? String,
                             model: tiff[kCGImagePropertyTIFFModel as String] as? String)
        format = typeIdentifier.flatMap(Self.format)

        let focal = Self.number(exif[kCGImagePropertyExifFocalLenIn35mmFilm as String])
            ?? Self.number(exif[kCGImagePropertyExifFocalLength as String])
        let aperture = Self.number(exif[kCGImagePropertyExifFNumber as String])
        let iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Any])?.first.flatMap(Self.number)
        let bias = Self.number(exif[kCGImagePropertyExifExposureBiasValue as String])
        let shutter = Self.number(exif[kCGImagePropertyExifExposureTime as String])

        let focalText = focal.map { "\(Self.trim($0)) mm" }
        let apertureText = aperture.map { "ƒ\(Self.trim($0))" }
        let kind = Self.lensKind(exif[kCGImagePropertyExifLensModel as String] as? String)
        let settings = [focalText, apertureText].compactMap { $0 }.joined(separator: " ")
        lens = kind.map { settings.isEmpty ? $0 : "\($0) — \(settings)" } ?? (settings.isEmpty ? nil : settings)

        exposure = [
            iso.map { "ISO \(Int($0.rounded()))" },
            focalText,
            bias.map { "\(Self.trim($0)) ev" },
            apertureText,
            shutter.map(Self.shutter),
        ].compactMap { $0 }
    }

    init(camera: String? = nil, lens: String? = nil, format: String? = nil, exposure: [String] = []) {
        self.camera = camera
        self.lens = lens
        self.format = format
        self.exposure = exposure
    }

    /// The make and model, without the make twice (Apple's model is "iPhone 13", but some cameras'
    /// models start with their make).
    static func camera(make: String?, model: String?) -> String? {
        let make = make?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        let model = model?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        guard let model else { return make }
        guard let make, !model.lowercased().hasPrefix(make.lowercased()) else { return model }
        return "\(make) \(model)"
    }

    /// Which of the phone's cameras, from a lens model like "iPhone 13 back dual wide camera 5.1mm f/1.6".
    static func lensKind(_ model: String?) -> String? {
        guard let model = model?.lowercased(), !model.isEmpty else { return nil }
        if model.contains("front") { return "Front Camera" }
        if model.contains("ultra wide") { return "Ultra Wide Camera" }
        if model.contains("telephoto") { return "Telephoto Camera" }
        if model.contains("wide") { return "Wide Camera" }
        return nil
    }

    /// The file type's short name.
    static func format(_ typeIdentifier: String) -> String? {
        switch typeIdentifier.lowercased() {
        case "public.heic", "public.heif", "public.heics": "HEIF"
        case "public.jpeg": "JPEG"
        case "public.png": "PNG"
        case "com.compuserve.gif": "GIF"
        case "public.tiff": "TIFF"
        case "com.adobe.raw-image", "com.apple.raw-image": "RAW"
        default: nil
        }
    }

    /// An exposure time, as a fraction of a second when it's under one: "1/50 s", "2 s".
    static func shutter(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0 s" }
        if seconds >= 1 { return "\(trim(seconds)) s" }
        return "1/\(Int((1 / seconds).rounded())) s"
    }

    /// Megapixels, like Photos' "12 MP".
    static func megapixels(width: Int, height: Int) -> String {
        let mp = Double(width * height) / 1_000_000
        return mp >= 10 ? "\(Int(mp.rounded())) MP" : "\(trim((mp * 10).rounded() / 10)) MP"
    }

    /// Up to one decimal, without a trailing ".0": 26, 1.6, -0.3.
    private static func trim(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == 0 { return "0" }
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let double as Double: double
        case let int as Int: Double(int)
        default: nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
