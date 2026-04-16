// Color+Hex.swift
// Brand colors + hex initializer used throughout WheelBro.

import SwiftUI

extension Color {

    // MARK: - WheelBro Brand Colors
    static let wheelBroYellow   = Color(hex: "FFCD00")   // primary accent
    static let wheelBroRed      = Color(hex: "FF0000")   // alerts / DTCs
    static let cardBackground   = Color(hex: "1C1C1E")   // OBD value cards
    static let bannerBackground = Color(hex: "111111")   // top status banner

    // MARK: - Hex Initializer
    /// Creates a Color from a hex string. Supports 3-char, 6-char, and 8-char (with alpha) formats.
    /// The leading "#" is stripped automatically.
    init(hex: String) {
        // Strip any non-alphanumeric prefix/suffix (e.g., "#")
        let raw = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

        var int: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&int)

        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64

        switch raw.count {
        case 3:
            // Shorthand RGB: each nibble doubles (e.g., "F0C" → "FF00CC")
            (a, r, g, b) = (255,
                            (int >> 8) * 17,
                            (int >> 4 & 0xF) * 17,
                            (int & 0xF) * 17)
        case 6:
            // Standard RRGGBB
            (a, r, g, b) = (255,
                            int >> 16,
                            int >> 8 & 0xFF,
                            int & 0xFF)
        case 8:
            // AARRGGBB
            (a, r, g, b) = (int >> 24,
                            int >> 16 & 0xFF,
                            int >> 8  & 0xFF,
                            int & 0xFF)
        default:
            // Fallback: mid-gray
            (a, r, g, b) = (255, 150, 150, 150)
        }

        self.init(
            .sRGB,
            red:     Double(r) / 255,
            green:   Double(g) / 255,
            blue:    Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
