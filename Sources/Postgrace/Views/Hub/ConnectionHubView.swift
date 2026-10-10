import SwiftUI

/// Compatibility bridge redirecting legacy ConnectionHubView to the modern FullPageConnectionHubView.
public struct ConnectionHubView: View {
    public init() {}

    public var body: some View {
        FullPageConnectionHubView()
    }
}
