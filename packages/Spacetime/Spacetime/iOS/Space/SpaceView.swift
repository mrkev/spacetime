#if os(iOS)
import MapKit
import SwiftUI

private let allFilter = "all"
/// The filter for places with upcoming events.
private let upcomingFilter = "upcoming"
private let userDelta = 0.03

/// A place to open in a sheet, with the ID it had when it was opened.
struct PlaceRequest: Identifiable {
    var id: String
}

/// The new-place form, at a spot on the map.
struct NewPlaceRequest: Identifiable {
    let id = UUID()
    var coordinate: Coordinate
    var collectionId: String?
}

/// A map of your saved places, with search and collection filters.
struct SpaceView: View {
    @Environment(AppModel.self) private var model
    @Environment(SpaceStore.self) private var space
    @Environment(CalendarStore.self) private var calendar
    @Environment(LocationModel.self) private var location
    @Environment(MapLayers.self) private var layers

    @State private var controller = MapController()
    @State private var filter = allFilter
    @State private var query = ""
    @State private var completer = PlaceCompleter()
    @State private var searching = false
    @State private var results: [PlaceResult] = []
    @State private var selectedResult = 0
    /// The place whose pin is selected. Its pill opens it.
    @State private var selectedPlaceId: String?
    /// A point of interest on Apple's map (a shop, a park) that was tapped, to save as a place.
    /// `at` is where MapKit put it; `place` is the place on the map there, or else an unsaved one.
    @State private var poi: (at: Coordinate, place: MapPlace)?
    @State private var notFound = false
    @State private var initialRegion: SearchRegion?
    /// Searches prefer places in view.
    @State private var visibleRegion: SearchRegion?
    @State private var centeredOnUser = false
    @State private var openPlace: PlaceRequest?
    @State private var newPlace: NewPlaceRequest?
    @State private var showingCollections = false
    @State private var showingFilters = false
    @State private var thumbnails = MapThumbnails()
    @State private var photos: PhotosRequest?
    /// Edit Collections was chosen in the filters' popover; the sheet opens once it's gone.
    @State private var editCollectionsAfterFilters = false
    @FocusState private var searchFocused: Bool
    /// Whether the toolbar's search field is open: taking the whole toolbar, with a button to close it.
    /// A search closes it, bringing back Time and Here; the field keeps the text and its clear button.
    @State private var searchPresented = false
    /// The search's text, while the field closes. Closing it empties it, as Cancel does, at the end of
    /// its animation, so the results are kept and the text is put back after.
    @State private var closingSearch: String?

    /// Opens the map at `region`, where it was last left.
    init(region: SearchRegion?) {
        _initialRegion = State(initialValue: region)
        _visibleRegion = State(initialValue: region)
    }

    var body: some View {
        let mapPlaces = Places.all(space: space, calendar: calendar)
        let visible = places(in: filter, mapPlaces)
        let selected = selectedPlace(visible: visible, mapPlaces: mapPlaces)
        let resultPlaces = results.map { placeAt($0.coordinate, name: $0.name, address: $0.address, mapPlaces) }
        // Todos' geofences, for the selected place or when looking at all of them.
        let fenced = filter == remindersCollectionId ? visible : selected.map { [$0] } ?? []

        NavigationStack {
            content(mapPlaces: mapPlaces, visible: visible, selected: selected, resultPlaces: resultPlaces,
                    fenced: fenced)
                .toolbar(.hidden, for: .navigationBar)
                .toolbar { bottomToolbar }
                .searchable(text: $query, isPresented: $searchPresented, placement: .toolbar, prompt: "Search for a place or address")
                .searchFocused($searchFocused)
                .autocorrectionDisabled()
                .onSubmit(of: .search) {
                    let text = query
                    let near = visibleRegion
                    runSearch { await PlaceSearch.search(text, near: near) }
                }
        }
        .task {
            location.requestAccess()
            await centerOnUser()
        }
        .onChange(of: location.granted) { Task { await centerOnUser() } }
        .onChange(of: model.hereRequests) { Task { await goToMyLocation() } }
        .onChange(of: query) { _, text in
            if text.isEmpty && closingSearch != nil { return }
            notFound = false
            if text.isEmpty { clearSearch() } else { completer.update(text, near: visibleRegion) }
        }
        .sheet(item: $openPlace) { request in
            PlaceSheet(id: request.id)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $newPlace) { request in
            NavigationStack { NewPlaceView(coordinate: request.coordinate, collectionId: request.collectionId) }
        }
        .sheet(isPresented: $showingCollections) {
            CollectionsView()
        }
        .sheet(item: $photos) { request in
            PhotosSheet(request: request)
        }
        .onAppear { thumbnails.contactData = { [layers] in layers.contactThumbnails[$0] } }
    }

    // MARK: Photos and contacts

    /// Photos and contacts, under places: they're drawn smaller and give way to places' pins.
    private var layerPins: [MapPin] {
        layers.photoGroups.map { group in
            MapPin(id: group.id, kind: .photos, coordinate: group.coordinate, color: Hex.blue, glyph: nil,
                   name: group.photoIds.count == 1 ? "1 photo" : "\(group.photoIds.count) photos",
                   count: group.photoIds.count, imageId: group.photoIds.first)
        } + layers.contactAddresses.compactMap { address in
            address.coordinate.map {
                MapPin(id: address.id, kind: .contact, coordinate: $0, color: Hex.blue, glyph: nil, name: address.name,
                       imageId: address.contactId)
            }
        }
    }

    /// Opens photos in a sheet, and a contact's card; contacts spread apart are zoomed in on, and
    /// several at one address picked from.
    private func openThumbnails(_ pins: [MapPin]) {
        guard let first = pins.first else { return }
        if first.kind == .photos {
            let ids = Set(pins.map(\.id))
            let groups = layers.photoGroups.filter { ids.contains($0.id) }
            guard !groups.isEmpty else { return }
            let latitude = groups.map(\.coordinate.latitude).reduce(0, +) / Double(groups.count)
            let longitude = groups.map(\.coordinate.longitude).reduce(0, +) / Double(groups.count)
            photos = PhotosRequest(photoIds: groups.flatMap(\.photoIds),
                                   coordinate: Coordinate(latitude: latitude, longitude: longitude))
            return
        }
        if pins.count == 1, let contactId = first.imageId {
            ContactCards.open(contactId)
        } else if pins.allSatisfy({ Geo.distanceMeters($0.coordinate, first.coordinate) < 50 }) {
            Task { await ContactCards.choose(pins) }
        } else {
            controller.focus(on: pins.map(\.coordinate), padding: focusPadding)
        }
    }

    // MARK: State

    private func places(in id: String, _ mapPlaces: [MapPlace]) -> [MapPlace] {
        switch id {
        case allFilter: mapPlaces
        case upcomingFilter: mapPlaces.filter { !$0.events.isEmpty }
        default: mapPlaces.filter { Places.isIn($0, collection: id) }
        }
    }

    /// The selected pin or point of interest. Once a point of interest is saved, it's found on the map.
    private func selectedPlace(visible: [MapPlace], mapPlaces: [MapPlace]) -> MapPlace? {
        if let id = selectedPlaceId, let place = visible.first(where: { $0.id == id }) { return place }
        guard let poi else { return nil }
        return Places.find(mapPlaces, id: poi.place.id, near: poi.at) ?? poi.place
    }

    /// A spot found on the map stands for the place on the map there, or else is an unsaved place.
    private func placeAt(_ at: Coordinate, name: String, address: String?, mapIcon: String? = nil,
                         _ mapPlaces: [MapPlace]) -> MapPlace {
        mapPlaces.first { Geo.distanceMeters($0, at) <= linkRadius }
            ?? Places.unsavedPlace(at: at, name: name, address: address, mapIcon: mapIcon)
    }

    private func handlePoi(_ event: PoiEvent, _ mapPlaces: [MapPlace]) {
        switch event {
        case .deselected(let at):
            if poi?.at == at { poi = nil }
        case .selected(let name, let at, let icon):
            let place = placeAt(at, name: name, address: nil, mapIcon: icon.flatMap { PlaceIcon.save($0) }, mapPlaces)
            poi = (at, place)
            guard place.saved == nil && place.todos.isEmpty && place.events.isEmpty else { return }
            Task {
                guard let described = await PlaceSearch.describe(at), let current = poi, current.at == at else { return }
                var updated = current.place
                updated.address = described.address
                poi = (at, updated)
            }
        }
    }

    private var focusPadding: UIEdgeInsets {
        UIEdgeInsets(top: 140, left: 60, bottom: 200, right: 60)
    }

    private func selectFilter(_ id: String, _ mapPlaces: [MapPlace]) {
        filter = id
        controller.focus(on: places(in: id, mapPlaces).map(\.coordinate), padding: focusPadding)
    }

    private func open(_ place: MapPlace) {
        // Keep the pin in view above the sheet, which covers the bottom half.
        if let region = controller.region {
            controller.show(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: place.latitude - region.latitudeDelta / 4,
                                               longitude: place.longitude),
                span: MKCoordinateSpan(latitudeDelta: region.latitudeDelta, longitudeDelta: region.longitudeDelta)))
        }
        // An unsaved point of interest isn't on the map, so the sheet couldn't find it otherwise.
        Places.remember(place)
        openPlace = PlaceRequest(id: place.id)
    }

    private func addPlace(at coordinate: Coordinate) {
        newPlace = NewPlaceRequest(coordinate: coordinate,
                                   collectionId: filter == allFilter || filter == upcomingFilter ? nil : filter)
    }

    /// Centers on the user once, when the map first opens.
    private func centerOnUser() async {
        guard !centeredOnUser, location.granted, let position = await location.currentLocation() else { return }
        centeredOnUser = true
        controller.show(MKCoordinateRegion(center: position.coordinate,
                                           span: MKCoordinateSpan(latitudeDelta: userDelta, longitudeDelta: userDelta)),
                        animated: false)
    }

    private func goToMyLocation() async {
        guard let position = await location.freshLocation() else {
            if !location.granted { location.requestAccess() }
            return
        }
        controller.focus(on: [Coordinate(position.coordinate)], padding: focusPadding)
    }

    /// The map, with the filters over its top and the selected place, search suggestions, or results
    /// over its bottom, above the toolbar.
    private func content(mapPlaces: [MapPlace], visible: [MapPlace], selected: MapPlace?,
                         resultPlaces: [MapPlace], fenced: [MapPlace]) -> some View {
        ZStack {
            SpaceMapView(
                pins: visible.map { place in
                    MapPin(id: place.id, kind: .place, coordinate: place.coordinate,
                           color: Places.pinColor(place, collections: space.collections), glyph: place.icon,
                           name: place.name)
                } + results.enumerated().map { i, found in
                    MapPin(id: "result:\(i)", kind: .result(i), coordinate: found.coordinate, color: Hex.blue,
                           glyph: nil, name: found.name)
                } + layerPins,
                fences: fenced.flatMap(\.todos).map {
                    MapFence(id: $0.id, coordinate: $0.coordinate, radius: $0.radius, color: space.reminderColor)
                },
                showsUserLocation: location.granted,
                initialRegion: initialRegion,
                controller: controller,
                onSelectPin: { pin in
                    switch pin.kind {
                    case .place: selectedPlaceId = pin.id
                    case .result(let i): withAnimation { selectedResult = i }
                    case .photos, .contact: break
                    }
                },
                onDeselectPin: { pin in
                    if pin.kind == .place && selectedPlaceId == pin.id { selectedPlaceId = nil }
                },
                onPoi: { handlePoi($0, mapPlaces) },
                onLongPress: { addPlace(at: $0) },
                onRegionChange: { region in
                    visibleRegion = region
                    space.saveMapRegion(region)
                },
                onTap: { searchFocused = false },
                thumbnails: thumbnails,
                onSelectThumbnails: openThumbnails)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                filterButton(mapPlaces)
                Spacer()
                bottom(selected: selected, resultPlaces: resultPlaces)
            }
        }
    }

    /// The switch to the calendar, the search field, and Here, laid out like the calendar's toolbar.
    @ToolbarContentBuilder
    private var bottomToolbar: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Button("Time", systemImage: "calendar") { model.switchTab() }
                .accessibilityHint("Shows the calendar")
        }
        // Spacers keep the buttons apart from the search field, which they'd otherwise share a capsule with.
        ToolbarSpacer(.fixed, placement: .bottomBar)
        DefaultToolbarItem(kind: .search, placement: .bottomBar)
        ToolbarSpacer(.fixed, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button("Here", systemImage: "location.fill") { model.goHere() }
        }
    }

    private func runSearch(_ search: @escaping () async -> [PlaceResult]) {
        searchFocused = false
        if searchPresented {
            let text = query
            closingSearch = text
            searchPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                closingSearch = nil
                if query.isEmpty { query = text }
            }
        }
        searching = true
        Task {
            let found = await search()
            searching = false
            results = found
            selectedResult = 0
            notFound = found.isEmpty
            controller.focus(on: found.map(\.coordinate), padding: focusPadding)
        }
    }

    private func clearSearch() {
        if !query.isEmpty { query = "" }
        completer.clear()
        results = []
        notFound = false
    }

    // MARK: Views

    private func filterOptions(_ mapPlaces: [MapPlace]) -> [FilterOption] {
        [
            FilterOption(id: allFilter, label: "All", count: mapPlaces.count, icon: "mappin.and.ellipse"),
            FilterOption(id: upcomingFilter, label: "Upcoming", count: places(in: upcomingFilter, mapPlaces).count,
                         color: Hex.tint, icon: "calendar"),
        ] + space.collections.map { collection in
            FilterOption(id: collection.id, label: collection.name,
                         count: places(in: collection.id, mapPlaces).count, color: collection.color,
                         icon: collection.id == remindersCollectionId ? "bell.fill" : nil)
        }
    }

    /// Which places the map shows, as one button that opens the list of filters.
    private func filterButton(_ mapPlaces: [MapPlace]) -> some View {
        let options = filterOptions(mapPlaces)
        let current = options.first { $0.id == filter } ?? options[0]
        return HStack {
            Button { showingFilters = true } label: {
                HStack(spacing: 6) {
                    current.symbol
                    Text(current.label).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(String(current.count))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glass(in: .capsule, interactive: true)
            .accessibilityLabel("Showing \(current.label)")
            .accessibilityHint("Chooses which places the map shows")
            .popover(isPresented: $showingFilters, arrowEdge: .top) {
                FilterList(options: options, selected: filter) { id in
                    showingFilters = false
                    selectFilter(id, mapPlaces)
                } edit: {
                    editCollectionsAfterFilters = true
                    showingFilters = false
                }
                .environment(layers)
                .presentationCompactAdaptation(.popover)
                .onDisappear {
                    guard editCollectionsAfterFilters else { return }
                    editCollectionsAfterFilters = false
                    showingCollections = true
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func bottom(selected: MapPlace?, resultPlaces: [MapPlace]) -> some View {
        VStack(spacing: 8) {
            if searchFocused && !completer.suggestions.isEmpty && !query.isEmpty {
                suggestions.padding(.horizontal, 20)
            } else if let selected {
                PlaceCard(place: selected, collections: space.collections) { open(selected) }
                    .padding(.horizontal, 20)
            } else if !resultPlaces.isEmpty {
                resultCards(resultPlaces)
            } else if searching {
                ProgressView()
                    .padding(10)
                    .glass(in: .circle)
            } else if notFound {
                Text("No results for “\(query.trimmingCharacters(in: .whitespaces))”")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glass(in: .capsule)
            }
        }
        .padding(.bottom, 8)
    }

    /// Search results' cards, side by side, with the ones on either side peeking in. Swiping to one selects its pin.
    private func resultCards(_ places: [MapPlace]) -> some View {
        // Cards are as wide as the space between the margins, so with several, the cards on either side
        // peek into them. Scrolling one just into view lines it up with the margins, so the position
        // has no anchor: centering one measured the width while the search field was still closing,
        // and put the first card a margin to the right.
        let margin: CGFloat = places.count > 1 ? 28 : 20
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                ForEach(places.indices, id: \.self) { i in
                    PlaceCard(place: places[i], collections: space.collections) { open(places[i]) }
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, margin, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: Binding<Int?>(
            get: { selectedResult },
            set: { i in
                guard let i, i != selectedResult else { return }
                selectedResult = i
                controller.select(pinId: "result:\(i)")
            }))
        .scrollIndicators(.hidden)
        .scrollEdgeEffectHidden(true, for: .all)
        .scrollClipDisabled()
        // A horizontal scroll view takes all the height it's offered.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var suggestions: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(completer.suggestions.enumerated()), id: \.element.id) { i, suggestion in
                    if i > 0 { Divider() }
                    Button {
                        query = suggestion.title
                        runSearch { await PlaceSearch.search(suggestion) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title).font(.system(size: 16, weight: .medium)).lineLimit(1)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 320)
        .fixedSize(horizontal: false, vertical: true)
        .glass(in: .rect(cornerRadius: 22))
    }
}

/// A place at the bottom of the map, drawn like the top of a sheet, which it opens into: tap it or drag
/// it up.
private struct PlaceCard: View {
    let place: MapPlace
    let collections: [PlaceCollection]
    let open: () -> Void
    /// How far it's been dragged: it follows the finger up, and resists going down.
    @State private var lift: CGFloat = 0

    var body: some View {
        Button(action: open) { card }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the place")
            .accessibilityIdentifier("placeCard")
            .offset(y: lift)
            .onVerticalDrag { drag in
                switch drag.state {
                case .began, .changed:
                    lift = drag.translation < 0 ? drag.translation * 0.5 : drag.translation * 0.1
                case .ended:
                    if drag.translation < -40 || (drag.translation < 0 && drag.velocity < -500) { open() }
                    withAnimation(.spring(duration: 0.3)) { lift = 0 }
                case .cancelled:
                    withAnimation(.spring(duration: 0.3)) { lift = 0 }
                }
            }
    }

    private var card: some View {
        HStack(spacing: 12) {
            PlaceBadge(icon: place.icon, color: Places.badgeColor(place, collections: collections))
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.headline).lineLimit(1)
                Text(Places.describe(place, collections: collections))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .padding(.top, 4)
        .overlay(alignment: .top) {
            Capsule().fill(Theme.tertiaryText).frame(width: 36, height: 5).padding(.top, 6)
        }
        .contentShape(.rect)
        .glass(in: .rect(cornerRadius: 22), interactive: true)
    }
}

/// A choice of which places the map shows: all of them, those with upcoming events, or a collection's.
private struct FilterOption: Identifiable {
    var id: String
    var label: String
    var count: Int
    var color: String?
    /// A collection without one has a dot of its color.
    var icon: String?

    @ViewBuilder
    var symbol: some View {
        let tint = color.map { Color(hex: $0) } ?? .primary
        if let icon {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint)
        } else {
            Circle().fill(tint).frame(width: 10, height: 10)
        }
    }
}

/// The filters, in the filter button's popover.
private struct FilterList: View {
    let options: [FilterOption]
    let selected: String
    let select: (String) -> Void
    let edit: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(options) { option in
                    Button { select(option.id) } label: {
                        HStack(spacing: 10) {
                            option.symbol.frame(width: 22)
                            Text(option.label).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(String(option.count)).foregroundStyle(.secondary).monospacedDigit()
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                                .opacity(option.id == selected ? 1 : 0)
                        }
                        .font(.system(size: 16))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.label)
                    .accessibilityValue(option.count == 1 ? "1 place" : "\(option.count) places")
                    .accessibilityAddTraits(option.id == selected ? .isSelected : [])
                }
                Divider().padding(.vertical, 4)
                Button(action: edit) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.up.fill").font(.system(size: 13)).frame(width: 22)
                        Text("Edit Collections")
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Divider().padding(.vertical, 4)
                ForEach(MapLayer.allCases, id: \.self) { layer in
                    MapLayerToggle(layer: layer)
                        .font(.system(size: 16))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                }
            }
            .padding(.vertical, 6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 280)
        .frame(maxHeight: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
