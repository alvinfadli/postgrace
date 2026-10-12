import XCTest
import AppKit
import SwiftUI
@testable import Postgrace

final class ThemeTests: XCTestCase {
    func testAppearanceIsDark() {
        let darkAqua = NSAppearance(named: .darkAqua)!
        XCTAssertTrue(darkAqua.isDark, "darkAqua appearance must evaluate isDark to true")

        let aqua = NSAppearance(named: .aqua)!
        XCTAssertFalse(aqua.isDark, "aqua appearance must evaluate isDark to false")

        if let vibrantDark = NSAppearance(named: .vibrantDark) {
            XCTAssertTrue(vibrantDark.isDark, "vibrantDark appearance must evaluate isDark to true")
        }

        if let vibrantLight = NSAppearance(named: .vibrantLight) {
            XCTAssertFalse(vibrantLight.isDark, "vibrantLight appearance must evaluate isDark to false")
        }
    }

    func testDynamicProviderColorAdaptation() {
        let darkAppearance = NSAppearance(named: .darkAqua)!
        let lightAppearance = NSAppearance(named: .aqua)!

        let dynamicCanvas = NSColor(name: nil, dynamicProvider: { appearance in
            appearance.isDark ? NSColor(hex: "#181A1E") : NSColor(hex: "#FFFFFF")
        })

        var darkCanvasResolved: NSColor?
        darkAppearance.performAsCurrentDrawingAppearance {
            darkCanvasResolved = dynamicCanvas.usingColorSpace(.deviceRGB)
        }

        var lightCanvasResolved: NSColor?
        lightAppearance.performAsCurrentDrawingAppearance {
            lightCanvasResolved = dynamicCanvas.usingColorSpace(.deviceRGB)
        }

        XCTAssertNotNil(darkCanvasResolved)
        XCTAssertNotNil(lightCanvasResolved)
        XCTAssertNotEqual(darkCanvasResolved, lightCanvasResolved)
    }

    func testThemeTokensAreDefined() {
        // Ensure static color tokens instantiate without crashing
        _ = PostgraceTheme.canvas
        _ = PostgraceTheme.surface
        _ = PostgraceTheme.surfaceElevated
        _ = PostgraceTheme.surfaceHover
        _ = PostgraceTheme.border
        _ = PostgraceTheme.borderSubtle
        _ = PostgraceTheme.accentSage
    }
}
