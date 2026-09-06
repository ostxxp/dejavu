import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            List(AppSection.allCases, selection: $app.section) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
                    .padding(.vertical, 5)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 250)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("DéjàVu").font(.system(.title3, design: .serif, weight: .semibold))
                    Text("Французский рядом").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        } detail: {
            switch app.section ?? .home {
            case .home: HomeView()
            case .saved: SavedView()
            case .history: HistoryView()
            case .settings: SettingsView()
            }
        }
        .frame(minWidth: 820, minHeight: 600)
        .tint(.accentColor)
        .onOpenURL { url in
            guard url.scheme == "dejavu", url.host == "open", url.query == nil else { return }
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .onAppear {
            app.openSettingsWindow = {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            app.startSystemIntegration()
        }
    }
}
