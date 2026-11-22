#if os(macOS)
import SwiftUI

/// The collections ("maps") places are saved in.
struct CollectionsView: View {
    @Environment(SpaceStore.self) private var space
    @Environment(CalendarStore.self) private var calendar
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String?] = []

    var body: some View {
        let mapPlaces = Places.all(space: space, calendar: calendar)
        let count = { (id: String) in mapPlaces.filter { Places.isIn($0, collection: id) }.count }
        let reminders = space.collections.filter { $0.id == remindersCollectionId }
        let others = space.collections.filter { $0.id != remindersCollectionId }
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(reminders) { CollectionRow(collection: $0, count: count($0.id)) }
                } footer: {
                    Text("Places with todos: reminders with a location, from any list in the Reminders app. Reminders notifies you when you arrive at or leave them.")
                }
                Section("My Maps") {
                    if others.isEmpty {
                        Text("No collections yet.").foregroundStyle(.secondary)
                    }
                    ForEach(others) { CollectionRow(collection: $0, count: count($0.id)) }
                }
            }
            .navigationTitle("Collections")
            .inlineNavigationTitle()
            .navigationDestination(for: String?.self) { id in
                EditCollectionView(id: id, place: nil)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", role: .confirmIfAvailable) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New collection", systemImage: "plus") { path.append(nil) }
                }
            }
        }
        .tint(Theme.blue)
    }
}

private struct CollectionRow: View {
    let collection: PlaceCollection
    let count: Int

    var body: some View {
        NavigationLink(value: Optional(collection.id)) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: collection.color))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: collection.id == remindersCollectionId ? "bell.fill" : "mappin.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                Text(collection.name).lineLimit(1)
                Spacer()
                Text(String(count)).foregroundStyle(.secondary)
            }
            .frame(minHeight: 40)
        }
    }
}

/// Creates a collection (adding `place` to it, if given), or renames, recolors, or deletes one.
struct EditCollectionView: View {
    let id: String?
    /// A place to add a new collection to.
    let place: MapPlace?

    @Environment(SpaceStore.self) private var space
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = ""
    @State private var loaded = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        let existing = space.collections.first { $0.id == id }
        let isReminders = id == remindersCollectionId
        Form {
            Section {
                TextField("Name", text: $name).focused($nameFocused)
            } footer: {
                if isReminders { Text("The Reminders collection can be renamed but not deleted.") }
            }
            Section("Pin Color") {
                ColorSwatches(value: $color)
            }
            if let existing, !isReminders {
                Section {
                    Button("Delete Collection", role: .destructive) { Task { await confirmDelete(existing) } }
                }
            }
        }
        .navigationTitle(existing?.name ?? "New Collection")
        .inlineNavigationTitle()
        .toolbar {
            if place != nil {
                // Opened straight from a place, with nothing to go back to.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(existing == nil ? "Add" : "Save", role: .confirmIfAvailable) { save(existing) }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .tint(Theme.blue)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = existing?.name ?? ""
            color = existing?.color ?? pinColors[space.collections.count % pinColors.count]
            if existing == nil { nameFocused = true }
        }
    }

    private func save(_ existing: PlaceCollection?) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let existing {
            space.updateCollection(existing.id, name: trimmed, color: color)
        } else {
            let added = space.addCollection(name: trimmed, color: color)
            if let place { Places.add(place, toCollection: added.id, space: space) }
        }
        dismiss()
    }

    private func confirmDelete(_ existing: PlaceCollection) async {
        let count = space.placesOnly(in: existing.id).count
        let choice = await Presenter.confirm(
            title: "Delete “\(existing.name)”?",
            message: count > 0
                ? "This also deletes \(count == 1 ? "a place" : "\(count) places") that \(count == 1 ? "isn’t" : "aren’t") in any other collection."
                : nil,
            options: [.init(label: "Delete", destructive: true)])
        guard choice == 0 else { return }
        dismiss()
        space.deleteCollection(existing.id)
    }
}

/// Picks a saved place's icon, or goes back to its own (from Apple Maps, or a plain pin).
struct IconPickerView: View {
    let placeId: String

    @Environment(SpaceStore.self) private var space
    @Environment(CalendarStore.self) private var calendar
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let place = Places.find(Places.all(space: space, calendar: calendar), id: placeId)
        Group {
            if let place, let saved = place.saved {
                let color = Places.badgeColor(place, collections: space.collections)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        group(place.mapIcon != nil ? "From Apple Maps" : "Default") {
                            cell(icon: nil, shown: place.mapIcon, selected: saved.icon == nil, color: color,
                                 label: place.mapIcon != nil ? "Apple Maps icon" : "Pin", saved: saved)
                        }
                        ForEach(PlaceIcon.groups, id: \.title) { group in
                            self.group(group.title) {
                                ForEach(group.symbols, id: \.self) { symbol in
                                    let icon = PlaceIcon.symbol(symbol)
                                    cell(icon: icon, shown: icon, selected: saved.icon == icon, color: color,
                                         label: symbol, saved: saved)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
                .background(Theme.groupedBackground)
            } else {
                ContentUnavailableView("This place was deleted.", systemImage: "mappin.slash")
            }
        }
        .navigationTitle("Icon")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
        }
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .padding(.top, 20)
            FlowLayout(spacing: 6) { content() }
        }
    }

    private func cell(icon: String?, shown: String?, selected: Bool, color: String, label: String,
                      saved: Place) -> some View {
        Button {
            space.updatePlace(saved.id) { $0.icon = icon }
            dismiss()
        } label: {
            PlaceBadge(icon: shown, color: color, size: 40)
                .frame(width: 52, height: 52)
                .overlay { Circle().stroke(selected ? Color(hex: color) : .clear, lineWidth: 2.5) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
#endif
