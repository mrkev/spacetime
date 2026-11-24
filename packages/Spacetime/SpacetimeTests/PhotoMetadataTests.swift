import Foundation
import ImageIO
import Testing
@testable import Spacetime

@MainActor
struct PhotoMetadataTests {
    /// What ImageIO reads from a photo taken with an iPhone 13's main camera.
    private let iPhone: [String: Any] = [
        kCGImagePropertyTIFFDictionary as String: [
            kCGImagePropertyTIFFMake as String: "Apple",
            kCGImagePropertyTIFFModel as String: "iPhone 13",
        ],
        kCGImagePropertyExifDictionary as String: [
            kCGImagePropertyExifLensModel as String: "iPhone 13 back dual wide camera 5.1mm f/1.6",
            kCGImagePropertyExifFocalLenIn35mmFilm as String: 26,
            kCGImagePropertyExifFocalLength as String: 5.1,
            kCGImagePropertyExifFNumber as String: 1.6,
            kCGImagePropertyExifExposureTime as String: 0.02,
            kCGImagePropertyExifISOSpeedRatings as String: [500],
            kCGImagePropertyExifExposureBiasValue as String: 0,
        ],
    ]

    @Test func describesAPhotoLikePhotos() {
        let metadata = PhotoMetadata(properties: iPhone, typeIdentifier: "public.heic")
        #expect(metadata.camera == "Apple iPhone 13")
        #expect(metadata.lens == "Wide Camera — 26 mm ƒ1.6")
        #expect(metadata.format == "HEIF")
        #expect(metadata.exposure == ["ISO 500", "26 mm", "0 ev", "ƒ1.6", "1/50 s"])
    }

    @Test func leavesOutWhatTheFileDoesntHave() {
        let metadata = PhotoMetadata(properties: [:], typeIdentifier: "public.png")
        #expect(metadata.camera == nil && metadata.lens == nil)
        #expect(metadata.format == "PNG")
        #expect(metadata.exposure.isEmpty)
    }

    @Test func namesTheCameraByItsMakeOnce() {
        #expect(PhotoMetadata.camera(make: "Apple", model: "iPhone 13") == "Apple iPhone 13")
        #expect(PhotoMetadata.camera(make: "Canon", model: "Canon EOS R6") == "Canon EOS R6")
        #expect(PhotoMetadata.camera(make: "FUJIFILM", model: nil) == "FUJIFILM")
        #expect(PhotoMetadata.camera(make: " ", model: " ") == nil)
    }

    @Test func tellsThePhonesCamerasApart() {
        #expect(PhotoMetadata.lensKind("iPhone 15 Pro back triple camera 2.22mm f/2.2 ultra wide") == "Ultra Wide Camera")
        #expect(PhotoMetadata.lensKind("iPhone 15 Pro back triple camera 6.86mm f/1.78") == nil)
        #expect(PhotoMetadata.lensKind("iPhone 15 Pro back telephoto camera 15.66mm f/2.8") == "Telephoto Camera")
        #expect(PhotoMetadata.lensKind("iPhone 13 front TrueDepth camera 2.71mm f/2.2") == "Front Camera")
        #expect(PhotoMetadata.lensKind(nil) == nil)
    }

    @Test func writesShutterSpeedsAsFractions() {
        #expect(PhotoMetadata.shutter(0.02) == "1/50 s")
        #expect(PhotoMetadata.shutter(1.0 / 120) == "1/120 s")
        #expect(PhotoMetadata.shutter(2) == "2 s")
        #expect(PhotoMetadata.shutter(1.5) == "1.5 s")
    }

    @Test func roundsMegapixelsLikePhotos() {
        #expect(PhotoMetadata.megapixels(width: 3024, height: 4032) == "12 MP")
        #expect(PhotoMetadata.megapixels(width: 1200, height: 800) == "1 MP")
        #expect(PhotoMetadata.megapixels(width: 900, height: 1200) == "1.1 MP")
        #expect(PhotoMetadata.megapixels(width: 8064, height: 6048) == "49 MP")
    }

    @Test func writesNegativeExposureBias() {
        var properties = iPhone
        var exif = properties[kCGImagePropertyExifDictionary as String] as! [String: Any]
        exif[kCGImagePropertyExifExposureBiasValue as String] = -0.33
        properties[kCGImagePropertyExifDictionary as String] = exif
        #expect(PhotoMetadata(properties: properties, typeIdentifier: nil).exposure.contains("-0.3 ev"))
    }
}
