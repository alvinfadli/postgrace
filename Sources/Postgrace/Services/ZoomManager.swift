import Foundation
import SwiftUI
import Observation

/// Manages application-wide zoom scaling for the SQL editor, data grid, and content workspace.
/// Supports ⌘+ (zoom in), ⌘- (zoom out), ⌘0 (actual size / reset), and persists user preferences.
@Observable
public final class ZoomManager: @unchecked Sendable {
    public static let shared = ZoomManager()

    public static let minZoom: Double = 0.70   // 70%
    public static let maxZoom: Double = 2.00   // 200%
    public static let defaultZoom: Double = 1.00 // 100%
    public static let step: Double = 0.10      // 10% step

    private static let userDefaultsKey = "postgrace_zoom_level"

    public var zoomLevel: Double {
        didSet {
            UserDefaults.standard.set(zoomLevel, forKey: Self.userDefaultsKey)
            triggerToast()
        }
    }

    public var showZoomToast: Bool = false
    private var toastTask: Task<Void, Never>? = nil

    public init() {
        let saved = UserDefaults.standard.double(forKey: Self.userDefaultsKey)
        if saved >= Self.minZoom && saved <= Self.maxZoom {
            self.zoomLevel = (saved * 100).rounded() / 100
        } else {
            self.zoomLevel = Self.defaultZoom
        }
    }

    public var zoomPercentage: Int {
        Int(round(zoomLevel * 100))
    }

    public var zoomPercentageString: String {
        "\(zoomPercentage)%"
    }

    public var isDefaultZoom: Bool {
        abs(zoomLevel - Self.defaultZoom) < 0.001
    }

    public var scale: CGFloat {
        CGFloat(zoomLevel)
    }

    // MARK: - Proportional Typography & Grid Metrics

    public var editorFontSize: CGFloat {
        max(9, min(28, round(13.0 * scale)))
    }

    public var gridCellFontSize: CGFloat {
        max(8, min(24, round(12.0 * scale)))
    }

    public var gridHeaderFontSize: CGFloat {
        max(9, min(24, round(12.0 * scale)))
    }

    public var gridRowPaddingVertical: CGFloat {
        max(3, min(14, round(5.0 * scale)))
    }

    // MARK: - Zoom Actions

    public func zoomIn() {
        let next = min(Self.maxZoom, ((zoomLevel + Self.step) * 100).rounded() / 100)
        setZoom(next)
    }

    public func zoomOut() {
        let next = max(Self.minZoom, ((zoomLevel - Self.step) * 100).rounded() / 100)
        setZoom(next)
    }

    public func resetZoom() {
        setZoom(Self.defaultZoom)
    }

    public func setZoom(_ value: Double) {
        let clamped = max(Self.minZoom, min(Self.maxZoom, (value * 100).rounded() / 100))
        guard abs(zoomLevel - clamped) > 0.001 else { return }
        zoomLevel = clamped
    }

    private func triggerToast() {
        showZoomToast = true
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self = self, !Task.isCancelled else { return }
            self.showZoomToast = false
        }
    }
}
