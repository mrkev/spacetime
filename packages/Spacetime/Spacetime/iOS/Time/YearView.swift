#if os(iOS)
import SwiftUI

private let yearsBefore = 10
private let yearsAfter = 10
private let sidePadding: CGFloat = 16
private let gap: CGFloat = 12
private let yearTitleHeight: CGFloat = 56
private let monthTitleHeight: CGFloat = 26
/// About the month view's rows' height, for the month's width, so the zoom between them lines up.
private let dayHeight: CGFloat = 18
private let monthHeight = monthTitleHeight + 6 * dayHeight
private let rowGap: CGFloat = 12
private let yearHeight = yearTitleHeight + 12 + 4 * monthHeight + 3 * rowGap + rowGap

/// The top of the calendar: a scrolling list of years, each a grid of tiny months.
struct YearView: View {
    @Environment(AppModel.self) private var model
    @State private var position: Int?
    private let today = Date()

    /// Opens at `initialMonth`'s year.
    init(initialMonth: Date) {
        let offset = Calendar.current.component(.year, from: initialMonth) - Calendar.current.component(.year, from: Date())
        _position = State(initialValue: min(yearsAfter, max(-yearsBefore, offset)))
    }

    var body: some View {
        let nav = model.time
        let transition = nav.transition
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(-yearsBefore...yearsAfter, id: \.self) { offset in
                        YearItem(year: Calendar.current.component(.year, from: today) + offset, today: today,
                                 zoom: transition.flatMap { $0.isZoom ? ZoomTarget(month: $0.month, transition: $0.id) : nil },
                                 onZoomMonthFrame: { frame in
                                     if let transition { nav.report(.year, frame, transition: transition.id) }
                                 }) { month in
                            nav.show(.month, month: month)
                        }
                        .frame(height: yearHeight)
                    }
                }
                .scrollTargetLayout()
                .noScrollToTop()
            }
            .scrollPosition(id: $position, anchor: .top)
            .scrollIndicators(.hidden)
            .background(Theme.background)
            .onChange(of: model.todayRequests) {
                guard nav.isShowing(.year) else { return }
                // Through the proxy, which scrolls even when `position` is already 0: the tab bar scrolls
                // to the top when Time is tapped again, without changing `position` until it's done.
                withAnimation { proxy.scrollTo(0, anchor: .top) }
            }
        }
    }
}

private struct ZoomTarget {
    var month: Date
    var transition: UUID
}

private struct YearItem: View {
    let year: Int
    let today: Date
    /// The month a zoom to or from the month view is on, whose frame to report.
    let zoom: ZoomTarget?
    let onZoomMonthFrame: (CGRect) -> Void
    let onPressMonth: (Date) -> Void

    var body: some View {
        let isThisYear = year == Calendar.current.component(.year, from: today)
        VStack(alignment: .leading, spacing: 0) {
            Text(String(year))
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(isThisYear ? Theme.tint : .primary)
                .frame(height: yearTitleHeight, alignment: .bottom)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { Divider() }
                .accessibilityAddTraits(.isHeader)
            Grid(horizontalSpacing: gap, verticalSpacing: rowGap) {
                ForEach(0..<4, id: \.self) { row in
                    GridRow {
                        ForEach(0..<3, id: \.self) { column in
                            monthButton(row * 3 + column + 1)
                        }
                    }
                }
            }
            .padding(.top, 12)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, sidePadding)
    }
}

extension YearItem {
    fileprivate func monthButton(_ number: Int) -> some View {
        let month = Dates.date(year: year, month: number, day: 1)
        let zooming = zoom.map { Dates.monthKey($0.month) == Dates.monthKey(month) } ?? false
        return Button { onPressMonth(month) } label: {
            MiniMonth(month: month, today: today, transition: zooming ? zoom?.transition : nil,
                      onFrame: onZoomMonthFrame)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Dates.formatMonthYear(month))
    }
}

private struct MiniMonth: View {
    let month: Date
    let today: Date
    /// The transition to report the frame of the grid of days for.
    let transition: UUID?
    let onFrame: (CGRect) -> Void

    var body: some View {
        let isThisMonth = Dates.monthKey(month) == Dates.monthKey(today)
        let leading = Dates.weekday(month)
        let total = Dates.daysInMonth(month)
        let todayNumber = isThisMonth ? Calendar.current.component(.day, from: today) : nil
        VStack(alignment: .leading, spacing: 0) {
            Text(Dates.formatShortMonth(month))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(isThisMonth ? Theme.tint : .primary)
                .frame(height: monthTitleHeight, alignment: .topLeading)
            Canvas { context, size in
                let dayWidth = size.width / 7
                for day in 1...total {
                    let index = leading + day - 1
                    let center = CGPoint(x: (CGFloat(index % 7) + 0.5) * dayWidth,
                                         y: (CGFloat(index / 7) + 0.5) * dayHeight)
                    let isToday = day == todayNumber
                    if isToday {
                        let circle = CGRect(x: center.x - dayHeight / 2, y: center.y - dayHeight / 2,
                                            width: dayHeight, height: dayHeight)
                        context.fill(Path(ellipseIn: circle), with: .color(Theme.tint))
                    }
                    context.draw(
                        Text(String(day)).font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isToday ? Color.white : Color.primary),
                        at: center)
                }
            }
            .frame(height: 6 * dayHeight)
            .reportsFrame(for: transition, onFrame)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}
#endif
