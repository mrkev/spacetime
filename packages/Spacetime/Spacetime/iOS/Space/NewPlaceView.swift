#if os(iOS)
import SwiftUI

/// Saves a place in collections, adds a todo there, or both.
struct NewPlaceView: View {
    @Environment(SpaceStore.self) private var space
    @Environment(CalendarStore.self) private var calendar
    @Environment(\.dismiss) private var dismiss
    @State private var location: LocationState
    @State private var collectionIds: [String] = []
    @State private var todo = TodoState()
    @State private var notes = ""
    @State private var saving = false
    @State private var pickedInitialCollection = false
    private let initialCollectionId: String?

    /// `collectionId` is the collection the map is showing, which the place starts out in.
    init(coordinate: Coordinate?, collectionId: String?, name: String = "", address: String = "") {
        _location = State(initialValue: LocationState(coordinate: coordinate, name: name, address: address))
        initialCollectionId = collectionId
    }

    private var hasTodo: Bool { !todo.title.trimmingCharacters(in: .whitespaces).isEmpty }
    private var canSave: Bool { location.coordinate != nil && (!collectionIds.isEmpty || hasTodo) && !saving }

    var body: some View {
        let color = Places.collections(of: collectionIds, in: space.collections).first?.color ?? space.reminderColor
        Form {
            LocationFields(state: $location, color: color, radius: hasTodo ? todo.radius : nil,
                           radiusColor: space.reminderColor)
            CollectionPicker(collections: space.collections, value: $collectionIds,
                             footer: collectionIds.isEmpty
                                 ? "In no collection, the place stays on the map only until its todos are done." : nil)
            TodoFields(todo: $todo, optional: true)
            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...)
            }
        }
        .navigationTitle("New Place")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", role: .confirm) { Task { await save() } }.disabled(!canSave)
            }
        }
        .onAppear {
            // From the Reminders collection, start with just a todo.
            guard !pickedInitialCollection else { return }
            pickedInitialCollection = true
            guard initialCollectionId != remindersCollectionId else { return }
            let initial = space.collections.first { $0.id == initialCollectionId }
                ?? space.collections.first { $0.id != remindersCollectionId }
            collectionIds = initial.map { [$0.id] } ?? []
        }
        .onChange(of: hasTodo) { _, needed in
            // Ask for access to Reminders as soon as a todo is being made.
            if needed && calendar.remindersStatus == .undetermined { Task { await calendar.requestAccess() } }
        }
    }

    private func save() async {
        guard canSave, let coordinate = location.coordinate else { return }
        let name = location.placeName
        let address = location.address.isEmpty ? nil : location.address
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = !collectionIds.isEmpty
        if hasTodo {
            guard let list = await todoList(calendar) else { return }
            saving = true
            do {
                try LocationReminders.create(
                    in: list,
                    LocationReminderInput(
                        title: todo.title.trimmingCharacters(in: .whitespaces), placeName: name, address: address,
                        // Notes go on the place if there is one.
                        notes: !saved && !trimmedNotes.isEmpty ? trimmedNotes : nil,
                        trigger: todo.trigger, radius: todo.radius, latitude: coordinate.latitude,
                        longitude: coordinate.longitude),
                    calendar: calendar)
            } catch {
                saving = false
                Presenter.showError("Couldn’t Save Todo", error)
                return
            }
        }
        if saved {
            space.addPlace(PlaceInput(name: name, address: address, notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                                      latitude: coordinate.latitude, longitude: coordinate.longitude,
                                      collectionIds: collectionIds))
        }
        dismiss()
    }
}

/// Edits where a saved place is, its name, and its notes. Its todos move with it.
struct EditPlaceView: View {
    let place: MapPlace

    @Environment(SpaceStore.self) private var space
    @Environment(CalendarStore.self) private var calendar
    @Environment(\.dismiss) private var dismiss
    @State private var location: LocationState
    @State private var notes: String
    @State private var saving = false

    init(place: MapPlace) {
        self.place = place
        _location = State(initialValue: LocationState(coordinate: place.coordinate, name: place.name,
                                                      address: place.address ?? ""))
        _notes = State(initialValue: place.saved?.notes ?? "")
    }

    var body: some View {
        Form {
            LocationFields(state: $location, color: Places.pinColor(place, collections: space.collections))
            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...)
            }
        }
        .navigationTitle("Edit Place")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", role: .confirm, action: save).disabled(location.coordinate == nil || saving)
            }
        }
    }

    private func save() {
        guard let coordinate = location.coordinate, let saved = place.saved, !saving else { return }
        let name = location.placeName
        let address = location.address.isEmpty ? nil : location.address
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        space.updatePlace(saved.id) {
            $0.name = name
            $0.address = address
            $0.latitude = coordinate.latitude
            $0.longitude = coordinate.longitude
            $0.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        }
        let moved = name != place.name || address != place.address || coordinate != place.coordinate
        if moved && !place.todos.isEmpty {
            saving = true
            do {
                try Places.syncTodos(place.todos, name: name, address: address, at: coordinate, calendar: calendar)
            } catch {
                Presenter.showError("Couldn’t Update Todos", error)
            }
        }
        dismiss()
    }
}
#endif
