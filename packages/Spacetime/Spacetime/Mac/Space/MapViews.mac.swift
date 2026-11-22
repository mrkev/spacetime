#if os(macOS)
import MapKit
import SwiftUI
import AppKit

/// A marker on the Space map: a place's pin or a search result.
struct MapPin: Hashable {
    enum Kind: Hashable {
        case place
        case result(Int)
    }

    var id: String
    var kind: Kind
    var coordinate: Coordinate
    var color: String
    var glyph: String?
    var name: String
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
    case selected(name: String, coordinate: Coordinate, icon: PlatformImage?)
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
    func focus(on coordinates: [Coordinate], padding: PlatformEdgeInsets) {
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
    let base = PlatformColor(hex: color)
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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    fileprivate func makeMap(_ coordinator: Coordinator) -> MKMapView {
        let map = MKMapView()
        map.delegate = coordinator
        map.showsCompass = false
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "pin")
        if let initialRegion { map.setRegion(initialRegion.mkRegion, animated: false) }
        // A long click or a right click drops a pin. None of these hold up the map's own clicks and drags.
        let longPress = NSPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.longPressed(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.delaysPrimaryMouseButtonEvents = false
        longPress.delegate = coordinator
        map.addGestureRecognizer(longPress)
        let rightClick = NSClickGestureRecognizer(target: coordinator, action: #selector(Coordinator.longPressed(_:)))
        rightClick.buttonMask = 0x2
        rightClick.delegate = coordinator
        map.addGestureRecognizer(rightClick)
        let tap = NSClickGestureRecognizer(target: coordinator, action: #selector(Coordinator.tapped))
        tap.delaysPrimaryMouseButtonEvents = false
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
            guard let annotation = annotation as? PinAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "pin", for: annotation)
            guard let marker = view as? MKMarkerAnnotationView else { return view }
            marker.markerTintColor = PlatformColor(hex: annotation.pin.color)
            marker.glyphImage = PlaceIcon.image(annotation.pin.glyph)
            marker.displayPriority = .required
            marker.titleVisibility = .hidden
            marker.canShowCallout = false
            marker.setAccessibilityLabel(annotation.pin.name)
            return marker
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let fence = (overlay as? FenceOverlay)?.fence { return circleRenderer(overlay, color: fence.color) }
            return MKOverlayRenderer(overlay: overlay)
        }

        // The annotation-view versions, since the Mac doesn't have the annotation ones.
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation else { return }
            if let pin = (annotation as? PinAnnotation)?.pin {
                parent.onSelectPin(pin)
            } else {
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard let annotation = view.annotation else { return }
            if let pin = (annotation as? PinAnnotation)?.pin {
                parent.onDeselectPin(pin)
            } else {
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange(SearchRegion(mapView.region))
        }

        @objc func longPressed(_ recognizer: NSGestureRecognizer) {
            // A press begins; a click (right click) ends.
            guard recognizer.state == (recognizer is NSClickGestureRecognizer ? .ended : .began),
                  let map = recognizer.view as? MKMapView else { return }
            let point = recognizer.location(in: map)
            parent.onLongPress(Coordinate(map.convert(point, toCoordinateFrom: map)))
        }

        @objc func tapped() {
            parent.onTap()
        }
    }
}

extension SpaceMapView: NSViewRepresentable {
    func makeNSView(context: Context) -> MKMapView { makeMap(context.coordinator) }
    func updateNSView(_ map: MKMapView, context: Context) { updateMap(map, context.coordinator) }
}

extension SpaceMapView.Coordinator: NSGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: NSGestureRecognizer) -> Bool {
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
            view.markerTintColor = PlatformColor(hex: parent.color)
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

extension PreviewMapView: NSViewRepresentable {
    func makeNSView(context: Context) -> MKMapView { makeMap(context.coordinator) }
    func updateNSView(_ map: MKMapView, context: Context) { updateMap(map, context.coordinator) }
}
#endif
