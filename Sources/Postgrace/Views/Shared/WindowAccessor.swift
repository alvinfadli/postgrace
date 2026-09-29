import SwiftUI
import AppKit

/// Helper that bridges AppKit NSWindow configuration to SwiftUI views.
/// Enables full-bleed content, transparent titlebars, and window background movability.
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window)
            }
        }
    }
}

/// An NSViewRepresentable that marks its region as draggable for moving the window.
/// Used selectively on custom titlebars/toolbars so dragging the toolbar moves the window,
/// without enabling `isMovableByWindowBackground` globally (which would cause clicking on
/// data grids, column resizers, and table rows to move the window).
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

final class WindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        return true
    }
}

