#if os(macOS)
import SwiftUI
import AppKit

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

}

/// A drag up or down, in points: negative is up.
struct VerticalDrag {
    var state: GesturePhase.State
    var translation: CGFloat
    /// Points per second.
    var velocity: CGFloat
}

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
