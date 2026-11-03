import SwiftUI

/// Effect colours for the Footprints rooms. Each room owns one light that
/// carries meaning (neon, starlight, candle flame); chrome stays on
/// `BSColor.Stage`.
enum FootprintRoomPalette {
    // Marquee and records: warm bulbs, brass and paper.
    static let bulb = Color(red: 1.0, green: 0.914, blue: 0.745)
    static let bulbGlow = Color(red: 1.0, green: 0.78, blue: 0.478)
    static let marqueePaper = Color(red: 0.945, green: 0.918, blue: 0.859)
    static let marqueeInk = Color(red: 0.078, green: 0.071, blue: 0.063)
    static let brass = Color(red: 0.788, green: 0.706, blue: 0.541)
    static let vinyl = Color(red: 0.055, green: 0.055, blue: 0.063)
    static let groove = Color(red: 0.173, green: 0.173, blue: 0.192)

    // Neon room.
    static let brick = Color(red: 0.082, green: 0.067, blue: 0.059)
    static let neonCore = Color(red: 1.0, green: 0.957, blue: 0.878)
    static let neonInner = Color(red: 1.0, green: 0.78, blue: 0.478)
    static let neonOuter = Color(red: 1.0, green: 0.541, blue: 0.180)
    static let deadTube = Color(red: 0.231, green: 0.204, blue: 0.176)

    // Night sky.
    static let skyTop = Color(red: 0.071, green: 0.102, blue: 0.180)
    static let skyBottom = Color(red: 0.016, green: 0.020, blue: 0.039)
    static let starlight = Color(red: 0.784, green: 0.824, blue: 0.941)
    static let spotlight = Color(red: 1.0, green: 0.902, blue: 0.690)

    // Tour shirt.
    static let cotton = Color(red: 0.102, green: 0.102, blue: 0.114)
    static let printInk = Color(red: 0.929, green: 0.902, blue: 0.839)

    // Candle.
    static let candleRoom = Color(red: 0.031, green: 0.024, blue: 0.020)
    static let wax = Color(red: 0.969, green: 0.941, blue: 0.882)
    static let flame = Color(red: 1.0, green: 0.78, blue: 0.396)
    static let flameEdge = Color(red: 1.0, green: 0.604, blue: 0.227)
    static let candleText = Color(red: 0.957, green: 0.933, blue: 0.890)
    static let candleGold = Color(red: 0.851, green: 0.698, blue: 0.478)
}
