import SwiftUI

@main
struct PostgraceApp: App {
    // Services
    private let postgresService: PostgresService
    private let keychainService: KeychainService
    private let schemaService: SchemaService

    // ViewModels
    @State private var connectionViewModel: ConnectionViewModel
    @State private var schemaViewModel: SchemaViewModel
    @State private var queryViewModel: QueryViewModel

    init() {
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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connectionViewModel)
                .environment(schemaViewModel)
                .environment(queryViewModel)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
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
