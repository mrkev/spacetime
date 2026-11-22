import SwiftUI

/// Picks the place for an event: a saved one, or any place or address from search.
struct EventPlaceView: View {
    let event: CalendarEvent
    let span: Span

    @Environment(CalendarStore.self) private var calendar
    @Environment(SpaceStore.self) private var space
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var completer = PlaceCompleter()
    @State private var searching = false
    @State private var saving = false
    private let near = MapRegionStore.load()

    var body: some View {
        let saved = Places.all(space: space, calendar: calendar)
            .filter { $0.saved != nil }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        Form {
            Section {
                SearchField(placeholder: "Search for a place or address", text: $query, searching: searching,
                            autoFocus: saved.isEmpty) {
                    Task { await pick { await PlaceSearch.search(query, near: near) } }
                }
                if !query.isEmpty {
                    ForEach(completer.suggestions) { suggestion in
                        PickRow(title: suggestion.title, subtitle: suggestion.subtitle) {
                            Task { await pick { await PlaceSearch.search(suggestion) } }
                        }
                    }
                }
            } footer: {
                if let location = event.location { Text("Now: \(location.replacingOccurrences(of: "\n", with: ", "))") }
            }
            if query.isEmpty && !saved.isEmpty {
                Section("Saved Places") {
                    ForEach(saved) { place in
                        PickRow(title: place.name,
                                subtitle: Places.collections(of: place.collectionIds, in: space.collections)
                                    .map(\.name).joined(separator: ", "),
                                color: Places.pinColor(place, collections: space.collections),
                                checked: event.place.map { Geo.distanceMeters($0, place) <= linkRadius } ?? false) {
                            save(Places.eventLocation(place))
                        }
                    }
                }
            }
            if query.isEmpty && event.location != nil {
                Section {
                    Button("Remove Location", role: .destructive) { save(nil) }
                }
            }
        }
        .navigationTitle(event.title)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
            if saving {
                ToolbarItem(placement: .confirmationAction) { ProgressView() }
            }
        }
        .onChange(of: query) { _, text in completer.update(text, near: near) }
    }

    private func pick(_ search: () async -> [PlaceResult]) async {
        searching = true
        let result = await search().first
        searching = false
        guard let result else {
            Presenter.alert(title: "Not Found", message: "Try a different search.")
            return
        }
        save(Places.eventLocation(name: result.name, address: result.address, at: result))
    }

    private func save(_ location: EventLocation?) {
        guard !saving else { return }
        saving = true
        do {
            try TimeActions.setPlace(location, of: event, span: span, calendar: calendar)
            dismiss()
        } catch {
            saving = false
            Presenter.showError("Couldn’t Save Event", error)
        }
    }
}
