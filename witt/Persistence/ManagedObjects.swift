import CoreData
import Foundation

@objc(WITTPlace)
public final class Place: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String
    @NSManaged public var notes: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var archivedAt: Date?
    @NSManaged public var rooms: NSSet?
    @NSManaged public var areas: NSSet?
    @NSManaged public var containers: NSSet?
    @NSManaged public var things: NSSet?
    @NSManaged public var keywords: NSSet?
    @NSManaged public var qrCodes: NSSet?
    @NSManaged public var photoAssets: NSSet?
    @NSManaged public var photos: NSSet?
    @NSManaged public var primaryPhoto: PhotoAsset?

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        initializeIdentityAndTimestamps()
    }
}

@objc(WITTRoom)
public final class Room: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String
    @NSManaged public var sortOrder: Int32
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var archivedAt: Date?
    @NSManaged public var place: Place?
    @NSManaged public var areas: NSSet?
    @NSManaged public var containers: NSSet?
    @NSManaged public var things: NSSet?

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        initializeIdentityAndTimestamps()
    }
}

@objc(WITTArea)
public final class Area: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String
    @NSManaged public var detail: String?
    @NSManaged public var sortOrder: Int32
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var archivedAt: Date?
    @NSManaged public var place: Place?
    @NSManaged public var room: Room?
    @NSManaged public var containers: NSSet?
    @NSManaged public var things: NSSet?
    @NSManaged public var qrCodes: NSSet?
    @NSManaged public var photos: NSSet?
    @NSManaged public var primaryPhoto: PhotoAsset?

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        initializeIdentityAndTimestamps()
    }
}

@objc(WITTContainer)
public final class Container: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String
    @NSManaged public var detail: String?
    @NSManaged public var sortOrder: Int32
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var archivedAt: Date?
    @NSManaged public var place: Place?
    @NSManaged public var parentRoom: Room?
    @NSManaged public var parentArea: Area?
    @NSManaged public var parentContainer: Container?
    @NSManaged public var childContainers: NSSet?
    @NSManaged public var things: NSSet?
    @NSManaged public var qrCodes: NSSet?
    @NSManaged public var photos: NSSet?
    @NSManaged public var primaryPhoto: PhotoAsset?

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        initializeIdentityAndTimestamps()
    }
}

@objc(WITTThing)
public final class Thing: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String
    @NSManaged public var detail: String?
    @NSManaged public var nameSource: String
    @NSManaged public var searchTextNormalized: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var archivedAt: Date?
    @NSManaged public var place: Place?
    @NSManaged public var homeRoom: Room?
    @NSManaged public var homeArea: Area?
    @NSManaged public var homeContainer: Container?
    @NSManaged public var keywords: NSSet?
    @NSManaged public var photos: NSSet?
    @NSManaged public var primaryPhoto: PhotoAsset?

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        initializeIdentityAndTimestamps()
    }
}

@objc(WITTThingKeyword)
public final class ThingKeyword: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var displayValue: String
    @NSManaged public var normalizedValue: String
    @NSManaged public var source: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var place: Place?
    @NSManaged public var thing: Thing?

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        createdAt = Date()
    }
}

@objc(WITTQRCode)
public final class QRCode: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var token: String
    @NSManaged public var state: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var boundAt: Date?
    // `lastScannedAt` remains only in the deployed model for CloudKit schema compatibility.
    @NSManaged public var place: Place?
    @NSManaged public var area: Area?
    @NSManaged public var container: Container?

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        initializeIdentityAndTimestamps()
    }
}

@objc(WITTPhotoAsset)
public final class PhotoAsset: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var data: Data?
    @NSManaged public var thumbnailData: Data?
    @NSManaged public var contentType: String
    @NSManaged public var pixelWidth: Int32
    @NSManaged public var pixelHeight: Int32
    @NSManaged public var byteSize: Int64
    @NSManaged public var kind: String
    @NSManaged public var source: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var capturedAt: Date?
    @NSManaged public var place: Place?
    @NSManaged public var placeOwner: Place?
    @NSManaged public var areaOwner: Area?
    @NSManaged public var containerOwner: Container?
    @NSManaged public var thingOwner: Thing?
    @NSManaged public var primaryForPlaces: NSSet?
    @NSManaged public var primaryForAreas: NSSet?
    @NSManaged public var primaryForContainers: NSSet?
    @NSManaged public var primaryForThings: NSSet?

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        createdAt = Date()
    }
}

private extension NSManagedObject {
    func initializeIdentityAndTimestamps() {
        setValue(UUID(), forKey: "id")
        let now = Date()
        setValue(now, forKey: "createdAt")
        setValue(now, forKey: "updatedAt")
    }
}
