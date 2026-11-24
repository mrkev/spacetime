#if os(iOS)
import ImageIO
import MapKit
import Photos
import SwiftUI
import UIKit

/// The photos at a spot, one at a time: swipe sideways for the others, and up for where and how each
/// was taken, like Photos.
struct PhotoViewer: View {
    let assets: [PHAsset]
    /// The spot's name, for the title.
    let placeName: String?
    @State private var currentId: String?
    /// Whether the details are showing. It carries over from photo to photo, as in Photos.
    @State private var showsInfo = false
    /// Full-size images of the photo showing and the ones on either side, decoded ahead of time so
    /// swiping to one shows it right away.
    @State private var images: [String: UIImage] = [:]
    /// Whether the photo showing is zoomed in, which holds the pager still so a drag pans it.
    @State private var zoomed = false

    init(assets: [PHAsset], startId: String, placeName: String?) {
        self.assets = assets
        self.placeName = placeName
        _currentId = State(initialValue: startId)
    }

    var body: some View {
        let current = assets.first { $0.localIdentifier == currentId }
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        PhotoPage(asset: asset, size: geometry.size, image: images[asset.localIdentifier],
                                  showsInfo: $showsInfo, zoomed: $zoomed,
                                  isCurrent: asset.localIdentifier == currentId)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentId)
            .scrollIndicators(.hidden)
            .scrollDisabled(zoomed)
            .task(id: currentId) { await preload(side: max(geometry.size.width, geometry.size.height)) }
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .navigationTitle(placeName ?? current?.creationDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "")
        .navigationSubtitle(current?.creationDate.map(Self.subtitle) ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    /// Loads and decodes the current photo, then the next and the previous, and lets go of the rest.
    private func preload(side: CGFloat) async {
        guard let index = assets.firstIndex(where: { $0.localIdentifier == currentId }) else { return }
        let nearby = [index, index + 1, index - 1].filter(assets.indices.contains).map { assets[$0] }
        let keep = Set(assets[max(0, index - 2)...min(assets.count - 1, index + 2)].map(\.localIdentifier))
        images = images.filter { keep.contains($0.key) }
        for asset in nearby where images[asset.localIdentifier] == nil {
            guard let image = await PhotoImages.image(asset, side: side, fill: false) else { continue }
            // Decoded off the main thread, so drawing it the first time doesn't hitch a swipe.
            let decoded = await image.byPreparingForDisplay() ?? image
            guard !Task.isCancelled else { return }
            images[asset.localIdentifier] = decoded
        }
    }

    /// Like Photos': the weekday for this week's photos, otherwise the date, and the time.
    private static func subtitle(_ date: Date) -> String {
        let day = Date().timeIntervalSince(date) < 6 * 24 * 3600
            ? date.formatted(.dateTime.weekday(.wide))
            : date.formatted(date: .abbreviated, time: .omitted)
        return "\(day)  \(Dates.formatTime(date))"
    }
}

/// One photo, centered, with its details below the screen. Swiping up brings the details up, and once
/// they reach the photo they push it up too, stopping with the details in view; swiping down puts it
/// back. Pinch or double-tap the photo to zoom in, and drag to look around it.
private struct PhotoPage: View {
    let asset: PHAsset
    let size: CGSize
    /// Loaded by the viewer, ahead of time.
    let image: UIImage?
    @Binding var showsInfo: Bool
    @Binding var zoomed: Bool
    let isCurrent: Bool
    @State private var position = ScrollPosition(y: 0)
    @State private var scrollY: CGFloat = 0
    @State private var info: PhotoInfo?
    @State private var zoom = PhotoZoom()
    /// The zoom, and where the fingers were, as a pinch began.
    @State private var pinchStart: (zoom: PhotoZoom, location: CGPoint)?
    /// The zoom, and how far the finger had moved, as a one-finger drag began (or carried on after a
    /// pinch).
    @State private var dragStart: (zoom: PhotoZoom, translation: CGSize)?
    /// The photo at full size, loaded once it's zoomed in far enough to need it.
    @State private var fullImage: UIImage?

    private static let gap: CGFloat = 20

    /// How tall the photo is drawn: fit to the screen.
    private var photoHeight: CGFloat {
        guard asset.pixelWidth > 0, asset.pixelHeight > 0 else { return size.height }
        return min(size.height, size.width * CGFloat(asset.pixelHeight) / CGFloat(asset.pixelWidth))
    }

    /// Where the details stop: their top a quarter of the way down the screen.
    private var infoOffset: CGFloat { size.height * 0.75 }

    /// How big the photo is drawn, before zooming.
    private var photoSize: CGSize {
        guard asset.pixelWidth > 0, asset.pixelHeight > 0 else { return size }
        let aspect = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
        return CGSize(width: min(size.width, photoHeight * aspect), height: photoHeight)
    }

    /// A point on the page, relative to its center, where the photo's center is while it can zoom.
    private func fromCenter(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
    }

    /// Where the photo's bottom is: centered, until the details push it up.
    private var photoBottom: CGFloat {
        min((size.height + photoHeight) / 2, size.height - scrollY - PhotoPage.gap)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                // The first screen is the photo's, drawn behind.
                Color.clear.frame(height: size.height)
                PhotoInfoPanel(asset: asset, info: info)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 48)
            }
            // Tall enough to stop at the details however short they are.
            .frame(width: size.width)
            .frame(minHeight: infoOffset + size.height, alignment: .top)
        }
        .scrollPosition($position)
        .scrollTargetBehavior(InfoSnap(infoOffset: infoOffset))
        .scrollIndicators(.hidden)
        .scrollDisabled(zoom.isZoomed)
        // Zooming is for the photo on its own, not with the details up.
        .gesture(PinchRecognizer(action: pinch))
        .simultaneousGesture(pan, isEnabled: zoom.isZoomed)
        .onTapGesture(count: 2) { location in
            guard !showsInfo else { return }
            withAnimation(.spring(duration: 0.35)) {
                zoom = zoom.isZoomed ? PhotoZoom()
                    : PhotoZoom().magnified(by: 2.5, around: fromCenter(location))
                        .settled(content: photoSize, viewport: size)
            }
        }
        .onChange(of: zoom.isZoomed) { _, isZoomed in
            if isCurrent { zoomed = isZoomed }
        }
        .onChange(of: zoom.scale > 1.5) { _, needsMore in
            guard needsMore, fullImage == nil else { return }
            Task {
                let side = CGFloat(max(asset.pixelWidth, asset.pixelHeight)) / UITraitCollection.current.displayScale
                let full = await PhotoImages.image(asset, side: side, fill: false)
                fullImage = await full?.byPreparingForDisplay() ?? full
            }
        }
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, y in
            scrollY = y
            let shown = y > infoOffset / 2
            if isCurrent && shown != showsInfo { showsInfo = shown }
        }
        .background(alignment: .top) {
            photo
                .frame(width: size.width, height: photoHeight)
                .scaleEffect(zoom.scale)
                .offset(zoom.offset)
                .offset(y: photoBottom - photoHeight)
        }
        .onAppear { position = ScrollPosition(y: showsInfo ? infoOffset : 0) }
        .onChange(of: isCurrent) { _, current in
            // A photo swiped to opens the way the last one was; one swiped away is zoomed back out.
            if current { position = ScrollPosition(y: showsInfo ? infoOffset : 0) }
            if !current {
                zoom = PhotoZoom()
                fullImage = nil
            }
        }
        .task(id: isCurrent && showsInfo) {
            guard isCurrent, showsInfo, info == nil else { return }
            info = await PhotoInfo.load(asset)
        }
    }

    /// Pinching zooms around the fingers, and moving them pans, like Photos.
    private func pinch(_ phase: GesturePhase) {
        switch phase.state {
        case .began:
            guard !showsInfo else { return }
            pinchStart = (zoom, phase.localLocation)
        case .changed:
            guard let start = pinchStart else { return }
            let moved = CGSize(width: phase.localLocation.x - start.location.x,
                               height: phase.localLocation.y - start.location.y)
            zoom = start.zoom.magnified(by: phase.scale, around: fromCenter(start.location)).panned(by: moved)
        case .ended, .cancelled:
            guard pinchStart != nil else { return }
            pinchStart = nil
            dragStart = nil
            withAnimation(.spring(duration: 0.35)) { zoom = zoom.settled(content: photoSize, viewport: size) }
        }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                // The pinch pans while two fingers are down; a finger left down carries on from there.
                guard pinchStart == nil else {
                    dragStart = nil
                    return
                }
                let start = dragStart ?? (zoom, value.translation)
                dragStart = start
                zoom = start.zoom.panned(by: CGSize(width: value.translation.width - start.translation.width,
                                                    height: value.translation.height - start.translation.height))
            }
            .onEnded { value in
                guard pinchStart == nil else { return }
                dragStart = nil
                // Carries on a little in the direction it was flung, then stays within the photo.
                let flung = zoom.panned(by: CGSize(width: value.velocity.width * 0.1, height: value.velocity.height * 0.1))
                withAnimation(.spring(duration: 0.45)) { zoom = flung.settled(content: photoSize, viewport: size) }
            }
    }

    private var photo: some View {
        ZStack {
            if let image = fullImage ?? image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if asset.mediaType == .video {
                Label(PhotoInfo.duration(asset.duration), systemImage: "video.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .shadow(radius: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(asset.mediaType == .video ? "Video" : "Photo")
    }
}

/// How far a photo is zoomed in, and panned from its center.
struct PhotoZoom: Equatable {
    static let maxScale: CGFloat = 5

    var scale: CGFloat = 1
    var offset: CGSize = .zero

    var isZoomed: Bool { scale > 1.01 }

    /// Zoomed by `factor`, keeping the point of the photo under `focus` (relative to the photo's
    /// center) where it is. It can go a little past the limits while pinching; `settled` brings it back.
    func magnified(by factor: CGFloat, around focus: CGPoint) -> PhotoZoom {
        let next = min(max(scale * factor, 0.6), PhotoZoom.maxScale * 1.3)
        let ratio = next / scale
        return PhotoZoom(scale: next, offset: CGSize(width: focus.x - ratio * (focus.x - offset.width),
                                                     height: focus.y - ratio * (focus.y - offset.height)))
    }

    func panned(by translation: CGSize) -> PhotoZoom {
        PhotoZoom(scale: scale, offset: CGSize(width: offset.width + translation.width,
                                               height: offset.height + translation.height))
    }

    /// Within the limits: no smaller than the photo fit to the screen, no bigger than `maxScale`, and
    /// panned no further than the photo's edges (a side that fits stays centered).
    func settled(content: CGSize, viewport: CGSize) -> PhotoZoom {
        let scale = min(max(self.scale, 1), PhotoZoom.maxScale)
        guard scale > 1.01 else { return PhotoZoom() }
        let ratio = scale / self.scale
        let maxX = max(0, (content.width * scale - viewport.width) / 2)
        let maxY = max(0, (content.height * scale - viewport.height) / 2)
        return PhotoZoom(scale: scale, offset: CGSize(width: min(max(offset.width * ratio, -maxX), maxX),
                                                      height: min(max(offset.height * ratio, -maxY), maxY)))
    }
}

/// Stops a photo page either on the photo or on its details; past the details' top, it scrolls freely.
private struct InfoSnap: ScrollTargetBehavior {
    let infoOffset: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let start = context.originalTarget.rect.minY
        let end = target.rect.minY
        // Swiping up from the photo stops at the details, however hard.
        if start < infoOffset / 2 && end > infoOffset {
            target.rect.origin.y = infoOffset
            return
        }
        guard end < infoOffset else { return }
        let goingUp = context.velocity.dy > 0.3 || (abs(context.velocity.dy) <= 0.3 && end > infoOffset / 2)
        target.rect.origin.y = goingUp ? infoOffset : 0
    }
}

/// What a photo's details show, read when they're first opened.
struct PhotoInfo {
    var filename: String?
    var metadata = PhotoMetadata()
    /// Like "12 MP • 3024 × 4032 • 1.9 MB".
    var dimensions: String
    var placeName: String?

    static func load(_ asset: PHAsset) async -> PhotoInfo {
        let resources = PHAssetResource.assetResources(for: asset)
        let original = resources.first { $0.type == .photo || $0.type == .video } ?? resources.first
        var info = PhotoInfo(filename: original.map { ($0.originalFilename as NSString).deletingPathExtension },
                             dimensions: "")
        var bytes: Int?
        if asset.mediaType == .image {
            let read = await imageData(asset)
            bytes = read.data?.count
            if let data = read.data, let source = CGImageSourceCreateWithData(data as CFData, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                info.metadata = PhotoMetadata(properties: properties, typeIdentifier: read.type)
            }
        } else {
            info.metadata.format = "Video"
        }
        info.dimensions = [
            PhotoMetadata.megapixels(width: asset.pixelWidth, height: asset.pixelHeight),
            "\(asset.pixelWidth) × \(asset.pixelHeight)",
            bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) },
            asset.mediaType == .video ? duration(asset.duration) : nil,
        ].compactMap { $0 }.joined(separator: " • ")
        if let location = asset.location {
            info.placeName = await PlaceSearch.describe(Coordinate(location.coordinate))?.name
        }
        return info
    }

    /// The photo's file, from iCloud if it's not on the phone.
    private static func imageData(_ asset: PHAsset) async -> (data: Data?, type: String?) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, type, _, _ in
                continuation.resume(returning: (data, type))
            }
        }
    }

    /// Like "0:42" or "1:02:03".
    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded()).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

/// A photo's details, in cards like Photos': when, which file, the camera and its settings, and where.
private struct PhotoInfoPanel: View {
    let asset: PHAsset
    let info: PhotoInfo?

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                row {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.creationDate.map(Self.date) ?? "No Date").font(.body)
                        if let filename = info?.filename {
                            Text(filename).foregroundStyle(.secondary)
                        }
                    }
                }
                if let info {
                    Divider()
                    row {
                        HStack {
                            Text(info.metadata.camera ?? "No Camera Information")
                                .foregroundStyle(info.metadata.camera == nil ? .secondary : .primary)
                            Spacer()
                            if let format = info.metadata.format {
                                Text(format)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.white.opacity(0.12), in: .capsule)
                            }
                        }
                    }
                    Divider()
                    row {
                        VStack(alignment: .leading, spacing: 2) {
                            if let lens = info.metadata.lens { Text(lens) }
                            Text(info.dimensions)
                        }
                        .foregroundStyle(.secondary)
                    }
                    if !info.metadata.exposure.isEmpty {
                        Divider()
                        HStack(spacing: 0) {
                            ForEach(Array(info.metadata.exposure.enumerated()), id: \.offset) { i, value in
                                if i > 0 { Divider().frame(height: 16) }
                                Text(value)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                } else {
                    Divider()
                    row { ProgressView().frame(maxWidth: .infinity) }
                }
            }
            .background(Color(white: 0.11), in: .rect(cornerRadius: 22))

            if let location = asset.location {
                PhotoLocationCard(asset: asset, coordinate: location.coordinate, placeName: info?.placeName)
            }
        }
        .frame(maxWidth: 600)
    }

    private func row(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    /// Like "Friday • Nov 20, 2026 • 6:17 PM".
    private static func date(_ date: Date) -> String {
        "\(date.formatted(.dateTime.weekday(.wide))) • \(date.formatted(date: .abbreviated, time: .omitted)) • "
            + Dates.formatTime(date)
    }
}

/// Where a photo was taken: a small map with the photo pinned, and the place's name.
private struct PhotoLocationCard: View {
    let asset: PHAsset
    let coordinate: CLLocationCoordinate2D
    let placeName: String?
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))) {
                Annotation("", coordinate: coordinate, anchor: .bottom) {
                    VStack(spacing: 0) {
                        Group {
                            if let thumbnail {
                                Image(uiImage: thumbnail).resizable().scaledToFill()
                            } else {
                                Color.gray
                            }
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(.rect(cornerRadius: 6))
                        .padding(3)
                        .background(.white, in: .rect(cornerRadius: 8))
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(180))
                            .offset(y: -3)
                    }
                    .shadow(radius: 3)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .allowsHitTesting(false)
            .frame(height: 190)
            Text(placeName ?? " ")
                .foregroundStyle(Theme.blue)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .background(Color(white: 0.11))
        .clipShape(.rect(cornerRadius: 22))
        .task { thumbnail = await PhotoImages.image(asset, side: 54) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(placeName.map { "Taken at \($0)" } ?? "Location")
    }
}
#endif
