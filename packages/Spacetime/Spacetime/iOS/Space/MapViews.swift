#if os(iOS)
import MapKit
import OSLog
import SwiftUI
import UIKit

/// A marker on the Space map: a place's pin or a search result.
struct MapPin: Hashable {
    enum Kind: Hashable {
        case place
        case result(Int)
        /// Photos taken around a spot (see `MapLayers`).
        case photos
        /// A contact's address.
        case contact
    }

    var id: String
    var kind: Kind
    var coordinate: Coordinate
    var color: String
    var glyph: String?
    var name: String
    /// How many photos a photos pin stands for.
    var count = 1
    /// The photo (an asset ID) or contact (a contact ID) whose picture a photos or contact pin shows.
    var imageId: String?
}

/// A todo's geofence.
struct MapFence: Hashable {
    var id: String
    var coordinate: Coordinate
    var radius: Double
    var color: String
}

/// A point of interest on Apple's map (a shop, a park) being selected or deselected.
enum PoiEvent {
    case selected(name: String, coordinate: Coordinate, icon: UIImage?)
    case deselected(coordinate: Coordinate)
}

/// Moves the Space map's camera.
final class MapController {
    fileprivate weak var mapView: MKMapView?

    var region: SearchRegion? {
        mapView.map { SearchRegion($0.region) }
    }

    func show(_ region: MKCoordinateRegion, animated: Bool = true) {
        mapView?.setRegion(region, animated: animated)
    }

    /// Shows one place up close, or several all in view.
    func focus(on coordinates: [Coordinate], padding: UIEdgeInsets) {
        guard let mapView, let first = coordinates.first else { return }
        if coordinates.count == 1 {
            mapView.setRegion(MKCoordinateRegion(center: first.clCoordinate,
                                                 span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)),
                              animated: true)
            return
        }
        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate.clCoordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1))
        }
        mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)
    }

    /// Selects a pin, and brings it into view if it's out of it.
    func select(pinId: String) {
        guard let mapView,
              let annotation = mapView.annotations.first(where: { ($0 as? PinAnnotation)?.pin.id == pinId })
        else { return }
        if !mapView.visibleMapRect.contains(MKMapPoint(annotation.coordinate)) {
            mapView.setCenter(annotation.coordinate, animated: true)
        }
        mapView.selectAnnotation(annotation, animated: true)
    }

    func deselectAll() {
        guard let mapView else { return }
        for annotation in mapView.selectedAnnotations { mapView.deselectAnnotation(annotation, animated: true) }
    }
}

private final class PinAnnotation: MKPointAnnotation {
    let pin: MapPin
    init(_ pin: MapPin) {
        self.pin = pin
        super.init()
        coordinate = pin.coordinate.clCoordinate
    }
}

private final class FenceOverlay: MKCircle {
    var fence: MapFence?
}

private func circleRenderer(_ overlay: MKOverlay, color: String) -> MKOverlayRenderer {
    let renderer = MKCircleRenderer(overlay: overlay)
    let base = UIColor(hex: color)
    renderer.strokeColor = base.withAlphaComponent(0.8)
    renderer.fillColor = base.withAlphaComponent(0.15)
    renderer.lineWidth = 1.5
    return renderer
}

/// The Space tab's map: places' pins, todos' geofences, search results, and Apple's points of
/// interest, which can be tapped.
struct SpaceMapView {
    var pins: [MapPin]
    var fences: [MapFence]
    var showsUserLocation: Bool
    var initialRegion: SearchRegion?
    var controller: MapController
    var onSelectPin: (MapPin) -> Void
    var onDeselectPin: (MapPin) -> Void
    var onPoi: (PoiEvent) -> Void
    var onLongPress: (Coordinate) -> Void
    var onRegionChange: (SearchRegion) -> Void
    var onTap: () -> Void
    /// Pictures for photo and contact pins.
    var thumbnails: MapThumbnails?
    /// A photo or contact pin, or a cluster of them, was tapped.
    var onSelectThumbnails: ([MapPin]) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    fileprivate func makeMap(_ coordinator: Coordinator) -> MKMapView {
        let map = MKMapView()
        map.delegate = coordinator
        map.showsCompass = false
        map.register(ThumbnailAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: ThumbnailAnnotationView.reuseIdentifier)
        map.register(ThumbnailAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: ThumbnailAnnotationView.clusterReuseIdentifier)
        // The Mac's MKMapView can't select points of interest.
        map.selectableMapFeatures = [.pointsOfInterest]
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "pin")
        if let initialRegion { map.setRegion(initialRegion.mkRegion, animated: false) }
        let longPress = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.longPressed(_:)))
        map.addGestureRecognizer(longPress)
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tapped))
        tap.cancelsTouchesInView = false
        tap.delegate = coordinator
        map.addGestureRecognizer(tap)
        controller.mapView = map
        return map
    }

    fileprivate func updateMap(_ map: MKMapView, _ coordinator: Coordinator) {
        coordinator.parent = self
        controller.mapView = map
        map.showsUserLocation = showsUserLocation

        let existing = map.annotations.compactMap { $0 as? PinAnnotation }
        let wanted = Set(pins)
        let present = Set(existing.map(\.pin))
        map.removeAnnotations(existing.filter { !wanted.contains($0.pin) })
        map.addAnnotations(pins.filter { !present.contains($0) }.map { PinAnnotation($0) })

        let overlays = map.overlays.compactMap { $0 as? FenceOverlay }
        let wantedFences = Set(fences)
        let presentFences = Set(overlays.compactMap(\.fence))
        map.removeOverlays(overlays.filter { !wantedFences.contains($0.fence!) })
        for fence in fences where !presentFences.contains(fence) {
            let overlay = FenceOverlay(center: fence.coordinate.clCoordinate, radius: fence.radius)
            overlay.fence = fence
            map.addOverlay(overlay)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: SpaceMapView

        init(_ parent: SpaceMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let pins = thumbnailPins(annotation) {
                return thumbnailView(mapView, annotation, pins)
            }
            guard let annotation = annotation as? PinAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "pin", for: annotation)
            guard let marker = view as? MKMarkerAnnotationView else { return view }
            marker.markerTintColor = UIColor(hex: annotation.pin.color)
            marker.glyphImage = PlaceIcon.image(annotation.pin.glyph)
            marker.displayPriority = .required
            marker.titleVisibility = .hidden
            marker.canShowCallout = false
            marker.accessibilityLabel = annotation.pin.name
            return marker
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let fence = (overlay as? FenceOverlay)?.fence { return circleRenderer(overlay, color: fence.color) }
            return MKOverlayRenderer(overlay: overlay)
        }

        /// The photo or contact pins an annotation stands for: its own, or a cluster's.
        private func thumbnailPins(_ annotation: MKAnnotation) -> [MapPin]? {
            let members = (annotation as? MKClusterAnnotation)?.memberAnnotations ?? [annotation]
            let pins = members.compactMap { ($0 as? PinAnnotation)?.pin }
            guard !pins.isEmpty, pins.count == members.count,
                  pins.allSatisfy({ $0.kind == .photos || $0.kind == .contact }) else { return nil }
            // A cluster shows the photo of its most photographed spot, or its first contact by name.
            return pins.sorted { ($1.count, $0.name, $0.id) < ($0.count, $1.name, $1.id) }
        }

        private func thumbnailView(_ mapView: MKMapView, _ annotation: MKAnnotation,
                                   _ pins: [MapPin]) -> MKAnnotationView {
            // Clusters' views are kept apart from pins': MapKit treats a view that showed a cluster as one
            // after it's reused, and crashed asking a pin for its cluster's members.
            let isCluster = annotation is MKClusterAnnotation
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: isCluster ? ThumbnailAnnotationView.clusterReuseIdentifier
                    : ThumbnailAnnotationView.reuseIdentifier,
                for: annotation)
            guard let thumbnail = view as? ThumbnailAnnotationView else { return view }
            thumbnail.configure(pins, isCluster: isCluster, thumbnails: parent.thumbnails)
            thumbnail.onSelect = { [weak self, weak mapView] pins in
                // Deselected right away, so it can be tapped again.
                DispatchQueue.main.async { mapView?.deselectAnnotation(annotation, animated: false) }
                self?.parent.onSelectThumbnails(pins)
            }
            return thumbnail
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let pin = (annotation as? PinAnnotation)?.pin {
                parent.onSelectPin(pin)
            } else if annotation is MKMapFeatureAnnotation {
                syncFeature(mapView)
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect annotation: MKAnnotation) {
            if let pin = (annotation as? PinAnnotation)?.pin {
                parent.onDeselectPin(pin)
            } else if annotation is MKMapFeatureAnnotation {
                syncFeature(mapView)
            }
        }

        /// The point of interest last reported as selected.
        private var reportedFeature: MKMapFeatureAnnotation?

        /// Reports the point of interest the map has selected, once it's done selecting. Going by the
        /// map rather than by each callback, since MapKit can deselect a point of interest after
        /// selecting another (or a new copy of the same one), which left the map with one selected
        /// and its card gone.
        private func syncFeature(_ mapView: MKMapView) {
            DispatchQueue.main.async { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                let feature = mapView.selectedAnnotations.lazy.compactMap { $0 as? MKMapFeatureAnnotation }.first
                guard feature !== reportedFeature else { return }
                let previous = reportedFeature
                reportedFeature = feature
                if let feature {
                    Log.places.debug("Selected point of interest \(feature.title ?? "", privacy: .private)")
                    parent.onPoi(.selected(name: feature.title ?? "", coordinate: Coordinate(feature.coordinate),
                                           icon: feature.iconStyle?.image))
                } else if let previous {
                    Log.places.debug("Deselected point of interest \(previous.title ?? "", privacy: .private)")
                    parent.onPoi(.deselected(coordinate: Coordinate(previous.coordinate)))
                }
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange(SearchRegion(mapView.region))
        }

        @objc func longPressed(_ recognizer: UIGestureRecognizer) {
            guard recognizer.state == .began, let map = recognizer.view as? MKMapView else { return }
            let point = recognizer.location(in: map)
            parent.onLongPress(Coordinate(map.convert(point, toCoordinateFrom: map)))
        }

        @objc func tapped() {
            parent.onTap()
        }
    }
}

extension SpaceMapView: UIViewRepresentable {
    func makeUIView(context: Context) -> MKMapView { makeMap(context.coordinator) }
    func updateUIView(_ map: MKMapView, context: Context) { updateMap(map, context.coordinator) }
}

extension SpaceMapView.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// A map span that comfortably fits a geofence of the given radius.
func regionSpan(radius: Double) -> MKCoordinateSpan {
    let meters = max(400, radius * 3.2)
    let delta = meters / 111_000
    return MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
}

/// A small map in a form, with the place's pin (draggable unless `fixed`) and a todo's radius.
struct PreviewMapView {
    var coordinate: Coordinate
    var color: String
    var radius: Double?
    var radiusColor: String?
    var fixed: Bool
    var onDragEnd: (Coordinate) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    fileprivate func makeMap(_ coordinator: Coordinator) -> MKMapView {
        let map = MKMapView()
        map.delegate = coordinator
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.pointOfInterestFilter = .includingAll
        map.setRegion(MKCoordinateRegion(center: coordinate.clCoordinate, span: regionSpan(radius: radius ?? 0)),
                      animated: false)
        return map
    }

    fileprivate func updateMap(_ map: MKMapView, _ coordinator: Coordinator) {
        let previous = coordinator.parent
        coordinator.parent = self
        map.isScrollEnabled = !fixed
        map.isZoomEnabled = !fixed

        let annotation = coordinator.annotation
        if map.annotations.isEmpty || previous.color != color || previous.fixed != fixed {
            map.removeAnnotations(map.annotations)
            map.addAnnotation(annotation)
        }
        if !coordinator.dragging, annotation.coordinate.latitude != coordinate.latitude
            || annotation.coordinate.longitude != coordinate.longitude {
            annotation.coordinate = coordinate.clCoordinate
        }
        let fence = radius.flatMap { r in radiusColor.map { MapFence(id: "", coordinate: coordinate, radius: r, color: $0) } }
        if fence != coordinator.fence {
            map.removeOverlays(map.overlays)
            coordinator.fence = fence
            if let fence {
                let overlay = FenceOverlay(center: fence.coordinate.clCoordinate, radius: fence.radius)
                overlay.fence = fence
                map.addOverlay(overlay)
            }
        }
        if previous.coordinate != coordinate || previous.radius != radius {
            map.setRegion(MKCoordinateRegion(center: coordinate.clCoordinate, span: regionSpan(radius: radius ?? 0)),
                          animated: true)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: PreviewMapView
        let annotation = MKPointAnnotation()
        var fence: MapFence?
        var dragging = false

        init(_ parent: PreviewMapView) {
            self.parent = parent
            annotation.coordinate = parent.coordinate.clCoordinate
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation === self.annotation else { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: nil)
            view.markerTintColor = UIColor(hex: parent.color)
            view.isDraggable = !parent.fixed
            view.displayPriority = .required
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let fence = (overlay as? FenceOverlay)?.fence { return circleRenderer(overlay, color: fence.color) }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            switch newState {
            case .starting, .dragging:
                dragging = true
            case .ending, .canceling:
                dragging = false
                view.dragState = .none
                if newState == .ending { parent.onDragEnd(Coordinate(annotation.coordinate)) }
            default:
                break
            }
        }
    }
}

extension PreviewMapView: UIViewRepresentable {
    func makeUIView(context: Context) -> MKMapView { makeMap(context.coordinator) }
    func updateUIView(_ map: MKMapView, context: Context) { updateMap(map, context.coordinator) }
}
#endif
