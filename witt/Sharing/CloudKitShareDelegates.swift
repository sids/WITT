import CloudKit
import Combine
import UIKit

@MainActor
public final class PlaceShareAcceptanceCenter: ObservableObject {
    public enum Status {
        case idle
        case accepting
        case accepted
        case failed(PlaceSharingError)
    }

    public static let shared = PlaceShareAcceptanceCenter()

    @Published public private(set) var status: Status = .idle

    public var sharingService: PlaceSharingService = PlaceSharingService(
        persistentContainer: PersistenceController.shared.container
    )

    public func accept(_ metadata: CKShare.Metadata) {
        status = .accepting
        Task {
            do {
                _ = try await sharingService.accept(metadata)
                status = .accepted
            } catch let error as PlaceSharingError {
                status = .failed(error)
            } catch {
                status = .failed(.invitationFailure(error.localizedDescription))
            }
        }
    }

    public func clearStatus() {
        status = .idle
    }
}

/// Wire with `@UIApplicationDelegateAdaptor(WITTAppDelegate.self)` in the SwiftUI app.
public final class WITTAppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "WITT Window",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = WITTSceneDelegate.self
        return configuration
    }
}

public final class WITTSceneDelegate: NSObject, UIWindowSceneDelegate {
    public func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            PlaceShareAcceptanceCenter.shared.accept(metadata)
        }
    }

    public func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        PlaceShareAcceptanceCenter.shared.accept(metadata)
    }
}
