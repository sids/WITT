import SwiftUI

struct ManagementSheet: View {
    @ObservedObject private var store: CatalogStore
    private let route: ManagementRoute
    private let onCreatedPlace: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isCommitting = false

    init(
        store: CatalogStore,
        route: ManagementRoute,
        onCreatedPlace: @escaping (UUID) -> Void = { _ in }
    ) {
        self.store = store
        self.route = route
        self.onCreatedPlace = onCreatedPlace
    }

    var body: some View {
        NavigationStack {
            ManagementForm(
                store: store,
                route: route,
                isCommitting: $isCommitting,
                onCreatedPlace: { onCreatedPlace($0.id) },
                onFinished: { dismiss() }
            )
        }
        .interactiveDismissDisabled(isCommitting)
    }
}

private struct ManagementForm: View {
    @ObservedObject var store: CatalogStore
    let route: ManagementRoute
    @Binding var isCommitting: Bool
    let onCreatedPlace: (PlaceSnapshot) -> Void
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
                onFinished: onFinished)
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
                onFinished: onFinished)
        }
    }
}
