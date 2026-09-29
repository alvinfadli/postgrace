import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.makeKeyAndOrderFront(nil)
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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connectionViewModel)
                .environment(schemaViewModel)
                .environment(queryViewModel)
                .environment(dataGridViewModel)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            SidebarCommands()
            TextEditingCommands()
            TextFormattingCommands()

            CommandGroup(replacing: .newItem) {
                Button("New Connection") {
                    connectionViewModel.showingConnectionForm = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Query") {
                Button("Execute") {
                    Task {
                        await queryViewModel.executeQuery()
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }

        Settings {
            Text("Settings")
                .frame(width: 400, height: 300)
        }
    }
}
