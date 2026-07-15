import SwiftUI
import UIKit

enum BrowseRoute: Hashable, Codable {
    case place(UUID)
    case room(UUID)
    case area(UUID)
    case container(UUID)
    case thing(UUID)
}

enum BrowsePathRestorer {
    static func path(
        to destination: BrowseRoute?,
        in places: [PlaceSnapshot]
    ) -> [BrowseRoute]? {
        guard let destination else { return [] }

        switch destination {
        case .place(let placeID):
            guard activePlace(id: placeID, in: places) != nil else { return nil }
            return [.place(placeID)]
        case .room(let roomID):
            guard
                let place = places.first(where: { place in
                    place.archivedAt == nil && place.activeRooms.contains { $0.id == roomID }
                })
            else { return nil }
            return [.place(place.id), .room(roomID)]
        case .area(let areaID):
            guard
                let place = places.first(where: { place in
                    place.archivedAt == nil && place.activeAreas.contains { $0.id == areaID }
                }),
                let area = place.activeAreas.first(where: { $0.id == areaID })
            else { return nil }
            return [.place(place.id), .room(area.roomID), .area(areaID)]
        case .container(let containerID):
            guard let place = activePlace(containingContainer: containerID, in: places) else {
                return nil
            }
            return containerPath(to: containerID, in: place)
        case .thing(let thingID):
            guard
                let place = places.first(where: { place in
                    place.archivedAt == nil && place.activeThings.contains { $0.id == thingID }
                }),
                let thing = place.activeThings.first(where: { $0.id == thingID }),
                let homePath = path(to: thing.home, in: place)
            else { return nil }
            return homePath + [.thing(thingID)]
        }
    }

    private static func activePlace(id: UUID, in places: [PlaceSnapshot]) -> PlaceSnapshot? {
        places.first { $0.id == id && $0.archivedAt == nil }
    }

    private static func activePlace(
        containingContainer containerID: UUID,
        in places: [PlaceSnapshot]
    ) -> PlaceSnapshot? {
        places.first { place in
            place.archivedAt == nil && place.activeContainers.contains { $0.id == containerID }
        }
    }

    private static func path(
        to home: ThingSnapshotHome,
        in place: PlaceSnapshot
    ) -> [BrowseRoute]? {
        switch home {
        case .room(let roomID):
            guard place.activeRooms.contains(where: { $0.id == roomID }) else { return nil }
            return [.place(place.id), .room(roomID)]
        case .area(let areaID):
            guard let area = place.activeAreas.first(where: { $0.id == areaID }) else { return nil }
            return [.place(place.id), .room(area.roomID), .area(areaID)]
        case .container(let containerID):
            return containerPath(to: containerID, in: place)
        }
    }

    private static func containerPath(
        to containerID: UUID,
        in place: PlaceSnapshot
    ) -> [BrowseRoute]? {
        guard place.activeContainers.contains(where: { $0.id == containerID }) else { return nil }

        var currentID = containerID
        var visited = Set<UUID>()
        var containerRoutes: [BrowseRoute] = []

        while visited.insert(currentID).inserted {
            guard
                let container = place.containers.first(where: {
                    $0.id == currentID && $0.placeID == place.id && $0.archivedAt == nil
                })
            else { return nil }

            containerRoutes.append(.container(container.id))
            switch container.parent {
            case .room(let roomID):
                guard place.activeRooms.contains(where: { $0.id == roomID }) else { return nil }
                return [.place(place.id), .room(roomID)] + Array(containerRoutes.reversed())
            case .area(let areaID):
                guard let area = place.activeAreas.first(where: { $0.id == areaID }) else {
                    return nil
                }
                return [.place(place.id), .room(area.roomID), .area(areaID)]
                    + Array(containerRoutes.reversed())
            case .container(let parentID):
                currentID = parentID
            }
        }

        return nil
    }
}

struct BrowseRestoredState: Equatable {
    let selectedPlaceID: UUID?
    let visiblePath: [BrowseRoute]
}

enum BrowsePathTransition {
    static func selectingRoom(_ roomID: UUID, replacing _: [BrowseRoute]) -> [BrowseRoute] {
        [.room(roomID)]
    }
}

enum BrowseSelectionRestorer {
    static func state(
        for destination: BrowseRoute?,
        preferredPlaceID: UUID? = nil,
        in places: [PlaceSnapshot]
    ) -> BrowseRestoredState {
        let activePlaces = places.filter { $0.archivedAt == nil }
        guard let fallbackPlaceID = activePlaces.first(where: { $0.id == preferredPlaceID })?.id
            ?? activePlaces.first?.id
        else {
            return BrowseRestoredState(selectedPlaceID: nil, visiblePath: [])
        }

        guard
            let fullPath = BrowsePathRestorer.path(to: destination, in: activePlaces),
            case .place(let placeID)? = fullPath.first
        else {
            return BrowseRestoredState(selectedPlaceID: fallbackPlaceID, visiblePath: [])
        }

        return BrowseRestoredState(
            selectedPlaceID: placeID,
            visiblePath: Array(fullPath.dropFirst())
        )
    }
}

private struct ManagementPresentation: Identifiable {
    let id = UUID()
    let route: ManagementRoute
}

struct BrowseView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var store: CatalogStore
    let onSharePlace: (UUID) -> Void
    let onPrintQRCodes: () -> Void
    let onScan: () -> Void
    @Binding var navigationRequest: BrowseRoute?
    @AppStorage("witt.browse.savedDestination.v1") private var savedDestination = Data()
    @AppStorage("witt.browse.selectedPlaceID.v1") private var savedSelectedPlaceID = ""
    @State private var path: [BrowseRoute] = []
    @State private var selectedPlaceID: UUID?
    @State private var hasCompletedRestoration = false
    @State private var managementPresentation: ManagementPresentation?
    @State private var query = ""
    @State private var isSearchPresented = false
    @State private var hasPresentedEmptyPlaceCreation = false
    @State private var thingPostSaveDismissal = ThingPostSaveDismissalState()

    var body: some View {
        NavigationStack(path: $path) {
            browseChrome(
                Group {
                    if store.isLoading && store.activePlaces.isEmpty {
                        ProgressView("Loading Places")
                    } else if let selectedPlace {
                        PlaceListView(
                            store: store,
                            place: selectedPlace,
                            onSharePlace: onSharePlace,
                            onPrintQRCodes: onPrintQRCodes,
                            onSelectRoom: selectRoom,
                            presentManagement: presentManagement
                        )
                    } else {
                        emptyPlaces
                    }
                }
            )
            .navigationDestination(for: BrowseRoute.self) { route in
                browseChrome(
                    BrowseDestinationView(
                        store: store,
                        route: route,
                        onSharePlace: onSharePlace,
                        presentManagement: presentManagement
                    )
                )
            }
        }
        .sheet(item: $managementPresentation, onDismiss: finishManagementDismissal) { presentation in
            ManagementSheet(
                store: store,
                route: presentation.route,
                onCreatedPlace: selectCreatedPlace,
                onThingPostSaveHandoff: dismissManagement(after:)
            )
        }
        .onAppear(perform: restoreIfReady)
        .onChange(of: store.hasLoaded) { _, _ in restoreIfReady() }
        .onChange(of: store.places) { _, _ in reconcilePathAfterReload() }
        .onChange(of: path) { _, _ in persistCurrentDestination() }
        .onChange(of: navigationRequest) { _, request in
            guard let request else { return }
            navigate(to: request)
            navigationRequest = nil
        }
    }

    private func browseChrome<Content: View>(_ content: Content) -> some View {
        ZStack {
            content
                .accessibilityHidden(isSearchPresented)
                .allowsHitTesting(!isSearchPresented)
            if isSearchPresented {
                ThingSearchResultsContent(
                    store: store,
                    query: query,
                    onSelect: navigateToSearchResult
                )
                .background(Color(uiColor: .systemGroupedBackground))
                .accessibilityIdentifier("browse.searchResults")
            }
        }
            .searchable(
                text: $query,
                isPresented: $isSearchPresented,
                prompt: "Search"
            )
            .toolbar {
                browseToolbar
            }
    }

    @ToolbarContentBuilder
    private var browseToolbar: some ToolbarContent {
        if horizontalSizeClass == .compact {
            ToolbarItem(placement: .bottomBar) {
                placesMenu
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(.fixed, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                scanButton
            }
        } else {
            ToolbarItem(placement: .bottomBar) {
                placesMenu
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                scanButton
            }
        }
    }

    @ViewBuilder
    private var placesMenu: some View {
        Menu {
            if !store.activePlaces.isEmpty {
                Section("Places") {
                    ForEach(store.activePlaces) { place in
                        Button {
                            selectPlace(place.id)
                        } label: {
                            if place.id == selectedPlaceID {
                                Label(place.name, systemImage: "checkmark")
                            } else {
                                Text(place.name)
                            }
                        }
                    }
                }
            }

            Section {
                Button("New Place", systemImage: "plus") {
                    presentManagement(.createPlace)
                }
            }
        } label: {
            Image(systemName: "mappin.and.ellipse")
        }
        .accessibilityLabel("Places")
    }

    private var scanButton: some View {
        Button("Scan QR", systemImage: "qrcode.viewfinder", action: onScan)
            .labelStyle(.iconOnly)
    }

    private var emptyPlaces: some View {
        ContentUnavailableView {
            Label("No Places", systemImage: "house")
        } description: {
            Text("Create a Place to start cataloguing your things.")
        } actions: {
            Button("New Place", systemImage: "plus") {
                presentManagement(.createPlace)
            }
        }
        .task {
            guard
                store.hasLoaded,
                store.activePlaces.isEmpty,
                !hasPresentedEmptyPlaceCreation
            else { return }
            hasPresentedEmptyPlaceCreation = true
            presentManagement(.createPlace)
        }
    }

    private var selectedPlace: PlaceSnapshot? {
        guard let selectedPlaceID else { return nil }
        return store.activePlaces.first { $0.id == selectedPlaceID }
    }

    private func presentManagement(_ route: ManagementRoute) {
        managementPresentation = ManagementPresentation(route: route)
    }

    private func restoreIfReady() {
        guard store.hasLoaded, !hasCompletedRestoration else { return }

        let destination: BrowseRoute?
        if savedDestination.isEmpty {
            destination = nil
        } else if let decoded = try? JSONDecoder().decode(BrowseRoute.self, from: savedDestination) {
            destination = decoded
        } else {
            savedDestination = Data()
            destination = nil
        }

        apply(
            BrowseSelectionRestorer.state(
                for: destination,
                preferredPlaceID: UUID(uuidString: savedSelectedPlaceID),
                in: store.activePlaces
            )
        )
        hasCompletedRestoration = true
        persistCurrentDestination()
    }

    private func reconcilePathAfterReload() {
        guard store.hasLoaded, hasCompletedRestoration else { return }
        let destination = path.last ?? selectedPlaceID.map(BrowseRoute.place)
        apply(
            BrowseSelectionRestorer.state(
                for: destination,
                preferredPlaceID: selectedPlaceID,
                in: store.activePlaces
            )
        )
        persistCurrentDestination()
    }

    private func persistCurrentDestination() {
        guard hasCompletedRestoration else { return }
        savedSelectedPlaceID = selectedPlaceID?.uuidString ?? ""
        guard let destination = path.last ?? selectedPlaceID.map(BrowseRoute.place) else {
            savedDestination = Data()
            return
        }
        if let encoded = try? JSONEncoder().encode(destination) {
            savedDestination = encoded
        }
    }

    private func selectPlace(_ placeID: UUID) {
        selectedPlaceID = placeID
        setPathWithoutAnimation([])
        persistCurrentDestination()
    }

    private func selectCreatedPlace(_ placeID: UUID) {
        selectPlace(placeID)
    }

    private func selectRoom(_ roomID: UUID) {
        withAnimation {
            path = BrowsePathTransition.selectingRoom(roomID, replacing: path)
        }
    }

    private func navigateToSearchResult(_ thing: ThingSnapshot) {
        isSearchPresented = false
        query = ""
        navigate(to: .thing(thing.id))
    }

    private func navigate(to destination: BrowseRoute) {
        let restored = BrowseSelectionRestorer.state(for: destination, in: store.activePlaces)
        apply(restored)
        persistCurrentDestination()
    }

    private func dismissManagement(after handoff: ThingPostSaveHandoff) {
        thingPostSaveDismissal.begin(handoff)
        managementPresentation = nil
    }

    private func finishManagementDismissal() {
        guard let handoff = thingPostSaveDismissal.finish() else { return }
        switch handoff {
        case .scanNext:
            onScan()
        case .viewThing(let thingID):
            navigate(to: .thing(thingID))
        case .done:
            break
        }
    }

    private func apply(_ restored: BrowseRestoredState) {
        selectedPlaceID = restored.selectedPlaceID
        if restored.visiblePath != path {
            setPathWithoutAnimation(restored.visiblePath)
        }
    }

    private func setPathWithoutAnimation(_ newPath: [BrowseRoute]) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            path = newPath
        }
    }
}

private struct PlaceListView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var store: CatalogStore
    let place: PlaceSnapshot
    let onSharePlace: (UUID) -> Void
    let onPrintQRCodes: () -> Void
    let onSelectRoom: (UUID) -> Void
    let presentManagement: (ManagementRoute) -> Void

    var body: some View {
        List {
            if place.activeRooms.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Rooms Yet",
                        systemImage: "door.left.hand.open",
                        description: Text(
                            "Add the first Room in \(place.name) to organize Storage Areas and Things."
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)

                    GeometryReader { proxy in
                        HStack {
                            Spacer(minLength: 0)
                            newRoomButton(placeID: place.id)
                                .frame(
                                    width: BrowseGridLayout.columnWidth(
                                        availableWidth: proxy.size.width,
                                        dynamicTypeSize: dynamicTypeSize
                                    )
                                )
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 112 : 92)
                    .listRowInsets(
                        EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                Section("Rooms") {
                    AdaptiveBrowseGrid {
                        ForEach(place.activeRooms) { room in
                            Button {
                                onSelectRoom(room.id)
                            } label: {
                                RoomTile(
                                    room: room,
                                    thingCount: place.descendantThingCount(inRoom: room.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        newRoomButton(placeID: place.id)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 1, bottom: 8, trailing: 1))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .navigationTitle(place.name)
        .refreshable { await store.reload() }
        .accessibilityIdentifier("browse.placeList")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if store.isPlaceShared(place.id) {
                    Button("Shared", systemImage: "person.2") {
                        onSharePlace(place.id)
                    }
                }
                Menu("Place Actions", systemImage: "ellipsis") {
                    Button("Rename Place", systemImage: "pencil") {
                        presentManagement(.editPlace(place.id))
                    }
                    Button("Share Place", systemImage: "person.crop.circle.badge.plus") {
                        onSharePlace(place.id)
                    }
                    Divider()
                    Button("Print QR Labels", systemImage: "qrcode", action: onPrintQRCodes)
                }
                .labelStyle(.iconOnly)
            }
        }
    }

    private func newRoomButton(placeID: UUID) -> some View {
        Button {
            presentManagement(.createRoom(placeID: placeID))
        } label: {
            NewRoomTile()
        }
        .buttonStyle(.plain)
    }
}

private struct BrowseDestinationView: View {
    @ObservedObject var store: CatalogStore
    let route: BrowseRoute
    let onSharePlace: (UUID) -> Void
    let presentManagement: (ManagementRoute) -> Void

    var body: some View {
        switch route {
        case .place:
            unavailable("Place", systemImage: "house")
        case .room(let id):
            RoomDetailView(store: store, roomID: id, presentManagement: presentManagement)
        case .area(let id):
            AreaDetailView(store: store, areaID: id, presentManagement: presentManagement)
        case .container(let id):
            ContainerDetailView(store: store, containerID: id, presentManagement: presentManagement)
        case .thing(let id):
            ThingDetailView(store: store, thingID: id)
        }
    }
}

struct RoomDetailView: View {
    @ObservedObject var store: CatalogStore
    let roomID: UUID
    let presentManagement: (ManagementRoute) -> Void

    var body: some View {
        Group {
            if let place = activePlace, let room = place.activeRooms.first(where: { $0.id == roomID }) {
                List {
                    let things = place.activeThings(in: .room(room.id))
                    let containers = place.activeContainers(inRoom: room.id)
                    let areas = place.activeAreas(in: room.id)
                    if things.isEmpty && containers.isEmpty && areas.isEmpty {
                        Section {
                            ContentUnavailableView(
                                "Room Is Empty",
                                systemImage: "door.left.hand.open",
                                description: Text(
                                    "Add a Storage Area to start organizing this Room."
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                        }
                    }
                    if !things.isEmpty {
                        Section("Things") {
                            AdaptiveBrowseGrid {
                                ForEach(things) { thing in
                                    NavigationLink(value: BrowseRoute.thing(thing.id)) {
                                        ThingMediaTile(thing: thing)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .browseGridListRow()
                        }
                    }
                    if !containers.isEmpty {
                        Section("Containers") {
                            AdaptiveBrowseGrid {
                                ForEach(containers) { container in
                                    NavigationLink(value: BrowseRoute.container(container.id)) {
                                        ContainerMediaTile(
                                            container: container,
                                            thingCount: place.descendantThingCount(
                                                inContainer: container.id
                                            )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .browseGridListRow()
                        }
                    }
                    Section("Storage Areas") {
                        ForEach(areas) { area in
                            NavigationLink(value: BrowseRoute.area(area.id)) {
                                StorageAreaRow(
                                    area: area,
                                    thingCount: place.descendantThingCount(inArea: area.id)
                                )
                            }
                        }

                        Button {
                            presentManagement(.createArea(roomID: room.id))
                        } label: {
                            NewStorageAreaRow(continuesList: !areas.isEmpty)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(
                            areas.isEmpty
                                ? EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)
                                : EdgeInsets()
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .navigationTitle(room.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Room Actions", systemImage: "ellipsis") {
                            Button("Edit Room", systemImage: "pencil") {
                                presentManagement(.editRoom(room.id))
                            }
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            } else {
                unavailable("Room", systemImage: "door.left.hand.open")
            }
        }
    }

    private var activePlace: PlaceSnapshot? {
        store.activePlaces.first { $0.activeRooms.contains(where: { $0.id == roomID }) }
    }
}

private struct AreaDetailView: View {
    private enum ContentSelection: String, CaseIterable, Identifiable {
        case things = "Things"
        case containers = "Containers"

        var id: Self { self }
    }

    @ObservedObject var store: CatalogStore
    let areaID: UUID
    let presentManagement: (ManagementRoute) -> Void
    @State private var showsQRScanner = false
    @State private var contentSelection = ContentSelection.things

    var body: some View {
        Group {
            if let place = activePlace, let area = place.activeAreas.first(where: { $0.id == areaID }) {
                VStack(alignment: .leading, spacing: 0) {
                    if let detail = area.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                    Picker("Contents", selection: $contentSelection) {
                        ForEach(ContentSelection.allCases) { selection in
                            Text(selection.rawValue).tag(selection)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    List {
                        CatalogLocationSummary(photo: area.primaryPhoto, detail: nil)
                        let things = place.activeThings(in: .area(area.id))
                        let containers = place.activeContainers(inArea: area.id)
                        if contentSelection == .things {
                            AdaptiveBrowseGrid {
                                ForEach(things) { thing in
                                    NavigationLink(value: BrowseRoute.thing(thing.id)) {
                                        ThingMediaTile(thing: thing)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Button {
                                    presentManagement(.createThing(destination: .area(area.id)))
                                } label: {
                                    NewCatalogGridTile(title: "New Thing")
                                }
                                .buttonStyle(.plain)
                            }
                            .browseGridListRow()
                        } else {
                            AdaptiveBrowseGrid {
                                ForEach(containers) { container in
                                    NavigationLink(value: BrowseRoute.container(container.id)) {
                                        ContainerMediaTile(
                                            container: container,
                                            thingCount: place.descendantThingCount(
                                                inContainer: container.id
                                            )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }

                                Button {
                                    presentManagement(.createContainer(destination: .area(area.id)))
                                } label: {
                                    NewCatalogGridTile(title: "New Container")
                                }
                                .buttonStyle(.plain)
                            }
                            .browseGridListRow()
                        }
                    }
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle(area.name)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Storage Area Actions", systemImage: "ellipsis") {
                            Button("Edit", systemImage: "pencil") {
                                presentManagement(.editArea(area.id))
                            }
                            Button(
                                area.hasQRCode ? "Reattach QR Code" : "Attach QR Code",
                                systemImage: "qrcode.viewfinder"
                            ) {
                                showsQRScanner = true
                            }
                        }
                        .labelStyle(.iconOnly)
                    }
                }
                .fullScreenCover(isPresented: $showsQRScanner) {
                    let target = QRBindingTarget.area(QRTargetID(rawValue: area.id))
                    QRAssignmentScanner(store: store, expectedTarget: target) { token in
                        try await store.replaceQRCode(token, target: target)
                    }
                }
            } else {
                unavailable("Storage Area", systemImage: "cabinet")
            }
        }
    }

    private var activePlace: PlaceSnapshot? {
        store.activePlaces.first { $0.activeAreas.contains(where: { $0.id == areaID }) }
    }
}

private struct ContainerDetailView: View {
    @ObservedObject var store: CatalogStore
    let containerID: UUID
    let presentManagement: (ManagementRoute) -> Void
    @State private var showsQRScanner = false

    var body: some View {
        Group {
            if let place = activePlace,
                let container = place.activeContainers.first(where: { $0.id == containerID })
            {
                List {
                    CatalogLocationSummary(
                        photo: container.primaryPhoto,
                        detail: container.detail
                    )
                    let things = place.activeThings(in: .container(container.id))
                    let children = place.childContainers(of: container.id)
                    Section("Things") {
                        AdaptiveBrowseGrid {
                            ForEach(things) { thing in
                                NavigationLink(value: BrowseRoute.thing(thing.id)) {
                                    ThingMediaTile(thing: thing)
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                presentManagement(.createThing(destination: .container(container.id)))
                            } label: {
                                NewCatalogGridTile(title: "New Thing")
                            }
                            .buttonStyle(.plain)
                        }
                        .browseGridListRow()
                    }
                    Section("Containers") {
                        AdaptiveBrowseGrid {
                            ForEach(children) { child in
                                NavigationLink(value: BrowseRoute.container(child.id)) {
                                    ContainerMediaTile(
                                        container: child,
                                        thingCount: place.descendantThingCount(
                                            inContainer: child.id
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                presentManagement(.createContainer(destination: .container(container.id)))
                            } label: {
                                NewCatalogGridTile(title: "New Container")
                            }
                            .buttonStyle(.plain)
                        }
                        .browseGridListRow()
                    }
                }
                .navigationTitle(container.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Container Actions", systemImage: "ellipsis") {
                            Button("Edit", systemImage: "pencil") {
                                presentManagement(.editContainer(container.id))
                            }
                            Button(
                                container.hasQRCode ? "Reattach QR Code" : "Attach QR Code",
                                systemImage: "qrcode.viewfinder"
                            ) {
                                showsQRScanner = true
                            }
                        }
                        .labelStyle(.iconOnly)
                    }
                }
                .fullScreenCover(isPresented: $showsQRScanner) {
                    let target = QRBindingTarget.container(QRTargetID(rawValue: container.id))
                    QRAssignmentScanner(store: store, expectedTarget: target) { token in
                        try await store.replaceQRCode(token, target: target)
                    }
                }
            } else {
                unavailable("Container", systemImage: "shippingbox")
            }
        }
    }

    private var activePlace: PlaceSnapshot? {
        store.activePlaces.first { $0.activeContainers.contains(where: { $0.id == containerID }) }
    }
}

private struct CatalogLocationSummary: View {
    let photo: PhotoAssetSnapshot?
    let detail: String?

    var body: some View {
        if photo != nil || detail?.isEmpty == false {
            Section {
                if let data = photo?.thumbnailData ?? photo?.data, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .accessibilityHidden(true)
                }
                if let detail, !detail.isEmpty { Text(detail) }
            }
        }
    }
}

enum BrowseGridLayout {
    static let spacing: CGFloat = 12

    static func columnCount(for dynamicTypeSize: DynamicTypeSize) -> Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : 2
    }

    static func columnWidth(
        availableWidth: CGFloat,
        dynamicTypeSize: DynamicTypeSize
    ) -> CGFloat {
        let count = CGFloat(columnCount(for: dynamicTypeSize))
        return (availableWidth - spacing * (count - 1)) / count
    }
}

private struct AdaptiveBrowseGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: BrowseGridLayout.spacing) {
            content
        }
        .navigationLinkIndicatorVisibility(.hidden)
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: BrowseGridLayout.spacing),
            count: BrowseGridLayout.columnCount(for: dynamicTypeSize)
        )
    }
}

private struct BrowseGridListRowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 8, leading: 1, bottom: 8, trailing: 1))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

private extension View {
    func browseGridListRow() -> some View {
        modifier(BrowseGridListRowModifier())
    }
}

private struct RoomTile: View {
    let room: RoomSnapshot
    let thingCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "door.left.hand.open")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                Text(thingCountLabel(thingCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 8))
        .contentShape(.rect)
    }
}

private struct NewRoomTile: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "plus")
                .font(.title2)
                .frame(width: 30)
                .accessibilityHidden(true)
            Text("New Room")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.tint)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .overlay { DashedCreateBorder() }
        .contentShape(.rect)
    }
}

private struct StorageAreaRow: View {
    let area: AreaSnapshot
    let thingCount: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(area.name)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(thingCountLabel(thingCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CatalogThumbnail(photo: area.primaryPhoto, fallbackSystemImage: "cabinet")
        }
    }
}

private struct NewStorageAreaRow: View {
    let continuesList: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("New Storage Area")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "plus")
                .font(.title2)
                .frame(width: 64, height: 52)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.tint)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .overlay {
            if continuesList {
                ZStack(alignment: .top) {
                    Divider()
                    BottomDashedCreateBorder()
                }
            } else {
                DashedCreateBorder()
            }
        }
        .contentShape(.rect)
    }
}

private struct BottomDashedCreateBorder: View {
    private let borderShape = UnevenRoundedRectangle(
        cornerRadii: RectangleCornerRadii(
            bottomLeading: 24,
            bottomTrailing: 24
        ),
        style: .circular
    )

    var body: some View {
        ZStack {
            borderShape
                .strokeBorder(
                    Color.accentColor,
                    style: StrokeStyle(
                        lineWidth: 1,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: [6, 4]
                    )
                )
                .mask { BottomCreateBorderMask() }

            borderShape
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                .mask { BottomCreateCornerMask() }
        }
        .accessibilityHidden(true)
    }
}

private struct BottomCreateBorderMask: View {
    var body: some View {
        Color.white
            .padding(.top, 1)
    }
}

private struct BottomCreateCornerMask: View {
    var body: some View {
        HStack(spacing: 0) {
            Color.white.frame(width: 32)
            Spacer(minLength: 0)
            Color.white.frame(width: 32)
        }
        .frame(height: 32)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

private struct DashedCreateBorder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    Color.accentColor,
                    style: StrokeStyle(
                        lineWidth: 1,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: [6, 4]
                    )
                )

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 1)
                .mask { DashedCreateCornerMask() }
        }
        .accessibilityHidden(true)
    }
}

private struct DashedCreateCornerMask: View {
    var body: some View {
        ZStack {
            corner(alignment: .topLeading)
            corner(alignment: .topTrailing)
            corner(alignment: .bottomLeading)
            corner(alignment: .bottomTrailing)
        }
    }

    private func corner(alignment: Alignment) -> some View {
        Color.white
            .frame(width: 16, height: 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

private struct NewCatalogGridTile: View {
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.title2)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .foregroundStyle(.tint)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .overlay { DashedCreateBorder() }
        .contentShape(.rect)
    }
}

private struct ThingMediaTile: View {
    let thing: ThingSnapshot

    var body: some View {
        CatalogTileMedia(photo: thing.primaryPhoto, fallbackSystemImage: "square.grid.2x2")
            .overlay(alignment: .bottom) {
                Text(thing.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.black.opacity(0.56))
            }
            .clipShape(.rect(cornerRadius: 8))
            .accessibilityElement(children: .combine)
    }
}

private struct ContainerMediaTile: View {
    let container: ContainerSnapshot
    let thingCount: Int

    var body: some View {
        CatalogTileMedia(photo: container.primaryPhoto, fallbackSystemImage: "shippingbox.fill")
            .overlay {
                VStack(spacing: 4) {
                    Text(container.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(thingCountLabel(thingCount))
                        .font(.caption)
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(Color.black.opacity(0.56))
            }
            .clipShape(.rect(cornerRadius: 8))
            .accessibilityElement(children: .combine)
    }
}

private struct CatalogTileMedia: View {
    let photo: PhotoAssetSnapshot?
    let fallbackSystemImage: String

    var body: some View {
        CatalogMedia(photo: photo, fallbackSystemImage: fallbackSystemImage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .clipShape(.rect(cornerRadius: 8))
    }
}

private struct CatalogThumbnail: View {
    let photo: PhotoAssetSnapshot?
    let fallbackSystemImage: String

    var body: some View {
        CatalogMedia(photo: photo, fallbackSystemImage: fallbackSystemImage)
            .frame(width: 64, height: 52)
            .clipped()
            .clipShape(.rect(cornerRadius: 6))
    }
}

private struct CatalogMedia: View {
    let photo: PhotoAssetSnapshot?
    let fallbackSystemImage: String

    var body: some View {
        Group {
            if let data = photo?.thumbnailData ?? photo?.data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(uiColor: .secondarySystemGroupedBackground)
                    Image(systemName: fallbackSystemImage)
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private func thingCountLabel(_ count: Int) -> String {
    "\(count) \(count == 1 ? "thing" : "things")"
}

@ViewBuilder
private func unavailable(_ noun: String, systemImage: String) -> some View {
    ContentUnavailableView(
        "\(noun) Unavailable",
        systemImage: systemImage,
        description: Text("It may have been archived or removed from this Place.")
    )
}

struct ThingRow: View {
    @ObservedObject var store: CatalogStore
    let thing: ThingSnapshot

    var body: some View {
        HStack(spacing: 12) {
            ThingThumbnail(thing: thing)
            VStack(alignment: .leading, spacing: 3) {
                Text(thing.name)
                Text(store.locationComponents(for: thing).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct ThingThumbnail: View {
    let thing: ThingSnapshot

    var body: some View {
        Group {
            if let data = thing.primaryPhoto?.thumbnailData ?? thing.primaryPhoto?.data,
                let image = UIImage(data: data)
            {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "shippingbox").foregroundStyle(.secondary)
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}

#Preview("Browse") {
    let persistence = PersistenceController.inMemory()
    let store = CatalogStore(persistence: persistence)
    BrowseView(
        store: store,
        onSharePlace: { _ in },
        onPrintQRCodes: {},
        onScan: {},
        navigationRequest: .constant(nil)
    )
        .task { await store.bootstrap() }
}
