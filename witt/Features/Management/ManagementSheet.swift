import SwiftUI

struct ManagementSheet: View {
    @ObservedObject private var store: CatalogStore
    private let route: ManagementRoute
    private let onCreatedPlace: (UUID) -> Void
    private let onThingPostSaveHandoff: (ThingPostSaveHandoff) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isCommitting = false
    @State private var savedThing: ThingSnapshot?
    @State private var creationSessionID = UUID()
    @State private var thingCreationDestination: ThingDestination?

    init(
        store: CatalogStore,
        route: ManagementRoute,
        onCreatedPlace: @escaping (UUID) -> Void = { _ in },
        onThingPostSaveHandoff: @escaping (ThingPostSaveHandoff) -> Void = { _ in }
    ) {
        self.store = store
        self.route = route
        self.onCreatedPlace = onCreatedPlace
        self.onThingPostSaveHandoff = onThingPostSaveHandoff
        if case .createThing(let destination) = route {
            _thingCreationDestination = State(initialValue: destination)
        }
    }

    var body: some View {
        NavigationStack {
            if let savedThing {
                ThingSavedView(
                    thing: savedThing,
                    location: store.locationComponents(for: savedThing).joined(separator: " · "),
                    onAction: handlePostSaveAction
                )
            } else {
                ManagementForm(
                    store: store,
                    route: effectiveRoute,
                    isCommitting: $isCommitting,
                    onCreatedPlace: { onCreatedPlace($0.id) },
                    onCreatedThing: { thing in
                        thingCreationDestination = ThingDestination(home: thing.home)
                        savedThing = thing
                    },
                    onFinished: { dismiss() }
                )
                .id(creationSessionID)
            }
        }
        .interactiveDismissDisabled(isCommitting)
    }

    private var effectiveRoute: ManagementRoute {
        if case .createThing = route {
            return .createThing(destination: thingCreationDestination)
        }
        return route
    }

    private func handlePostSaveAction(_ action: ThingPostSaveAction) {
        guard let savedThing else { return }
        if action == .addAnotherHere {
            self.savedThing = nil
            creationSessionID = UUID()
        } else if let handoff = ThingPostSaveHandoff(action: action, thingID: savedThing.id) {
            onThingPostSaveHandoff(handoff)
        }
    }
}

private struct ManagementForm: View {
    @ObservedObject var store: CatalogStore
    let route: ManagementRoute
    @Binding var isCommitting: Bool
    let onCreatedPlace: (PlaceSnapshot) -> Void
    let onCreatedThing: (ThingSnapshot) -> Void
    let onFinished: () -> Void

    @ViewBuilder var body: some View {
        switch route {
        case .createPlace:
            PlaceManagementForm(
                store: store, placeID: nil, isSaving: $isCommitting,
                onCreated: onCreatedPlace, onFinished: onFinished)
        case .createRoom(let placeID):
            RoomManagementForm(
                store: store, roomID: nil, contextPlaceID: placeID, isSaving: $isCommitting,
                onFinished: onFinished)
        case .createArea(let roomID):
            AreaManagementForm(
                store: store, areaID: nil, contextRoomID: roomID, isSaving: $isCommitting,
                onFinished: onFinished)
        case .createContainer(let destination):
            ContainerManagementForm(
                store: store, containerID: nil, contextDestination: destination, isSaving: $isCommitting,
                onFinished: onFinished)
        case .createThing(let destination):
            ThingManagementForm(
                store: store, thingID: nil, contextDestination: destination, isSaving: $isCommitting,
                onCreated: onCreatedThing, onFinished: onFinished)
        case .editPlace(let id):
            PlaceManagementForm(
                store: store, placeID: id, isSaving: $isCommitting, onFinished: onFinished)
        case .editRoom(let id):
            RoomManagementForm(
                store: store, roomID: id, contextPlaceID: nil, isSaving: $isCommitting,
                onFinished: onFinished)
        case .editArea(let id):
            AreaManagementForm(
                store: store, areaID: id, contextRoomID: nil, isSaving: $isCommitting,
                onFinished: onFinished)
        case .editContainer(let id):
            ContainerManagementForm(
                store: store, containerID: id, contextDestination: nil, isSaving: $isCommitting,
                onFinished: onFinished)
        case .editThing(let id):
            ThingManagementForm(
                store: store, thingID: id, contextDestination: nil, isSaving: $isCommitting,
                onCreated: onCreatedThing, onFinished: onFinished)
        }
    }
}
