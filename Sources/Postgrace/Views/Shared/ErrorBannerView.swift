import SwiftUI

/// Reusable error banner that slides in from the top.
struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        if isVisible {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(2)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isVisible = false
                    }
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color.red.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    init(message: String, onDismiss: @escaping () -> Void) {
        self.message = message
        self.onDismiss = onDismiss
        _isVisible = State(initialValue: true)
    }
}

/// Reusable success toast that auto-dismisses.
struct SuccessToastView: View {
    let message: String

    @State private var isVisible = true

    var body: some View {
        if isVisible {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.white)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.9))
            .clipShape(Capsule())
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation {
                        isVisible = false
                    }
                }
            }
        }
    }
}
