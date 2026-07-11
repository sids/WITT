import SwiftUI

private struct ThingPhotoLabelingServiceEnvironmentKey: EnvironmentKey {
    static let defaultValue: any ThingPhotoLabelingService =
        UnavailableThingPhotoLabelingService()
}

extension EnvironmentValues {
    var thingPhotoLabelingService: any ThingPhotoLabelingService {
        get { self[ThingPhotoLabelingServiceEnvironmentKey.self] }
        set { self[ThingPhotoLabelingServiceEnvironmentKey.self] = newValue }
    }
}
