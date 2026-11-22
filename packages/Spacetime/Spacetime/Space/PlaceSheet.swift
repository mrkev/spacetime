import SwiftUI

private enum PlaceRoute: Identifiable {
    case icon, newCollection, addTodo, addEvent, edit
    case todo(LocationReminder)

    var id: String {
        switch self {
        case .icon: "icon"
        case .newCollection: "newCollection"
        case .addTodo: "addTodo"
        case .addEvent: "addEvent"
        case .edit: "edit"
        case .todo(let todo): "todo:\(todo.id)"
        }
    }
}

/// A place's details, in a sheet over the map: its collections (sorted, since the first colors its
/// pin), its todos, and its upcoming events.
struct PlaceSheet: View {
    let id: String

    @Environment(SpaceStore.self) private var space
    @Environment(CalendarStore.self) private var calendar
    @Environment(\.dismiss) private var dismiss
    /// A place's ID changes when it's saved or unsaved, so keep track of where it was. And when its
    /// last todo is checked off an unsaved place is gone, but keep showing it so that can be undone.
    @State private var last: MapPlace?
    /// Todos checked off here, which drop out of the open reminders.
    @State private var done: [LocationReminder] = []
    @State private var route: PlaceRoute?

    var body: some View {
        let mapPlaces = Places.all(space: space, calendar: calendar)
        let live = Places.find(mapPlaces, id: id, near: last?.coordinate)
        let place = live ?? last?.emptied
        Group {
            if let place {
                content(place, live: live)
            } else {
                ContentUnavailableView("This place was deleted.", systemImage: "mappin.slash")
            }
        }
        .onChange(of: live?.signature, initial: true) { if let live { last = live } }
        .sizedSheet(item: $route) { route in
            if let place { destination(route, place: place) }
        }
    }

    @ViewBuilder
    private func destination(_ route: PlaceRoute, place: MapPlace) -> some View {
        switch route {
        case .icon: NavigationStack { IconPickerView(placeId: place.id) }
        case .newCollection: NavigationStack { EditCollectionView(id: nil, place: place) }
        case .addTodo: NavigationStack { AddToReminderView(place: place) }
        case .addEvent: NavigationStack { EventPickerView(place: place) }
        case .edit: NavigationStack { EditPlaceView(place: place) }
        case .todo(let todo): NavigationStack { TodoEditorView(existing: todo, place: place) }
        }
    }

    private func content(_ place: MapPlace, live: MapPlace?) -> some View {
        let inCollections = Places.collections(of: place.collectionIds, in: space.collections)
        let otherCollections = space.collections.filter {
            $0.id != remindersCollectionId && !place.collectionIds.contains($0.id)
        }
        let todos = place.todos + done.filter { d in !place.todos.contains { $0.id == d.id } }
        let isDone = { (todo: LocationReminder) in !place.todos.contains { $0.id == todo.id } }

        return VStack(spacing: 0) {
            header(place)
            List {
                Section {
                    ForEach(inCollections) { collection in
                        Label {
                            Text(collection.name)
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(Color(hex: collection.color))
                                .font(.system(size: 14))
                        }
                        // Taking a place without todos out of its last collection would delete it.
                        .deleteDisabled(inCollections.count == 1 && place.todos.isEmpty)
                    }
                    .onMove { from, to in
                        var ids = inCollections.map(\.id)
                        ids.move(fromOffsets: from, toOffset: to)
                        Places.setCollections(place, ids, space: space)
                    }
                    .onDelete { offsets in
                        let ids = inCollections.enumerated().filter { !offsets.contains($0.offset) }.map(\.element.id)
                        Places.setCollections(place, ids, space: space)
                    }
                    if otherCollections.isEmpty {
                        Button("New Collection…", systemImage: "plus.circle") { route = .newCollection }
                    } else {
                        Menu {
                            ForEach(otherCollections) { collection in
                                Button(collection.name) {
                                    Places.add(place, toCollection: collection.id, space: space)
                                }
                            }
                            Divider()
                            Button("New Collection…", systemImage: "plus") { route = .newCollection }
                        } label: {
                            Label("Add to Collection", systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text("Collections")
                } footer: {
                    if inCollections.count > 1 {
                        Text("The first collection colors the pin. Hold and drag to reorder.")
                    } else if inCollections.isEmpty {
                        Text("Not saved. Without a collection, this place is on the map only while it has todos or upcoming events.")
                    }
                }

                Section("Todos") {
                    ForEach(todos) { todo in
                        HStack(spacing: 12) {
                            Button { toggle(todo, completed: isDone(todo)) } label: {
                                Image(systemName: isDone(todo) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(isDone(todo) ? Theme.blue : Theme.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(todo.title)
                            .accessibilityValue(isDone(todo) ? "Completed" : "Not completed")
                            Button { route = .todo(todo) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(todo.title)
                                        .foregroundStyle(isDone(todo) ? .secondary : .primary)
                                        .lineLimit(2)
                                    Text(LocationReminders.describeTrigger(todo))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onDelete { offsets in deleteTodos(offsets.map { todos[$0] }) }
                    Button("Add to Reminder", systemImage: "plus.circle") { route = .addTodo }
                }

                Section {
                    ForEach(place.events) { event in
                        Button { TimeActions.openEvent(event, calendar: calendar) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(hex: event.color))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title).lineLimit(2)
                                    Text(Places.describeEventTime(event))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    Menu {
                        Button("New Event…", systemImage: "plus") {
                            Task {
                                await TimeActions.createEvent(place: Places.eventLocation(place), calendar: calendar)
                            }
                        }
                        Button("Existing Event…", systemImage: "calendar") { route = .addEvent }
                    } label: {
                        Label("Add to Event", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Events")
                } footer: {
                    Text("Events here in the next \(upcomingDays) days.")
                }

                if let notes = place.saved?.notes {
                    Section("Notes") { Text(notes) }
                }

                Section {
                    Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") {
                        PlaceSearch.openDirections(to: place.coordinate, name: place.name)
                    }
                    if place.saved != nil {
                        Button("Edit Place", systemImage: "pencil") { route = .edit }
                    }
                    if place.saved != nil || !place.todos.isEmpty {
                        Button("Delete Place", systemImage: "trash", role: .destructive) {
                            Task { await confirmDelete(place) }
                        }
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
        .background(Theme.groupedBackground)
    }

    private func header(_ place: MapPlace) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { route = .icon } label: {
                PlaceBadge(icon: place.icon, color: Places.badgeColor(place, collections: space.collections), size: 44)
            }
            .buttonStyle(.plain)
            .disabled(place.saved == nil)
            .accessibilityLabel("Icon")
            .accessibilityHint(place.saved != nil ? "Changes the icon" : "")
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.title2.bold()).lineLimit(2)
                if let address = place.address, !address.isEmpty {
                    Text(address).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Close", systemImage: "xmark", role: .closeIfAvailable) { dismiss() }
                .labelStyle(.iconOnly)
                .glassButtonStyle()
                .buttonBorderShape(.circle)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 4)
    }

    private func toggle(_ todo: LocationReminder, completed: Bool) {
        if !completed {
            done.removeAll { $0.id == todo.id }
            done.append(todo)
        }
        var reminder = todo.reminder
        reminder.completed = completed
        do { try calendar.toggleReminder(reminder) } catch {
            Presenter.showError("Couldn’t Update Todo", error)
        }
    }

    private func deleteTodos(_ removed: [LocationReminder]) {
        done.removeAll { d in removed.contains { $0.id == d.id } }
        do {
            for todo in removed { try calendar.deleteReminder(todo.reminder) }
        } catch {
            Presenter.showError("Couldn’t Delete Todo", error)
        }
    }

    private func confirmDelete(_ place: MapPlace) async {
        let open = place.todos.count
        let choice = await Presenter.confirm(
            title: "Delete “\(place.name)”?",
            message: open > 0 ? "This also deletes its \(open == 1 ? "todo" : "\(open) todos")." : nil,
            options: [.init(label: "Delete", destructive: true)])
        guard choice == 0 else { return }
        dismiss()
        if let saved = place.saved { space.deletePlace(saved.id) }
        do {
            for todo in place.todos { try calendar.deleteReminder(todo.reminder) }
        } catch {
            Presenter.showError("Couldn’t Delete Todos", error)
        }
    }
}
