import SwiftUI

struct AppShellView: View {
    @ObservedObject var store: CatalogStore
    private let deepLinkRouter: QRDeepLinkRouter
    @State private var presentedScan: ScanPresentation?
    @State private var isPresentingScanner = false
    @State private var pendingScannerOutcome: ScannerOutcome?
#if DEBUG
    @State private var pendingDemo: ScanDemo?
#endif
    @State private var thingPostSaveDismissal = ThingPostSaveDismissalState()
    @State private var browseNavigationRequest: BrowseRoute?
    @State private var sharingSheet: PlaceSharingSheet?
    @State private var isPrintingQRCodes = false
    @State private var deepLinkAlert: DeepLinkAlert?
    @State private var isRoutingQRCode = false
    @ObservedObject private var shareAcceptanceCenter = PlaceShareAcceptanceCenter.shared

#if DEBUG
    init(store: CatalogStore, initialScan: ScanDemo? = nil, qrResolver: any QRCodeResolving) {
        self.store = store
        deepLinkRouter = QRDeepLinkRouter(resolver: qrResolver)
        _pendingDemo = State(initialValue: initialScan)
    }
#else
    init(store: CatalogStore, qrResolver: any QRCodeResolving) {
        self.store = store
        deepLinkRouter = QRDeepLinkRouter(resolver: qrResolver)
    }
#endif

    var body: some View {
        BrowseView(
            store: store,
            onSharePlace: sharePlace,
            onPrintQRCodes: { isPrintingQRCodes = true },
            onScan: { isPresentingScanner = true },
            navigationRequest: $browseNavigationRequest
        )
        .fullScreenCover(isPresented: $isPresentingScanner, onDismiss: finishScannerDismissal) {
            ScanView(
                isPaused: pendingScannerOutcome != nil,
                onClose: { isPresentingScanner = false },
                onPayload: handleScannerPayload
            )
        }
        .sheet(item: $presentedScan, onDismiss: finishThingFlowDismissal) { presentation in
            NavigationStack {
                switch presentation.flow {
                case .capture(let destination):
                    CaptureThingView(
                        store: store,
                        destination: destination,
                        onPostSaveHandoff: dismissScanFlow(after:)
                    )
                case .attach(let token):
                    AttachQRCodeView(
                        store: store,
                        token: token,
                        onAttached: closeScanFlow
                    )
#if DEBUG
                case .review(let destination, let photo):
                    ReviewThingSessionView(
                        store: store,
                        destination: destination,
                        photo: photo,
                        onPostSaveHandoff: dismissScanFlow(after:)
                    )
                case .createAttach(let token):
                    CreateAndAttachView(
                        store: store,
                        token: token,
                        onAttached: closeScanFlow
                    )
#endif
                case .repair(let route):
                    RepairQRCodeView(
                        store: store,
                        route: route,
                        onRepaired: closeScanFlow
                    )
                }
            }
        }
        .sheet(item: $sharingSheet, onDismiss: {
            Task { await store.reload() }
        }) { item in
            PlaceSharingActivityView(presentation: item.presentation) { result in
                if case .failure(let error) = result {
                    deepLinkAlert = DeepLinkAlert(
                        title: "Couldn't Share Place",
                        message: error.localizedDescription
                    )
                }
            }
        }
        .sheet(isPresented: $isPrintingQRCodes) {
            QRCodePrintingView()
        }
        .onOpenURL(perform: handleDeepLink)
#if DEBUG
        .onChange(of: store.hasLoaded) { _, loaded in
            guard loaded else { return }
            presentPendingDemoIfPossible()
        }
#endif
        .onChange(of: store.errorMessage) { _, message in
            guard let message else { return }
            deepLinkAlert = DeepLinkAlert(title: "WITT Couldn't Finish", message: message)
            store.errorMessage = nil
        }
        .onReceive(shareAcceptanceCenter.$status) { status in
            switch status {
            case .accepted:
                deepLinkAlert = DeepLinkAlert(
                    title: "Place Added",
                    message: "The shared Place is now available in WITT."
                )
                shareAcceptanceCenter.clearStatus()
                Task { await store.reload() }
            case .failed(let error):
                deepLinkAlert = DeepLinkAlert(
                    title: "Couldn't Accept Place",
                    message: error.localizedDescription
                )
                shareAcceptanceCenter.clearStatus()
            case .idle, .accepting:
                break
            }
        }
        .alert(item: $deepLinkAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard !isRoutingQRCode else { return }
        isRoutingQRCode = true
        Task {
            defer { isRoutingQRCode = false }
            do {
                switch try await deepLinkRouter.destination(for: url) {
                case .addThing(let destination):
                    presentedScan = ScanPresentation(flow: .capture(destination))
                case .attach(let token):
                    presentedScan = ScanPresentation(flow: .attach(token))
                case .repair(let route):
                    presentedScan = ScanPresentation(flow: .repair(route))
                }
            } catch {
                deepLinkAlert = DeepLinkAlert(
                    title: "Invalid WITT Code",
                    message: "This link is not a valid WITT QR code."
                )
            }
        }
    }

    private func handleScannerPayload(_ payload: String) {
        guard pendingScannerOutcome == nil else { return }
        pendingScannerOutcome = ScannerOutcome(payload: payload)
        isPresentingScanner = false
    }

    private func finishScannerDismissal() {
        guard let outcome = pendingScannerOutcome else { return }
        pendingScannerOutcome = nil
        switch outcome {
        case .payload(let token):
            routeScannedPayload(token)
        case .invalidPayload:
            deepLinkAlert = DeepLinkAlert(
                title: "Invalid QR Code",
                message: "This QR code does not contain a usable payload."
            )
        }
    }

    private func routeScannedPayload(_ token: QRToken) {
        guard !isRoutingQRCode else { return }
        isRoutingQRCode = true
        Task {
            defer { isRoutingQRCode = false }
            do {
                switch try await deepLinkRouter.destination(for: token) {
                case .addThing(let destination):
                    presentedScan = ScanPresentation(flow: .capture(destination))
                case .attach(let token):
                    presentedScan = ScanPresentation(flow: .attach(token))
                case .repair(let route):
                    presentedScan = ScanPresentation(flow: .repair(route))
                }
            } catch {
                deepLinkAlert = DeepLinkAlert(
                    title: "Unable to Read QR Code",
                    message: "WITT could not look up this QR code. Try scanning it again."
                )
            }
        }
    }

    private func closeScanFlow() {
        presentedScan = nil
    }

    private func dismissScanFlow(after handoff: ThingPostSaveHandoff) {
        thingPostSaveDismissal.begin(handoff)
        presentedScan = nil
    }

    private func finishThingFlowDismissal() {
        guard let handoff = thingPostSaveDismissal.finish() else { return }
        switch handoff {
        case .scanNext:
            isPresentingScanner = true
        case .viewThing(let thingID):
            browseNavigationRequest = .thing(thingID)
        case .done:
            break
        }
    }

    private func sharePlace(_ placeID: UUID) {
        do {
            sharingSheet = PlaceSharingSheet(
                id: placeID,
                presentation: try store.sharingPresentation(for: placeID)
            )
        } catch {
            deepLinkAlert = DeepLinkAlert(
                title: "Couldn't Share Place",
                message: error.localizedDescription
            )
        }
    }

#if DEBUG
    private func presentPendingDemoIfPossible() {
        guard let demo = pendingDemo else { return }
        switch demo {
        case .known:
            guard let destination = store.defaultThingDestination else { return }
            presentedScan = ScanPresentation(flow: .capture(destination))
        case .unknown:
            let token = try! QRToken(validating: "BBBBBBBBBBBBBBBBBBBBBA")
            presentedScan = ScanPresentation(flow: .attach(token))
        case .review:
            guard let destination = store.defaultThingDestination else { return }
            presentedScan = ScanPresentation(flow: .review(destination, nil))
        case .createAttach:
            let token = try! QRToken(validating: "BBBBBBBBBBBBBBBBBBBBBA")
            presentedScan = ScanPresentation(flow: .createAttach(token))
        case .repair:
            let token = try! QRToken(validating: "BBBBBBBBBBBBBBBBBBBBBA")
            let targets = store.activePlaces.flatMap { place in
                place.activeAreas.map { QRBindingTarget.area(QRTargetID(rawValue: $0.id)) }
                    + place.activeContainers.map {
                        QRBindingTarget.container(QRTargetID(rawValue: $0.id))
                    }
            }
            let issue: QRCodeRepairIssue
            if targets.count >= 2 {
                issue = .conflict(QRCodeConflict(
                    firstTarget: targets[0],
                    secondTarget: targets[1],
                    additionalTargets: Array(targets.dropFirst(2))
                ))
            } else {
                issue = .unavailable(QRCodeRepair(reason: .missingTarget))
            }
            presentedScan = ScanPresentation(
                flow: .repair(QRCodeRepairRoute(token: token, issue: issue))
            )
        }
        pendingDemo = nil
    }
#endif
}

enum ScannerOutcome: Equatable {
    case payload(QRToken)
    case invalidPayload

    init(payload: String) {
        guard let token = QRToken(scannedPayload: payload) else {
            self = .invalidPayload
            return
        }
        self = .payload(token)
    }
}

private struct ScanPresentation: Identifiable {
    enum Flow {
        case capture(ThingDestination)
        case attach(QRToken)
#if DEBUG
        case review(ThingDestination, NormalizedPhoto?)
        case createAttach(QRToken)
#endif
        case repair(QRCodeRepairRoute)
    }

    let id = UUID()
    let flow: Flow
}

private struct PlaceSharingSheet: Identifiable {
    let id: UUID
    let presentation: PlaceSharingPresentation
}

private struct DeepLinkAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview("iPad Shell", traits: .landscapeLeft) {
    let persistence = PersistenceController.inMemory()
    let store = CatalogStore(persistence: persistence)
    AppShellView(store: store, qrResolver: store.repository)
        .task { await store.bootstrap() }
}
