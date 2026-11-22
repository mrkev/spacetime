import SwiftUI

/// The day page's timeline: its measurements, and the math for dragging blocks and pinching it.
enum Timeline {
    /// How tall an hour is by default; pinching zooms between the min and max.
    static let defaultHourHeight: CGFloat = 56
    static let minHourHeight: CGFloat = 24
    static let maxHourHeight: CGFloat = 180
    static let gutter: CGFloat = 56
    static let padding: CGFloat = 12
    /// Reminders are points in time, so they stay this tall at any zoom.
    static let reminderHeight: CGFloat = 26
    static let minBlockHeight: CGFloat = 20
    static let handleHit: CGFloat = 44
    static let titleLine: CGFloat = 15
    static let subtitleLine: CGFloat = 14
    static let blockPadding: CGFloat = 2
    static let menuHeight: CGFloat = 44

    /// Where the timeline scrolls to show the current time: an hour above it.
    static func nowOffset(hourHeight: CGFloat) -> CGFloat {
        max(0, (CGFloat(Dates.minutesIntoDay(Date())) / 60 - 1) * hourHeight)
    }

    static func y(minute: Double, hourHeight: CGFloat) -> CGFloat {
        padding + CGFloat(minute) / 60 * hourHeight
    }

    /// Where to scroll to keep the same time at the top when the hours change height.
    static func scrollY(_ y: CGFloat, rescaledFrom previous: CGFloat, to height: CGFloat) -> CGFloat {
        max(0, padding + (y - padding) * height / previous)
    }

    static func blockFrame(_ range: MinuteRange, hourHeight: CGFloat) -> (top: CGFloat, height: CGFloat) {
        (y(minute: range.startMinute, hourHeight: hourHeight),
         max(minBlockHeight, CGFloat(range.endMinute - range.startMinute) / 60 * hourHeight - 2))
    }
}

/// A block on the timeline following a finger up or down: moved whole, or by its start or end.
struct BlockDrag {
    var mode: DragMode
    /// Where the block was when the drag began.
    var origin: MinuteRange
    /// The finger's height in the window when the drag began.
    var startY: CGFloat

    /// Where the block is with the finger at `y`, snapped to the quarter hour.
    func range(atY y: CGFloat, hourHeight: CGFloat) -> MinuteRange {
        Editing.drag(origin, mode: mode, deltaMinutes: Double((y - startY) / hourHeight * 60))
    }
}

/// A pinch zooming the timeline, which keeps the minute under the fingers where it is.
struct TimelinePinch {
    var startHeight: CGFloat
    /// The minute under the fingers when the pinch began.
    var minute: Double
    /// How far down the visible timeline the fingers are.
    var focalY: CGFloat

    init(hourHeight: CGFloat, scrollY: CGFloat, focalY: CGFloat) {
        startHeight = hourHeight
        minute = Double((scrollY + focalY - Timeline.padding) / hourHeight * 60)
        self.focalY = focalY
    }

    /// The hour height with the fingers spread by `scale`, within the zoom's limits.
    func hourHeight(scale: CGFloat) -> CGFloat {
        min(Timeline.maxHourHeight, max(Timeline.minHourHeight, startHeight * scale)).rounded()
    }

    /// Where to scroll at `hourHeight` so the minute stays under the fingers.
    func scrollY(hourHeight: CGFloat) -> CGFloat {
        max(0, Timeline.padding + CGFloat(minute) / 60 * hourHeight - focalY)
    }
}
