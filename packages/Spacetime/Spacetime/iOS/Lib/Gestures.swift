#if os(iOS)
import SwiftUI
import UIKit

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
}

/// A drag up or down, in points: negative is up.
struct VerticalDrag {
    var state: GesturePhase.State
    var translation: CGFloat
    /// Points per second.
    var velocity: CGFloat
}

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

    func makeUIGestureRecognizer(context: Context) -> TouchDownPanRecognizer {
        TouchDownPanRecognizer()
    }

    func updateUIGestureRecognizer(_ recognizer: TouchDownPanRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: TouchDownPanRecognizer, context: Context) {
        guard var phase = GesturePhase(recognizer, localLocation: context.converter.localLocation) else { return }
        if phase.state == .began, let touchDown = recognizer.touchDown {
            // A pan begins once the finger has moved a little. Begin it where the finger came down, or
            // what's dragged lags that far behind the finger.
            phase.localLocation.x += touchDown.x - phase.location.x
            phase.localLocation.y += touchDown.y - phase.location.y
            phase.location = touchDown
        }
        action(phase)
    }
}

/// A pan that remembers where the finger came down, in the window. (Its translation leaves out some
/// of the way the finger moved before it began.)
final class TouchDownPanRecognizer: UIPanGestureRecognizer {
    private(set) var touchDown: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if touchDown == nil { touchDown = touches.first?.location(in: nil) }
    }

    override func reset() {
        super.reset()
        touchDown = nil
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
#endif
