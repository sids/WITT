import CloudKit
import SwiftUI
import UIKit

@MainActor
public struct PlaceSharingPresentation {
    let place: Place
    let service: PlaceSharingService
    let existingShare: PlaceShare?
    let cloudKitContainer: CKContainer

    public var isManagingExistingShare: Bool {
        existingShare != nil
    }
}

public extension PlaceSharingService {
    func sharingPresentation(for place: Place) throws -> PlaceSharingPresentation {
        try PlaceGraphValidator.validate(place)
        return PlaceSharingPresentation(
            place: place,
            service: self,
            existingShare: try fetchShare(for: place),
            cloudKitContainer: try cloudKitContainer()
        )
    }
}

/// Presents Apple's collaboration activity sheet. The system supplies all invitation and
/// participant-management chrome.
public struct PlaceSharingActivityView: UIViewControllerRepresentable {
    public typealias UIViewControllerType = UIActivityViewController

    private let presentation: PlaceSharingPresentation
    private let onCompletion: (Result<Void, Error>) -> Void

    public init(
        presentation: PlaceSharingPresentation,
        onCompletion: @escaping (Result<Void, Error>) -> Void = { _ in }
    ) {
        self.presentation = presentation
        self.onCompletion = onCompletion
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let itemProvider = NSItemProvider(object: presentation.place.name as NSString)
        let allowedOptions = CKAllowedSharingOptions(
            allowedParticipantPermissionOptions: .readWrite,
            allowedParticipantAccessOptions: .specifiedRecipientsOnly
        )

        if let existingShare = presentation.existingShare {
            itemProvider.registerCKShare(
                existingShare.share,
                container: existingShare.container,
                allowedSharingOptions: allowedOptions
            )
        } else {
            let place = presentation.place
            let service = presentation.service
            itemProvider.registerCKShare(
                container: presentation.cloudKitContainer,
                allowedSharingOptions: allowedOptions
            ) {
                try await service.createShare(for: place).share
            }
        }

        let configuration = UIActivityItemsConfiguration(itemProviders: [itemProvider])
        configuration.metadataProvider = { key in
            key == .title ? presentation.service.shareTitle(for: presentation.place) : nil
        }

        let controller = UIActivityViewController(activityItemsConfiguration: configuration)
        controller.completionWithItemsHandler = { _, completed, _, error in
            if let error {
                onCompletion(.failure(error))
            } else if completed {
                onCompletion(.success(()))
            }
        }
        return controller
    }

    public func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
