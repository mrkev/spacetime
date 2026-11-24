#if os(iOS)
import Contacts
import ContactsUI
import MapKit
import Photos
import SwiftUI
import UIKit

// The Space map's photo and contact layers: their markers, the photos sheet, and their switches.

/// Thumbnails for the map's photo and contact markers.
final class MapThumbnails {
    /// A contact's thumbnail, by contact ID.
    var contactData: (String) -> Data? = { _ in nil }
    private let cache = NSCache<NSString, UIImage>()

    /// The image for a photo (by asset ID) or a contact (by contact ID), about `side` points square.
    func image(for pin: MapPin, side: CGFloat) async -> UIImage? {
        guard let id = pin.imageId else { return nil }
        let key = "\(id)@\(Int(side))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image: UIImage?
        switch pin.kind {
        case .photos: image = await PhotoImages.image(id, side: side)
        case .contact: image = contactData(id).flatMap(UIImage.init(data:))
        default: image = nil
        }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

/// Images of photos in the library.
enum PhotoImages {
    static func asset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// A photo's image, filling a square `side` points across (or fitting it, if `fill` is false).
    static func image(_ id: String, side: CGFloat, fill: Bool = true) async -> UIImage? {
        guard let asset = asset(id) else { return nil }
        return await image(asset, side: side, fill: fill)
    }

    static func image(_ asset: PHAsset, side: CGFloat, fill: Bool = true) async -> UIImage? {
        let scale = UITraitCollection.current.displayScale
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: side * scale, height: side * scale),
                contentMode: fill ? .aspectFill : .aspectFit, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

/// A photo or contact marker: a rounded photo with a count, or a contact's round picture (or
/// initials). A cluster shows one of them and how many photos or contacts are in it.
final class ThumbnailAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "thumbnail"
    static let clusterReuseIdentifier = "thumbnailCluster"

    /// Runs when it's tapped, with the pins it stands for.
    var onSelect: ([MapPin]) -> Void = { _ in }
    private var pins: [MapPin] = []
    private let imageView = UIImageView()
    private let initials = UILabel()
    private let badge = UILabel()
    private var loading: Task<Void, Never>?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.borderColor = UIColor.white.cgColor
        imageView.layer.borderWidth = 2
        imageView.backgroundColor = .systemGray3
        addSubview(imageView)
        initials.textAlignment = .center
        initials.textColor = .white
        initials.font = .systemFont(ofSize: 14, weight: .semibold)
        addSubview(initials)
        badge.font = .systemFont(ofSize: 11, weight: .bold)
        badge.textColor = .white
        badge.backgroundColor = .systemBlue
        badge.textAlignment = .center
        badge.clipsToBounds = true
        addSubview(badge)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        canShowCallout = false
        collisionMode = .circle
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Shows `pins` (one, or a cluster's), loading the image from `thumbnails`. A cluster's view isn't
    /// clustered itself.
    func configure(_ pins: [MapPin], isCluster: Bool, thumbnails: MapThumbnails?) {
        self.pins = pins
        guard let first = pins.first else { return }
        let isPhoto = first.kind == .photos
        let side: CGFloat = isPhoto ? 44 : 36
        frame = CGRect(x: 0, y: 0, width: side, height: side)
        centerOffset = isPhoto ? CGPoint(x: 0, y: -side / 2) : .zero
        imageView.frame = bounds
        imageView.layer.cornerRadius = isPhoto ? 8 : side / 2
        initials.frame = bounds
        clusteringIdentifier = isCluster ? nil : isPhoto ? "photos" : "contacts"
        displayPriority = .defaultHigh
        zPriority = isPhoto ? .defaultUnselected : .max

        let count = isPhoto ? pins.reduce(0) { $0 + $1.count } : pins.count
        badge.isHidden = count < 2
        badge.text = count > 999 ? "999+" : String(count)
        badge.backgroundColor = isPhoto ? .systemBlue : .systemGray
        badge.sizeToFit()
        let badgeWidth = max(18, badge.bounds.width + 8)
        badge.frame = CGRect(x: side - badgeWidth + 6, y: -6, width: badgeWidth, height: 18)
        badge.layer.cornerRadius = 9

        // Its first pin is its picture (see `SpaceMapView`).
        let shown = first
        initials.text = isPhoto ? nil : Self.initials(shown.name)
        imageView.image = nil
        loading?.cancel()
        loading = Task { [weak self] in
            let image = await thumbnails?.image(for: shown, side: side)
            guard !Task.isCancelled, let self, self.pins.first == shown else { return }
            self.imageView.image = image
            self.initials.isHidden = image != nil
        }
        initials.isHidden = isPhoto
        accessibilityLabel = isPhoto
            ? (count == 1 ? "1 photo" : "\(count) photos")
            : pins.map(\.name).joined(separator: ", ")
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loading?.cancel()
        imageView.image = nil
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        guard selected else { return }
        onSelect(pins)
    }

    private static func initials(_ name: String) -> String {
        let words = name.split(separator: " ")
        return String(words.prefix(2).compactMap(\.first)).uppercased()
    }
}

/// A photo's day, with its year, since photos go back years.
private func photoDate(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .omitted)
}

/// Photos taken around one spot, to open from the map.
struct PhotosRequest: Identifiable {
    let id = UUID()
    var photoIds: [String]
    var coordinate: Coordinate
}

/// A grid of the photos taken around a spot on the map, newest first. Tap one to see it bigger.
struct PhotosSheet: View {
    let request: PhotosRequest
    @Environment(\.dismiss) private var dismiss
    @State private var assets: [PHAsset] = []
    @State private var placeName: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 2)], spacing: 2) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        NavigationLink(value: asset.localIdentifier) {
                            PhotoCell(asset: asset)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(placeName ?? (assets.count == 1 ? "1 Photo" : "\(assets.count) Photos"))
            .navigationSubtitle(dateRange)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                if let asset = assets.first(where: { $0.localIdentifier == id }) { PhotoDetail(asset: asset) }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .task {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(withLocalIdentifiers: request.photoIds, options: options)
            assets = result.objects(at: IndexSet(integersIn: 0..<result.count))
            placeName = await PlaceSearch.describe(request.coordinate)?.name
        }
    }

    private var dateRange: String {
        let dates = assets.compactMap(\.creationDate)
        guard let newest = dates.max(), let oldest = dates.min() else { return "" }
        let newestText = photoDate(newest)
        let oldestText = photoDate(oldest)
        return newestText == oldestText ? newestText : "\(oldestText) – \(newestText)"
    }
}

private struct PhotoCell: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Color(uiColor: .systemGray5)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    Image(systemName: "video.fill").font(.caption).foregroundStyle(.white).padding(4)
                        .shadow(radius: 2)
                }
            }
            .clipped()
            .contentShape(.rect)
            .task(id: asset.localIdentifier) { image = await PhotoImages.image(asset, side: 120) }
            .accessibilityLabel(asset.creationDate.map(photoDate) ?? "Photo")
    }
}

private struct PhotoDetail: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .navigationTitle(asset.creationDate.map(photoDate) ?? "")
        .navigationSubtitle(asset.creationDate.map(Dates.formatTime) ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { image = await PhotoImages.image(asset, side: 1200, fill: false) }
    }
}

/// Contacts' cards, from the map.
enum ContactCards {
    /// Opens a contact's card from Contacts.
    static func open(_ contactId: String) {
        let keys = [CNContactViewController.descriptorForRequiredKeys()]
        guard let contact = try? CNContactStore().unifiedContact(withIdentifier: contactId, keysToFetch: keys) else {
            Presenter.alert(title: "Couldn’t Open Contact")
            return
        }
        let controller = CNContactViewController(for: contact)
        let navigation = UINavigationController(rootViewController: controller)
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close, primaryAction: UIAction { [weak navigation] _ in navigation?.dismiss(animated: true) })
        Presenter.topViewController?.present(navigation, animated: true)
    }

    /// Several contacts at one spot (a household): picks one to open.
    static func choose(_ pins: [MapPin]) async {
        let sorted = pins.sorted { $0.name < $1.name }
        guard let index = await Presenter.actionSheet(
            title: nil, options: sorted.map { Presenter.Option(label: $0.name) }),
            let contactId = sorted[index].imageId else { return }
        open(contactId)
    }
}

/// A switch for one of the map's layers. Turning it on asks for access the first time, and offers
/// Settings if access was refused.
struct MapLayerToggle: View {
    let layer: MapLayer
    @Environment(MapLayers.self) private var layers
    @State private var pending = false

    var body: some View {
        Toggle(isOn: Binding {
            layers.isEnabled(layer) || pending
        } set: { on in
            pending = on
            Task {
                let done = await layers.setEnabled(layer, on)
                pending = false
                if !done { await offerSettings() }
            }
        }) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(layer.title)
                    if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                }
            } icon: {
                Image(systemName: layer == .photos ? "photo.fill" : "person.crop.circle.fill")
                    .foregroundStyle(layer == .photos ? Color.blue : Color.gray)
            }
        }
    }

    private var status: String? {
        guard layer == .contacts, layers.isEnabled(.contacts), layers.addressesToLookUp > 0 else { return nil }
        let count = layers.addressesToLookUp
        return count == 1 ? "Finding 1 address…" : "Finding \(count) addresses…"
    }

    private func offerSettings() async {
        let what = layer == .photos ? "your photos" : "your contacts"
        let choice = await Presenter.confirm(
            title: "Allow Access to \(layer.title)",
            message: "To show \(what) on the map, allow Spacetime to read them in Settings.",
            options: [Presenter.Option(label: "Open Settings")])
        if choice == 0 { Presenter.openSettings() }
    }
}
#endif
