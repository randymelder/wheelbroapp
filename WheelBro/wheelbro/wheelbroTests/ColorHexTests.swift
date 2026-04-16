// ColorHexTests.swift
// Tests for Color+Hex extension — hex parsing and brand color existence.

import Testing
import SwiftUI
import UIKit
@testable import wheelbro

// Helper: extract sRGB components from a SwiftUI Color
private func components(of color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    return (r, g, b, a)
}

@Suite("Color(hex:) — 6-character strings")
struct ColorHex6CharTests {

    @Test func blackHex() {
        let c = components(of: Color(hex: "000000"))
        #expect(c.r < 0.01 && c.g < 0.01 && c.b < 0.01 && abs(c.a - 1) < 0.01)
    }

    @Test func whiteHex() {
        let c = components(of: Color(hex: "FFFFFF"))
        #expect(c.r > 0.99 && c.g > 0.99 && c.b > 0.99 && abs(c.a - 1) < 0.01)
    }

    @Test func pureRedHex() {
        let c = components(of: Color(hex: "FF0000"))
        #expect(c.r > 0.99 && c.g < 0.01 && c.b < 0.01)
    }

    @Test func pureGreenHex() {
        let c = components(of: Color(hex: "00FF00"))
        #expect(c.r < 0.01 && c.g > 0.99 && c.b < 0.01)
    }

    @Test func pureBlueHex() {
        let c = components(of: Color(hex: "0000FF"))
        #expect(c.r < 0.01 && c.g < 0.01 && c.b > 0.99)
    }

    @Test func lowercaseHex() {
        let c = components(of: Color(hex: "ff0000"))
        #expect(c.r > 0.99 && c.g < 0.01 && c.b < 0.01)
    }

    @Test func hexWithPoundPrefix() {
        let withPound    = components(of: Color(hex: "#FF0000"))
        let withoutPound = components(of: Color(hex: "FF0000"))
        #expect(abs(withPound.r - withoutPound.r) < 0.01)
        #expect(abs(withPound.g - withoutPound.g) < 0.01)
        #expect(abs(withPound.b - withoutPound.b) < 0.01)
    }
}

@Suite("Color(hex:) — 3-character shorthand")
struct ColorHex3CharTests {

    @Test func shorthandExpandsCorrectly() {
        // "F00" should equal "FF0000"
        let short = components(of: Color(hex: "F00"))
        let full  = components(of: Color(hex: "FF0000"))
        #expect(abs(short.r - full.r) < 0.01)
        #expect(abs(short.g - full.g) < 0.01)
        #expect(abs(short.b - full.b) < 0.01)
    }

    @Test func shorthandBlack() {
        let c = components(of: Color(hex: "000"))
        #expect(c.r < 0.01 && c.g < 0.01 && c.b < 0.01)
    }

    @Test func shorthandWhite() {
        let c = components(of: Color(hex: "FFF"))
        #expect(c.r > 0.99 && c.g > 0.99 && c.b > 0.99)
    }
}

@Suite("Color(hex:) — 8-character AARRGGBB")
struct ColorHex8CharTests {

    @Test func fullyOpaque() {
        let c = components(of: Color(hex: "FFFF0000"))
        #expect(abs(c.a - 1.0) < 0.01)
        #expect(c.r > 0.99)
    }

    @Test func fullyTransparent() {
        let c = components(of: Color(hex: "00FF0000"))
        #expect(c.a < 0.01)
    }

    @Test func halfAlpha() {
        let c = components(of: Color(hex: "80FF0000"))
        // 0x80 / 255 ≈ 0.502
        #expect(abs(c.a - (128.0 / 255.0)) < 0.01)
    }
}

@Suite("Color(hex:) — invalid input fallback")
struct ColorHexInvalidTests {

    // "ZZZ" is 3 chars — hits the 3-char shorthand branch.
    // Scanner fails to parse it as hex so int stays 0, producing black (0,0,0).
    @Test func unparseable3CharHexProducesBlack() {
        let c = components(of: Color(hex: "ZZZ"))
        #expect(c.r < 0.01 && c.g < 0.01 && c.b < 0.01)
        #expect(abs(c.a - 1.0) < 0.01)
    }

    // Empty string has count == 0, which falls through to the default branch → mid-gray.
    @Test func emptyStringFallsBackToGray() {
        let c = components(of: Color(hex: ""))
        let expected: CGFloat = 150.0 / 255.0
        #expect(abs(c.r - expected) < 0.01)
        #expect(abs(c.g - expected) < 0.01)
        #expect(abs(c.b - expected) < 0.01)
    }

    // A 5-char string also hits the default branch → mid-gray.
    @Test func fiveCharStringFallsBackToGray() {
        let c = components(of: Color(hex: "FFFFF"))
        let expected: CGFloat = 150.0 / 255.0
        #expect(abs(c.r - expected) < 0.01)
    }
}

@Suite("Color — brand colors")
struct ColorBrandTests {

    @Test func wheelBroYellowIsYellow() {
        // FFCD00 — high red, high green, no blue
        let c = components(of: Color.wheelBroYellow)
        #expect(c.r > 0.99)
        #expect(c.g > 0.70)
        #expect(c.b < 0.05)
        #expect(abs(c.a - 1.0) < 0.01)
    }

    @Test func wheelBroRedIsPureRed() {
        let c = components(of: Color.wheelBroRed)
        #expect(c.r > 0.99 && c.g < 0.01 && c.b < 0.01)
    }

    @Test func cardBackgroundIsDark() {
        // 1C1C1E — very dark gray
        let c = components(of: Color.cardBackground)
        #expect(c.r < 0.15 && c.g < 0.15 && c.b < 0.15)
    }

    @Test func bannerBackgroundIsDark() {
        // 111111 — near-black
        let c = components(of: Color.bannerBackground)
        #expect(c.r < 0.10 && c.g < 0.10 && c.b < 0.10)
    }
}
