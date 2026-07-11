import SwiftUI

enum AppTab: Hashable {
    case browse
    case scan
    case find
}

struct AppShellView: View {
    let store: DemoInventoryStore
    private let deepLinkRouter: QRDeepLinkRouter
    @State private var selectedTab: AppTab = .browse
    @State private var presentedScan: ScanDemo?
    @State private var deepLinkAlert: DeepLinkAlert?

    init(
        store: DemoInventoryStore,
        initialScan: ScanDemo? = nil,
        qrResolver: any QRCodeResolving = DemoQRCodeResolver()
    ) {
        self.store = store
        deepLinkRouter = QRDeepLinkRouter(resolver: qrResolver)
        _presentedScan = State(initialValue: initialScan)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Browse", systemImage: "square.grid.2x2", value: AppTab.browse) {
                BrowseView(store: store)
            }

            Tab("Scan", systemImage: "qrcode.viewfinder", value: AppTab.scan) {
                ScanLauncherView { demo in
                    presentedScan = demo
                }
            }

            Tab(value: AppTab.find, role: .search) {
                FindView(store: store)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .sheet(item: $presentedScan) { demo in
            NavigationStack {
                switch demo {
                case .known:
                    CaptureThingView(store: store)
                case .unknown:
                    AttachQRCodeView(store: store)
                case .review:
                    ReviewThingView(
                        store: store,
                        labelingService: MockThingPhotoLabelingService.demo
                    )
                }
            }
        }
        .onOpenURL(perform: handleDeepLink)
        .alert(item: $deepLinkAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func handleDeepLink(_ url: URL) {
        Task {
            do {
                switch try await deepLinkRouter.destination(for: url) {
                case .addThing:
                    presentedScan = .known
                case .attach:
                    presentedScan = .unknown
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
}

private struct DeepLinkAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview("iPad Shell", traits: .landscapeLeft) {
    AppShellView(store: .fixture)
}
