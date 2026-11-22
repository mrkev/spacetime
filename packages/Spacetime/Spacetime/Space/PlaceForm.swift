import EventKit
import SwiftUI

let radiusOptions: [(label: String, value: Double)] = [("100 m", 100), ("250 m", 250), ("500 m", 500), ("1 km", 1000)]

/// How far around the current pin (in degrees, about 5 km) search looks first.
private let searchDelta = 0.05

struct LocationState {
    var coordinate: Coordinate?
    var name: String
    var address: String

    /// The name given to a place saved without one.
    var placeName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Dropped Pin" : trimmed
    }
}

/// Where a place is: a search field, a map with a pin, and its name. The pin can be dragged unless
/// `fixed`, and a todo's radius is drawn around it.
struct LocationFields: View {
    @Binding var state: LocationState
    var color: String
    var radius: Double?
    var radiusColor: String?
    var fixed = false

    @State private var query = ""
    @State private var searching = false

    var body: some View {
        Section {
            if !fixed && (state.coordinate == nil || !query.isEmpty) {
                SearchField(placeholder: "Search for a place or address", text: $query, searching: searching,
                            onSubmit: runSearch)
            }
            if let coordinate = state.coordinate {
                PreviewMapView(coordinate: coordinate, color: color, radius: radius, radiusColor: radiusColor,
                               fixed: fixed) { moved in
                    state.coordinate = moved
                    state.address = ""
                    Task { await resolveAddress(moved, overwriteName: false) }
                }
                .frame(height: 180)
                .listRowInsets(EdgeInsets())
            }
        } footer: {
            if state.coordinate != nil {
                if !state.address.isEmpty {
                    Text(state.address)
                } else if !fixed {
                    Text("Drag the pin to adjust the location.")
                }
            } else {
                Text("Search for a place or address, or \(mapPressVerb.lowercased()) the map in Space.")
            }
        }
        .task {
            // Fill in the name and address for a new pin.
            if let coordinate = state.coordinate, state.address.isEmpty, !fixed {
                await resolveAddress(coordinate, overwriteName: state.name.isEmpty)
            }
        }

        if !fixed {
            Section {
                TextField("Place name", text: $state.name)
            }
        }
    }

    private func resolveAddress(_ coordinate: Coordinate, overwriteName: Bool) async {
        guard let described = await PlaceSearch.describe(coordinate), state.coordinate == coordinate else { return }
        state.address = described.address
        if overwriteName { state.name = described.name }
    }

    private func runSearch() {
        let near = state.coordinate.map {
            SearchRegion(latitude: $0.latitude, longitude: $0.longitude, latitudeDelta: searchDelta,
                         longitudeDelta: searchDelta)
        } ?? MapRegionStore.load()
        let text = query
        searching = true
        Task {
            let place = await PlaceSearch.search(text, near: near).first
            searching = false
            guard let place else {
                Presenter.alert(title: "Not Found", message: "Try a different search.")
                return
            }
            query = ""
            state = LocationState(coordinate: place.coordinate, name: place.name, address: place.address)
        }
    }
}

/// Picks any number of collections, in the order they're picked.
struct CollectionPicker: View {
    let collections: [PlaceCollection]
    @Binding var value: [String]
    var footer: String?

    var body: some View {
        Section {
            FlowLayout(spacing: 8) {
                ForEach(collections.filter { $0.id != remindersCollectionId }) { collection in
                    let selected = value.contains(collection.id)
                    Button {
                        if selected { value.removeAll { $0 == collection.id } } else { value.append(collection.id) }
                    } label: {
                        HStack(spacing: 5) {
                            if selected {
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                            }
                            Text(collection.name).font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(selected ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(selected ? Color(hex: collection.color) : .clear, in: .capsule)
                        .overlay { Capsule().stroke(Color(hex: collection.color), lineWidth: 1.5) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Collections")
        } footer: {
            if let footer { Text(footer) }
        }
    }
}

/// What a todo (a location reminder) has besides its place.
struct TodoState {
    var title = ""
    var trigger: ReminderTrigger = .arrive
    var radius: Double = 250
    var notes = ""
}

struct TodoFields: View {
    @Binding var todo: TodoState
    /// Hides the trigger until there's a title, for a form where the todo is optional.
    var optional = false

    var body: some View {
        let showTrigger = !optional || !todo.title.trimmingCharacters(in: .whitespaces).isEmpty
        Section {
            TextField("Remind me to…", text: $todo.title)
            if showTrigger {
                Picker("When", selection: $todo.trigger) {
                    Text("When Arriving").tag(ReminderTrigger.arrive)
                    Text("When Leaving").tag(ReminderTrigger.leave)
                }
                .pickerStyle(.segmented)
                Picker("Radius", selection: $todo.radius) {
                    ForEach(radiusOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("Todo")
        } footer: {
            Text(showTrigger
                 ? "Saved in Reminders, which notifies you when you \(todo.trigger.rawValue)."
                 : "Optional. Saved in Reminders, which notifies you when you get there.")
        }
    }
}

/// Lays out views in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.indices.isEmpty && row.width + spacing + size.width > width {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// The reminder list new todos go into, or nil (after telling the user why) if there isn't one.
@MainActor
func todoList(_ calendar: CalendarStore) async -> EKCalendar? {
    if let list = calendar.defaultReminderList() { return list }
    if calendar.remindersStatus == .granted {
        Presenter.alert(title: "Can’t Save Todo", message: "Add a list in Reminders to save todos.")
    } else {
        let choice = await Presenter.confirm(
            title: "Can’t Save Todo",
            message: "Todos are saved in Reminders. Allow access to Reminders in Settings.",
            options: [.init(label: "Open Settings")])
        if choice == 0 { Presenter.openSettings() }
    }
    return nil
}
