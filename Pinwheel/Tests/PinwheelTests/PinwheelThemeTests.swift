import XCTest
import SwiftUI
import UIKit
@testable import Pinwheel

@MainActor
final class PinwheelThemeTests: XCTestCase {
    private struct FlatColorProvider: ColorProvider {
        let color: UIColor
        var primaryText: UIColor { color }
        var secondaryText: UIColor { color }
        var tertiaryText: UIColor { color }
        var actionText: UIColor { color }
        var criticalText: UIColor { color }
        var primaryBackground: UIColor { color }
        var secondaryBackground: UIColor { color }
        var actionBackground: UIColor { color }
        var criticalBackground: UIColor { color }
    }

    private struct FixedSizeFontProvider: FontProvider {
        let size: CGFloat
        var title: UIFont { font(ofSize: size, weight: .regular) }
        var subtitle: UIFont { font(ofSize: size, weight: .regular) }
        var subtitleSemibold: UIFont { font(ofSize: size, weight: .semibold) }
        var body: UIFont { font(ofSize: size, weight: .regular) }
        var footnote: UIFont { font(ofSize: size, weight: .regular) }
        var caption: UIFont { font(ofSize: size, weight: .regular) }

        func font(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
            UIFont.systemFont(ofSize: size, weight: weight)
        }
    }

    private func theme(named name: String, color: UIColor, fontSize: CGFloat) -> PinwheelTheme {
        PinwheelTheme(
            name: name,
            colors: FlatColorProvider(color: color),
            fonts: FixedSizeFontProvider(size: fontSize)
        )
    }

    func testColorTokenResolvesTheThemeInTheTraitCollectionRatherThanAGlobal() {
        let red = theme(named: "Red", color: .red, fontSize: 10)
        let blue = theme(named: "Blue", color: .blue, fontSize: 10)

        let inRed = UIColor.primaryText.resolvedColor(with: UITraitCollection(mutations: {
            $0[PinwheelThemeTrait.self] = red
        }))
        let inBlue = UIColor.primaryText.resolvedColor(with: UITraitCollection(mutations: {
            $0[PinwheelThemeTrait.self] = blue
        }))

        XCTAssertEqual(inRed, UIColor.red, "a color token must resolve the theme carried by the traits it is resolved against")
        XCTAssertEqual(inBlue, UIColor.blue, "the same token must resolve differently under a different theme — one static provider cannot be brand-reactive")
    }

    func testFontTokenResolvesThePassedTheme() {
        let small = theme(named: "Small", color: .red, fontSize: 11)
        let large = theme(named: "Large", color: .red, fontSize: 29)

        XCTAssertEqual(PinTextStyle.body.uiFont(in: small).pointSize, 11)
        XCTAssertEqual(PinTextStyle.body.uiFont(in: large).pointSize, 29, "a text style must read the theme it is given, not a fixed provider")
    }

    func testThemesAreEqualByNameSoAReRenderSkipsAnUnchangedSelection() {
        let first = theme(named: "Marine", color: .red, fontSize: 10)
        let second = theme(named: "Marine", color: .blue, fontSize: 20)
        XCTAssertEqual(first, second, "a theme is identified by its name — the providers are its contents, not its identity")
    }

    func testChromeResolvesTheSelectedThemeByName() {
        let chrome = PinwheelChrome()
        chrome.themes = [theme(named: "Marine", color: .red, fontSize: 10), theme(named: "Ember", color: .blue, fontSize: 10)]
        chrome.selectedThemeName = "Ember"
        XCTAssertEqual(chrome.theme.name, "Ember")
    }

    func testChromeFallsBackToTheFirstThemeWhenThePersistedNameIsGone() {
        let chrome = PinwheelChrome()
        chrome.themes = [theme(named: "Marine", color: .red, fontSize: 10)]
        chrome.selectedThemeName = "Ember"
        chrome.normalizeTheme()
        XCTAssertEqual(chrome.selectedThemeName, "Marine", "a persisted name for a theme no longer supplied must fall back rather than resolve nothing")
    }

    func testAThemeKeepsRoundedButtonsUnlessItAsksForAnotherShape() {
        XCTAssertEqual(theme(named: "Marine", color: .red, fontSize: 10).buttonShape, .rounded)
    }

    func testAThemeCanGiveItsButtonsACapsule() {
        let capsuled = PinwheelTheme(
            name: "Ember",
            colors: FlatColorProvider(color: .red),
            fonts: FixedSizeFontProvider(size: 10),
            buttonShape: .capsule
        )
        XCTAssertEqual(capsuled.buttonShape, .capsule, "a capsule is half the button's height, so it cannot be carried as a radius")
    }

    func testThemePickerStaysHiddenForASingleTheme() {
        let chrome = PinwheelChrome()
        chrome.themes = [theme(named: "Marine", color: .red, fontSize: 10)]
        XCTAssertFalse(chrome.isThemePickerVisible, "a catalog with one theme has nothing to pick between")
    }
}
