import SwiftUI

/// Global application state shared across the app.
@Observable
class AppState {
    var isConnecting: Bool = false
    var error: AppError? = nil

    init() {}
}

/// Application-level errors.
enum AppError: Error, LocalizedError {
    case connectionFailed(String)
    case general(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return message
        case .general(let message):
            return message
        }
    }
}
