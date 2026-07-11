import Foundation
import Observation

struct DemoQRCodeResolver: QRCodeResolving {
    static let knownToken = try! QRToken(validating: "AAAAAAAAAAAAAAAAAAAAAA")

    func resolve(_ token: QRToken) async throws -> QRCodeResolution {
        if token == Self.knownToken {
            return .knownContainer(QRTargetID(rawValue: DemoIDs.blueBin))
        }

        return .unknown
    }
}

extension MockThingPhotoLabelingService {
    static var demo: MockThingPhotoLabelingService {
        MockThingPhotoLabelingService(
            mode: .delayedSuccess(
                ThingLabelSuggestion(
                    proposedName: "LED Flashlight",
                    keywords: ["flashlight", "torch", "emergency", "battery"],
                    detail: "Compact black flashlight.",
                    confidence: 0.94
                ),
                delay: .milliseconds(250)
            )
        )
    }
}

private enum DemoIDs {
    static let blueBin = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
}

struct DemoPlace: Identifiable, Hashable {
    let id: UUID
    var name: String
    var rooms: [DemoRoom]
}

struct DemoRoom: Identifiable, Hashable {
    let id: UUID
    var name: String
    var areas: [DemoArea]
}

struct DemoArea: Identifiable, Hashable {
    let id: UUID
    var name: String
    var hasQRCode: Bool
    var containers: [DemoContainer]
    var things: [DemoThing]
}

struct DemoContainer: Identifiable, Hashable {
    let id: UUID
    var name: String
    var hasQRCode: Bool
    var things: [DemoThing]
}

struct DemoThing: Identifiable, Hashable {
    let id: UUID
    var name: String
    var keywords: [String]
    var location: String
    var notes: String
    var symbolName: String
}

struct AttachTarget: Identifiable, Hashable {
    enum Kind: String {
        case area = "Storage Areas"
        case container = "Containers"
    }

    let id: UUID
    let name: String
    let location: String
    let kind: Kind
}

@MainActor
@Observable
final class DemoInventoryStore {
    var places: [DemoPlace]
    var lastSavedThingName: String?
    var lastAttachedTargetName: String?

    init(places: [DemoPlace]) {
        self.places = places
    }

    var things: [DemoThing] {
        places.flatMap(\.rooms).flatMap(\.areas).flatMap { area in
            area.things + area.containers.flatMap(\.things)
        }
    }

    var unassignedTargets: [AttachTarget] {
        places.flatMap { place in
            place.rooms.flatMap { room in
                room.areas.flatMap { area in
                    let path = "\(place.name) · \(room.name)"
                    var targets: [AttachTarget] = []
                    if !area.hasQRCode {
                        targets.append(AttachTarget(id: area.id, name: area.name, location: path, kind: .area))
                    }
                    targets += area.containers.filter { !$0.hasQRCode }.map {
                        AttachTarget(id: $0.id, name: $0.name, location: "\(path) · \(area.name)", kind: .container)
                    }
                    return targets
                }
            }
        }
    }

    func saveSuggestedThing(name: String, keywords: [String], notes: String) {
        lastSavedThingName = name
        let thing = DemoThing(
            id: UUID(),
            name: name,
            keywords: keywords,
            location: "Hall Closet · Top Shelf · Blue Bin",
            notes: notes,
            symbolName: "shippingbox"
        )
        places[0].rooms[0].areas[0].containers[0].things.insert(thing, at: 0)
    }

    func attach(_ target: AttachTarget) {
        lastAttachedTargetName = target.name
    }
}

extension DemoInventoryStore {
    static var fixture: DemoInventoryStore {
        let batteries = DemoThing(
            id: UUID(), name: "AA Batteries", keywords: ["battery", "electronics", "spare"],
            location: "Hall Closet · Top Shelf · Blue Bin", notes: "Rechargeable and alkaline packs.",
            symbolName: "battery.100percent"
        )
        let drill = DemoThing(
            id: UUID(), name: "Cordless Drill", keywords: ["tool", "drill", "repair"],
            location: "Garage · Workbench · Tool Case", notes: "Charger is in the same case.",
            symbolName: "wrench.and.screwdriver"
        )
        let passport = DemoThing(
            id: UUID(), name: "Passports", keywords: ["documents", "travel", "important"],
            location: "Study · Filing Cabinet · Documents Box", notes: "Family passports in a zip pouch.",
            symbolName: "book.closed"
        )

        return DemoInventoryStore(places: [
            DemoPlace(id: UUID(), name: "Home", rooms: [
                DemoRoom(id: UUID(), name: "Hall Closet", areas: [
                    DemoArea(id: UUID(), name: "Top Shelf", hasQRCode: true, containers: [
                        DemoContainer(id: DemoIDs.blueBin, name: "Blue Bin", hasQRCode: true, things: [batteries]),
                        DemoContainer(id: UUID(), name: "Winter Basket", hasQRCode: false, things: [])
                    ], things: [])
                ]),
                DemoRoom(id: UUID(), name: "Garage", areas: [
                    DemoArea(id: UUID(), name: "Workbench", hasQRCode: false, containers: [
                        DemoContainer(id: UUID(), name: "Tool Case", hasQRCode: true, things: [drill])
                    ], things: [])
                ]),
                DemoRoom(id: UUID(), name: "Study", areas: [
                    DemoArea(id: UUID(), name: "Filing Cabinet", hasQRCode: true, containers: [
                        DemoContainer(id: UUID(), name: "Documents Box", hasQRCode: false, things: [passport])
                    ], things: [])
                ])
            ])
        ])
    }

    static var allTargetsAssignedFixture: DemoInventoryStore {
        let store = fixture

        for placeIndex in store.places.indices {
            for roomIndex in store.places[placeIndex].rooms.indices {
                for areaIndex in store.places[placeIndex].rooms[roomIndex].areas.indices {
                    store.places[placeIndex].rooms[roomIndex].areas[areaIndex].hasQRCode = true

                    for containerIndex in store.places[placeIndex].rooms[roomIndex]
                        .areas[areaIndex].containers.indices
                    {
                        store.places[placeIndex].rooms[roomIndex].areas[areaIndex]
                            .containers[containerIndex].hasQRCode = true
                    }
                }
            }
        }

        return store
    }
}
