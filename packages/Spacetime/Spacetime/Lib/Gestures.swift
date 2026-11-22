import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// A gesture's progress, with where the touch (or pointer) is in the window, which doesn't move while
/// the timeline holds still for a drag.
struct GesturePhase {
    enum State { case began, changed, ended, cancelled }
    var state: State
    /// In the window.
    var location: CGPoint
    /// In the view the gesture is attached to.
    var localLocation: CGPoint
    var scale: CGFloat = 1

    init(state: State, location: CGPoint, localLocation: CGPoint, scale: CGFloat = 1) {
        self.state = state
        self.location = location
        self.localLocation = localLocation
        self.scale = scale
    }

    #if os(iOS)
    init?(_ recognizer: UIGestureRecognizer, localLocation: CGPoint) {
        switch recognizer.state {
        case .began: state = .began
        case .changed: state = .changed
        case .ended: state = .ended
        case .cancelled, .failed: state = .cancelled
        default: return nil
        }
        location = recognizer.location(in: nil)
        self.localLocation = localLocation
        if let pinch = recognizer as? UIPinchGestureRecognizer { scale = pinch.scale }
    }
    #endif
}

/// A drag up or down, in points: negative is up.
struct VerticalDrag {
    var state: GesturePhase.State
    var translation: CGFloat
    /// Points per second.
    var velocity: CGFloat
}

#if os(iOS)

/// Touch and hold, then (optionally) drag.
struct LongPressRecognizer: UIGestureRecognizerRepresentable {
    var minimumDuration: TimeInterval = 0.35
    var isEnabled = true
    var action: (GesturePhase) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = minimumDuration
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        if let phase = GesturePhase(recognizer, localLocation: context.converter.localLocation) { action(phase) }
    }
}

/// A drag that starts as soon as the touch moves.
struct PanRecognizer: UIGestureRecognizerRepresentable {
    var isEnabled = true
    var action: (GesturePhase) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        UIPanGestureRecognizer()
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        if let phase = GesturePhase(recognizer, localLocation: context.converter.localLocation) { action(phase) }
    }
}

/// A drag that only starts when it's more up or down than sideways, so a horizontal scroll view it's
/// in still scrolls sideways (the scroll view waits for it to fail).
private struct VerticalPanRecognizer: UIGestureRecognizerRepresentable {
    var action: (VerticalDrag) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard let phase = GesturePhase(recognizer, localLocation: .zero) else { return }
        action(VerticalDrag(state: phase.state, translation: recognizer.translation(in: recognizer.view).y,
                            velocity: recognizer.velocity(in: recognizer.view).y))
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.y) > abs(velocity.x)
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}

extension View {
    /// An up or down drag, which leaves sideways ones to a scroll view it's in.
    func onVerticalDrag(_ action: @escaping (VerticalDrag) -> Void) -> some View {
        gesture(VerticalPanRecognizer(action: action))
    }
}

struct PinchRecognizer: UIGestureRecognizerRepresentable {
    var action: (GesturePhase) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        UIPinchGestureRecognizer()
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        if let phase = GesturePhase(recognizer, localLocation: context.converter.localLocation) { action(phase) }
    }
}

enum Haptics {
    static func impact() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
#else
/// A mouse drag, reported in phases like the iPhone's recognizers.
private struct DragPhases: ViewModifier {
    var isEnabled: Bool
    var action: (GesturePhase) -> Void
    /// Where the view is in the window, to work out the local location from the window one.
    @State private var origin: CGPoint = .zero
    @State private var active = false
    @GestureState private var pressing = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { origin = $0 }
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .updating($pressing) { _, pressing, _ in pressing = true }
                    .onChanged { value in
                        if !active {
                            active = true
                            send(.began, at: value.startLocation)
                        }
                        send(.changed, at: value.location)
                    }
                    .onEnded { value in
                        guard active else { return }
                        active = false
                        send(.ended, at: value.location)
                    },
                isEnabled: isEnabled)
            .onChange(of: pressing) { _, pressing in
                // The drag stopped without ending (another gesture took over, say).
                if !pressing && active {
                    active = false
                    send(.cancelled, at: .zero)
                }
            }
    }

    private func send(_ state: GesturePhase.State, at location: CGPoint) {
        action(GesturePhase(state: state, location: location,
                            localLocation: CGPoint(x: location.x - origin.x, y: location.y - origin.y)))
    }
}

/// A mouse drag up or down, reported like the iPhone's recognizer.
private struct VerticalDragPhases: ViewModifier {
    var action: (VerticalDrag) -> Void
    @State private var active = false
    @GestureState private var pressing = false

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 6)
                    .updating($pressing) { _, pressing, _ in pressing = true }
                    .onChanged { value in
                        if !active {
                            guard abs(value.translation.height) > abs(value.translation.width) else { return }
                            active = true
                            action(VerticalDrag(state: .began, translation: value.translation.height, velocity: 0))
                        }
                        action(VerticalDrag(state: .changed, translation: value.translation.height,
                                            velocity: value.velocity.height))
                    }
                    .onEnded { value in
                        guard active else { return }
                        active = false
                        action(VerticalDrag(state: .ended, translation: value.translation.height,
                                            velocity: value.velocity.height))
                    })
            .onChange(of: pressing) { _, pressing in
                if !pressing && active {
                    active = false
                    action(VerticalDrag(state: .cancelled, translation: 0, velocity: 0))
                }
            }
    }
}

/// A trackpad pinch, reported in phases like the iPhone's recognizer.
private struct MagnifyPhases: ViewModifier {
    var action: (GesturePhase) -> Void
    @State private var active = false
    @GestureState private var magnifying = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($magnifying) { _, magnifying, _ in magnifying = true }
                    .onChanged { value in
                        if !active {
                            active = true
                            send(.began, value)
                        }
                        send(.changed, value)
                    }
                    .onEnded { value in
                        guard active else { return }
                        active = false
                        send(.ended, value)
                    })
            .onChange(of: magnifying) { _, magnifying in
                if !magnifying && active {
                    active = false
                    action(GesturePhase(state: .cancelled, location: .zero, localLocation: .zero))
                }
            }
    }

    private func send(_ state: GesturePhase.State, _ value: MagnifyGesture.Value) {
        action(GesturePhase(state: state, location: value.startLocation, localLocation: value.startLocation,
                            scale: value.magnification))
    }
}

extension View {
    /// Click and drag.
    func onDragPhases(isEnabled: Bool = true, _ action: @escaping (GesturePhase) -> Void) -> some View {
        modifier(DragPhases(isEnabled: isEnabled, action: action))
    }

    /// A drag up or down.
    func onVerticalDrag(_ action: @escaping (VerticalDrag) -> Void) -> some View {
        modifier(VerticalDragPhases(action: action))
    }

    /// Pinch on the trackpad.
    func onMagnifyPhases(_ action: @escaping (GesturePhase) -> Void) -> some View {
        modifier(MagnifyPhases(action: action))
    }
}

/// The Mac has no haptics to speak of (only Force Touch trackpads, for alignment), so these are
/// mostly silent.
enum Haptics {
    static func impact() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    static func selection() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
#endif
