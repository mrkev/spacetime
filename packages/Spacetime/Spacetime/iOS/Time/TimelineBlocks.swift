#if os(iOS)
import SwiftUI

// What the day page draws on its timeline.

struct HourGrid: View {
    let hourHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...24, id: \.self) { hour in
                HStack(spacing: 0) {
                    Text(Dates.formatHour(hour: hour))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: Timeline.gutter - 8, alignment: .trailing)
                        .padding(.trailing, 8)
                    Rectangle().fill(Theme.hourLine).frame(height: 1 / 3)
                }
                .frame(height: 16)
                .offset(y: Timeline.padding + CGFloat(hour) * hourHeight - 8)
            }
        }
    }
}

struct EventBlock: View {
    let event: CalendarEvent
    let height: CGFloat
    let selected: Bool
    let lifted: Bool
    let editing: Bool

    var body: some View {
        let color = Color(hex: event.color)
        let textColor = selected ? Color.white : Theme.eventText(event.color)
        // The block's position already says when it is, so it shows the title, plus the location when
        // there's a spare line for it.
        let inner = height - Timeline.blockPadding * 2
        let showLocation = event.location != nil && inner >= Timeline.titleLine + Timeline.subtitleLine
        let titleLines = max(1, Int(((showLocation ? inner - Timeline.subtitleLine : inner) / Timeline.titleLine)))
        VStack(alignment: .leading, spacing: 0) {
            Text(event.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(titleLines)
            if showLocation, let location = event.location {
                Text(location.replacingOccurrences(of: "\n", with: ", "))
                    .font(.system(size: 11))
                    .opacity(0.8)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 5)
        .padding(.vertical, Timeline.blockPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(selected ? color : Theme.eventFill(event.color))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .clipShape(.rect(cornerRadius: 4))
        .background {
            if lifted {
                RoundedRectangle(cornerRadius: 4).fill(color).shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            } else if !selected {
                RoundedRectangle(cornerRadius: 4).fill(Theme.background)
            }
        }
    }
}

/// A new event's block, in the calendar it'll be saved to. It pops in, like Calendar's, and has
/// handles once it's set down (only to show it can be resized; the editor sets its times).
struct NewEventBlock: View {
    let color: String
    let lifted: Bool
    @State private var popped = false

    var body: some View {
        Text("New Event")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, Timeline.blockPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(hex: color), in: .rect(cornerRadius: 4))
            .shadow(color: .black.opacity(lifted ? 0.3 : 0), radius: 8, y: 4)
            .overlay(alignment: .topTrailing) {
                if !lifted {
                    Handle(color: color).offset(x: Timeline.handleHit / 2 - 12, y: -Timeline.handleHit / 2)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !lifted {
                    Handle(color: color).offset(x: 24 - Timeline.handleHit / 2, y: Timeline.handleHit / 2)
                }
            }
            .scaleEffect(popped ? 1 : 1.08)
            .onAppear { withAnimation(.spring(duration: 0.35, bounce: 0.45)) { popped = true } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("New Event")
    }
}

struct Handle: View {
    let color: String

    var body: some View {
        Circle()
            .fill(.white)
            .stroke(Color(hex: color), lineWidth: 2)
            .frame(width: 11, height: 11)
            .frame(width: Timeline.handleHit, height: Timeline.handleHit)
            .contentShape(.rect)
    }
}

struct ReminderCheck: View {
    let reminder: CalendarReminder
    var size: CGFloat = 16
    @Environment(CalendarStore.self) private var calendar

    var body: some View {
        Button {
            do { try calendar.toggleReminder(reminder) } catch {
                Presenter.showError("Couldn’t Update Reminder", error)
            }
        } label: {
            Image(systemName: reminder.completed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: size))
                .foregroundStyle(Color(hex: reminder.color))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reminder.title)
        .accessibilityValue(reminder.completed ? "Completed" : "Not completed")
    }
}

struct ReminderBlock: View {
    let reminder: CalendarReminder
    let onPress: (CalendarReminder) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ReminderCheck(reminder: reminder)
            Text(reminder.title)
                .font(.system(size: 12, weight: .semibold))
                .strikethrough(reminder.completed)
                .opacity(reminder.completed ? 0.5 : 1)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .frame(maxHeight: .infinity)
        .background(Theme.background, in: .rect(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).stroke(Color(hex: reminder.color), lineWidth: 1) }
        .contentShape(.rect)
        .onTapGesture { onPress(reminder) }
        .accessibilityElement(children: .combine)
    }
}

/// An alarm at its time on the timeline; tap it to change or delete it.
struct AlarmBlock: View {
    let alarm: SpacetimeAlarm
    let onPress: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: alarm.repeats ? "alarm.waves.left.and.right.fill" : "alarm.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.alarm)
            Text(alarm.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .frame(maxHeight: .infinity)
        .background(Theme.background, in: .rect(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).stroke(Theme.alarm, lineWidth: 1) }
        .contentShape(.rect)
        .onTapGesture(perform: onPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Alarm, \(alarm.title), \(Dates.formatTime(Dates.date(Date(), atMinute: alarm.minuteOfDay)))")
        .accessibilityAddTraits(.isButton)
    }
}

struct ReminderChip: View {
    let reminder: CalendarReminder
    let onPress: (CalendarReminder) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ReminderCheck(reminder: reminder)
            Text(reminder.title)
                .font(.system(size: 13, weight: .semibold))
                .strikethrough(reminder.completed)
                .opacity(reminder.completed ? 0.5 : 1)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .overlay { RoundedRectangle(cornerRadius: 4).stroke(Color(hex: reminder.color), lineWidth: 1) }
        .contentShape(.rect)
        .onTapGesture { onPress(reminder) }
    }
}

struct NowIndicator: View {
    let hourHeight: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            HStack(spacing: 0) {
                Text(Dates.formatTime(now))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.tint)
                    .frame(width: Timeline.gutter - 4, alignment: .trailing)
                    .padding(.trailing, 4)
                    .background(Theme.background)
                Rectangle().fill(Theme.tint).frame(height: 2)
            }
            .frame(height: 16)
            .offset(y: Timeline.y(minute: Double(Dates.minutesIntoDay(now)), hourHeight: hourHeight) - 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current time, \(Dates.formatTime(now))")
        }
    }
}

/// A horizontal action bar like iOS's edit menu (Cut · Copy · Delete · Duplicate).
struct EditMenu: View {
    struct Item {
        var label: String
        var destructive = false
        var action: () -> Void
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i > 0 { Divider().frame(height: 18) }
                Button(action: item.action) {
                    Text(item.label)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(item.destructive ? Theme.tint : .primary)
                        .padding(.horizontal, 14)
                        .frame(height: Timeline.menuHeight - 8)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: Timeline.menuHeight)
        .glass(in: .capsule, interactive: true)
    }
}
#endif
