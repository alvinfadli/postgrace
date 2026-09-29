import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        if let imagePath = Bundle.module.path(forResource: "AppIcon", ofType: "png"),
           let iconImage = NSImage(contentsOfFile: imagePath) {
            NSApplication.shared.applicationIconImage = iconImage
        }
        
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.makeKeyAndOrderFront(nil)
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = false
                window.minSize = NSSize(width: 960, height: 620)
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct PostgraceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Services
    private let postgresService: PostgresService
    private let keychainService: KeychainService
    private let schemaService: SchemaService

    // ViewModels
    @State private var connectionViewModel: ConnectionViewModel
    @State private var schemaViewModel: SchemaViewModel
    @State private var queryViewModel: QueryViewModel
    @State private var dataGridViewModel: DataGridViewModel
    @State private var tabViewModel: WorkspaceTabViewModel

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let postgres = PostgresService()
        let keychain = KeychainService()
        let schema = SchemaService(postgresService: postgres)

        self.postgresService = postgres
        self.keychainService = keychain
        self.schemaService = schema

        _connectionViewModel = State(initialValue: ConnectionViewModel(
            postgresService: postgres,
            keychainService: keychain
        ))
        _schemaViewModel = State(initialValue: SchemaViewModel(schemaService: schema))
        _queryViewModel = State(initialValue: QueryViewModel(postgresService: postgres))
        _dataGridViewModel = State(initialValue: DataGridViewModel(postgresService: postgres))
        _tabViewModel = State(initialValue: WorkspaceTabViewModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connectionViewModel)
                .environment(schemaViewModel)
                .environment(queryViewModel)
                .environment(dataGridViewModel)
                .environment(tabViewModel)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            SidebarCommands()
            TextEditingCommands()
            TextFormattingCommands()

            CommandGroup(replacing: .appInfo) {
                Button("About Postgrace") {
                    showAboutDialog()
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("New Connection") {
                    connectionViewModel.showingConnectionForm = true
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Query Tab") {
                    tabViewModel.openQueryTab()
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!connectionViewModel.isConnected)

                Button("Close Tab") {
                    if let activeId = tabViewModel.activeTabId {
                        tabViewModel.closeTab(id: activeId)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(!connectionViewModel.isConnected)
            }

            CommandMenu("View") {
                Button("Refresh Schema") {
                    Task {
                        await schemaViewModel.refresh()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!connectionViewModel.isConnected)

                Divider()

                Button("Open Schemas Catalog") {
                    tabViewModel.openSchemasTab()
                }
                .keyboardShortcut("1", modifiers: [.command, .option])
                .disabled(!connectionViewModel.isConnected)

                Button("New Query Tab") {
                    tabViewModel.openQueryTab()
                }
                .keyboardShortcut("2", modifiers: [.command, .option])
                .disabled(!connectionViewModel.isConnected)
            }

            CommandMenu("Query") {
                Button("Execute") {
                    Task {
                        await queryViewModel.executeQuery()
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!connectionViewModel.isConnected || queryViewModel.isExecuting || queryViewModel.queryText.isEmpty)

                Button("Cancel Query") {
                    queryViewModel.cancelQuery()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!queryViewModel.isExecuting)

                Button("Format SQL") {
                    let text = queryViewModel.queryText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        queryViewModel.queryText = SQLFormatter.format(text)
                    }
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(!connectionViewModel.isConnected || queryViewModel.queryText.isEmpty)

                Button("Clear Editor") {
                    queryViewModel.clearResult()
                    queryViewModel.queryText = ""
                }
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(!connectionViewModel.isConnected)
            }
        }

        Settings {
            Text("Settings")
                .frame(width: 400, height: 300)
        }
    }

    private func showAboutDialog() {
        let alert = NSAlert()
        alert.messageText = "Postgrace"
        alert.informativeText = """
        Version 2.0.0 (Slonik Edition)
        The Precision macOS Native PostgreSQL Client.

        Engineered with 100% Swift, SwiftUI, and PostgresNIO wire protocol.
        Obsidian Dark Design System • Zero Latency Data Grid.

        Copyright © 2026 Postgrace Contributors.
        Licensed under the MIT License.
        """
        if let imagePath = Bundle.module.path(forResource: "AppIcon", ofType: "png"),
           let img = NSImage(contentsOfFile: imagePath) {
            img.size = NSSize(width: 80, height: 80)
            alert.icon = img
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
