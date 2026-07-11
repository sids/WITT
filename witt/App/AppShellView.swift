import SwiftUI

enum AppTab: Hashable {
    case browse
    case scan
    case find
}

struct AppShellView: View {
    @ObservedObject var store: CatalogStore
    private let deepLinkRouter: QRDeepLinkRouter
    @State private var selectedTab: AppTab = .browse
    @State private var presentedScan: ScanPresentation?
    @State private var pendingDemo: ScanDemo?
    @State private var sharingSheet: PlaceSharingSheet?
    @State private var isPrintingQRCodes = false
    @State private var deepLinkAlert: DeepLinkAlert?
    @State private var isRoutingQRCode = false
    @ObservedObject private var shareAcceptanceCenter = PlaceShareAcceptanceCenter.shared

    init(
        store: CatalogStore,
        initialScan: ScanDemo? = nil,
        qrResolver: any QRCodeResolving
    ) {
        self.store = store
        deepLinkRouter = QRDeepLinkRouter(resolver: qrResolver)
        _pendingDemo = State(initialValue: initialScan)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Browse", systemImage: "square.grid.2x2", value: AppTab.browse) {
                BrowseView(
                    store: store,
                    onSharePlace: sharePlace,
                    onPrintQRCodes: { isPrintingQRCodes = true }
                )
            }

            Tab("Scan", systemImage: "qrcode.viewfinder", value: AppTab.scan) {
                ScanView(
                    isPaused: selectedTab != .scan || presentedScan != nil || isRoutingQRCode,
                    onPayload: handleScannerPayload
                )
            }

            Tab(value: AppTab.find, role: .search) {
                FindView(store: store)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .sheet(item: $presentedScan) { presentation in
            NavigationStack {
                switch presentation.flow {
                case .capture(let destination):
                    CaptureThingView(
                        store: store,
                        destination: destination,
                        onSaved: closeScanFlow
                    )
                case .attach(let token):
                    AttachQRCodeView(
                        store: store,
                        token: token,
                        onAttached: closeScanFlow
                    )
                case .review(let destination, let photo):
                    ReviewThingView(
                        store: store,
                        destination: destination,
                        photo: photo,
                        onSaved: closeScanFlow
                    )
                case .createAttach(let token):
                    CreateAndAttachView(
                        store: store,
                        token: token,
                        onAttached: closeScanFlow
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
        .onChange(of: store.hasLoaded) { _, loaded in
            guard loaded else { return }
            presentPendingDemoIfPossible()
        }
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
                case .needsRepair:
                    deepLinkAlert = DeepLinkAlert(
                        title: "QR Code Needs Attention",
                        message: "This code was previously attached, but its Storage Area or Container is no longer available."
                    )
                case .conflict:
                    deepLinkAlert = DeepLinkAlert(
                        title: "QR Code Conflict",
                        message: "This code is attached to more than one destination and needs to be repaired before use."
                    )
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
        guard let url = URL(string: payload) else {
            deepLinkAlert = DeepLinkAlert(
                title: "Invalid QR Code",
                message: "This QR code does not contain a valid URL."
            )
            return
        }

        handleDeepLink(url)
    }

    private func closeScanFlow() {
        presentedScan = nil
        selectedTab = .browse
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
        }
        pendingDemo = nil
    }
}

private struct ScanPresentation: Identifiable {
    enum Flow {
        case capture(ThingDestination)
        case attach(QRToken)
        case review(ThingDestination, NormalizedPhoto?)
        case createAttach(QRToken)
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
