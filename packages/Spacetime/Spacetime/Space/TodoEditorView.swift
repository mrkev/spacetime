import SwiftUI

/// Makes or edits a todo at a place. A saved place's todos stay where it is; a todo that isn't at a
/// saved place can be moved.
struct TodoEditorView: View {
    var existing: LocationReminder?
    var place: MapPlace?
    /// Shown above the form.
    var header: AnyView?

    @Environment(SpaceStore.self) private var space
    @Environment(CalendarStore.self) private var calendar
    @Environment(\.dismiss) private var dismiss
    @State private var location: LocationState
    @State private var todo: TodoState
    @State private var saving = false
    /// Checking it off applies right away, like in a list. It then drops out of the open reminders, so
    /// it's kept track of here.
    @State private var completed: Bool

    init(existing: LocationReminder?, place: MapPlace?, header: AnyView? = nil) {
        self.existing = existing
        self.place = place
        self.header = header
        let anchor: Coordinate? = existing?.coordinate ?? place?.coordinate
        _location = State(initialValue: LocationState(
            coordinate: anchor, name: existing?.placeName ?? place?.name ?? "",
            address: existing?.address ?? place?.address ?? ""))
        _todo = State(initialValue: existing.map {
            TodoState(title: $0.title, trigger: $0.trigger, radius: $0.radius, notes: $0.notes ?? "")
        } ?? TodoState())
        _completed = State(initialValue: existing?.completed ?? false)
    }

    private var canSave: Bool {
        location.coordinate != nil && !todo.title.trimmingCharacters(in: .whitespaces).isEmpty && !saving
    }

    var body: some View {
        let color = place.map { Places.pinColor($0, collections: space.collections) } ?? space.reminderColor
        Form {
            if let header {
                Section { header }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            TodoFields(todo: $todo)
            LocationFields(state: $location, color: color, radius: todo.radius, radiusColor: space.reminderColor,
                           fixed: place?.saved != nil)
            Section("Notes") {
                TextField("Notes", text: $todo.notes, axis: .vertical).lineLimit(3...)
            }
            if let existing {
                Section {
                    Button(completed ? "Mark as Incomplete" : "Mark as Completed") { toggleCompleted(existing) }
                    Button("Show in Reminders") { TimeActions.showInReminders(existing.id) }
                }
                Section {
                    Button("Delete Todo", role: .destructive) { Task { await confirmDelete(existing) } }
                }
            }
        }
        .navigationTitle(existing == nil ? "Add to Reminder" : "Todo")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(existing == nil ? "Add" : "Done", role: .confirmIfAvailable) { Task { await save() } }
                    .disabled(!canSave)
            }
        }
        .task {
            if existing == nil && calendar.remindersStatus == .undetermined { await calendar.requestAccess() }
        }
    }

    private func save() async {
        guard canSave, let coordinate = location.coordinate else { return }
        let notes = todo.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = LocationReminderInput(
            title: todo.title.trimmingCharacters(in: .whitespaces), placeName: location.placeName,
            address: location.address.isEmpty ? nil : location.address, notes: notes.isEmpty ? nil : notes,
            trigger: todo.trigger, radius: todo.radius, latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            if let existing {
                saving = true
                try LocationReminders.update(existing, input, calendar: calendar)
            } else {
                guard let list = await todoList(calendar) else { return }
                saving = true
                try LocationReminders.create(in: list, input, calendar: calendar)
            }
            dismiss()
        } catch {
            saving = false
            Presenter.showError("Couldn’t Save Todo", error)
        }
    }

    private func toggleCompleted(_ existing: LocationReminder) {
        var reminder = existing.reminder
        reminder.completed = completed
        completed.toggle()
        do { try calendar.toggleReminder(reminder) } catch {
            completed.toggle()
            Presenter.showError("Couldn’t Update Todo", error)
        }
    }

    private func confirmDelete(_ existing: LocationReminder) async {
        let choice = await Presenter.confirm(title: "Delete “\(existing.title)”?",
                                             options: [.init(label: "Delete", destructive: true)])
        guard choice == 0 else { return }
        do {
            try calendar.deleteReminder(existing.reminder)
            dismiss()
        } catch {
            Presenter.showError("Couldn’t Delete Todo", error)
        }
    }
}

/// A reminder at a place: a new one, or one that's already in Reminders.
struct AddToReminderView: View {
    let place: MapPlace
    @State private var mode = Mode.new

    enum Mode { case new, existing }

    var body: some View {
        let header = AnyView(
            Picker("Reminder", selection: $mode) {
                Text("New Reminder").tag(Mode.new)
                Text("Existing Reminder").tag(Mode.existing)
            }
            .pickerStyle(.segmented)
        )
        switch mode {
        case .new: TodoEditorView(existing: nil, place: place, header: header)
        case .existing: ReminderPickerView(place: place, header: header)
        }
    }
}

/// Picks an open reminder to remind you at a place. It lists the ones without a location; search finds
/// ones with a location too, which then move here.
struct ReminderPickerView: View {
    let place: MapPlace
    var header: AnyView?

    @Environment(CalendarStore.self) private var calendar
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var saving = false

    var body: some View {
        let term = query.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = calendar.openReminders.filter { reminder in
            !place.todos.contains { $0.id == reminder.key }
                && (term.isEmpty ? reminder.locatedAlarm == nil : reminder.title.lowercased().contains(term))
        }
        Form {
            if let header {
                Section { header }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                SearchField(placeholder: "Search reminders", text: $query)
                ForEach(shown) { reminder in
                    let located = LocationReminders.from(reminder, meta: nil)
                    PickRow(title: reminder.title,
                            subtitle: [reminder.listTitle, reminder.due.map { Dates.formatRelativeDay($0) },
                                       located?.placeName].compactMap { $0 }.joined(separator: " · "),
                            color: reminder.color) {
                        Task { await pick(reminder) }
                    }
                }
            } footer: {
                if !term.isEmpty {
                    if shown.isEmpty { Text("No reminders match “\(query.trimmingCharacters(in: .whitespaces))”.") }
                } else {
                    Text(shown.isEmpty
                         ? "No reminders without a location. Search to find ones with a location."
                         : "Reminders without a location. Search to find ones with a location too.")
                }
            }
        }
        .navigationTitle("Add to Reminder")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
            if saving {
                ToolbarItem(placement: .confirmationAction) { ProgressView() }
            }
        }
        .task {
            if calendar.remindersStatus == .undetermined { await calendar.requestAccess() }
        }
    }

    private func pick(_ reminder: CalendarReminder) async {
        guard !saving else { return }
        if let located = LocationReminders.from(reminder, meta: nil) {
            let choice = await Presenter.confirm(title: "Move “\(reminder.title)” Here?",
                                                 message: "It reminds you at \(located.placeName) now.",
                                                 options: [.init(label: "Move")])
            guard choice == 0 else { return }
        }
        saving = true
        do {
            let defaults = TodoState()
            try LocationReminders.move(reminder, to: place, name: place.name, address: place.address,
                                       defaults: (defaults.trigger, defaults.radius), calendar: calendar)
            dismiss()
        } catch {
            saving = false
            Presenter.showError("Couldn’t Save Reminder", error)
        }
    }
}

/// Picks an upcoming event to be at a place. It lists the ones without a location; search finds ones
/// with a location too, which then move here.
struct EventPickerView: View {
    let place: MapPlace

    @Environment(CalendarStore.self) private var calendar
    @Environment(\.dismiss) private var dismiss
    @State private var events: [CalendarEvent]?
    @State private var query = ""
    @State private var saving = false

    var body: some View {
        let term = query.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = (events ?? []).filter { event in
            event.editable && !place.events.contains { $0.eventId == event.eventId }
                && (term.isEmpty ? event.location == nil : event.title.lowercased().contains(term))
        }
        Form {
            Section {
                SearchField(placeholder: "Search events", text: $query)
                if events == nil {
                    ProgressView().frame(maxWidth: .infinity)
                }
                ForEach(shown) { event in
                    PickRow(title: event.title,
                            subtitle: [Places.describeEventTime(event),
                                       event.location.map { Places.parseLocationTitle($0).name }]
                                .compactMap { $0 }.joined(separator: " · "),
                            color: event.color) {
                        Task { await pick(event) }
                    }
                }
            } footer: {
                if events != nil {
                    if !term.isEmpty {
                        if shown.isEmpty {
                            Text("No upcoming events match “\(query.trimmingCharacters(in: .whitespaces))”.")
                        }
                    } else {
                        Text(shown.isEmpty
                             ? "No events in the next \(upcomingDays) days without a location. Search to find ones with a location."
                             : "Events in the next \(upcomingDays) days without a location. Search to find ones with a location too.")
                    }
                }
            }
        }
        .navigationTitle("Add to Event")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
            if saving {
                ToolbarItem(placement: .confirmationAction) { ProgressView() }
            }
        }
        .task { events = await calendar.listUpcomingEvents() }
    }

    private func pick(_ event: CalendarEvent) async {
        guard !saving else { return }
        if let location = event.location {
            let choice = await Presenter.confirm(title: "Move “\(event.title)” Here?",
                                                 message: "Its location is \(Places.parseLocationTitle(location).name) now.",
                                                 options: [.init(label: "Move")])
            guard choice == 0 else { return }
        }
        guard let span = await TimeActions.chooseSpan(event, verb: "Save") else { return }
        saving = true
        do {
            try TimeActions.setPlace(Places.eventLocation(place), of: event, span: span, calendar: calendar)
            dismiss()
        } catch {
            saving = false
            Presenter.showError("Couldn’t Save Event", error)
        }
    }
}
