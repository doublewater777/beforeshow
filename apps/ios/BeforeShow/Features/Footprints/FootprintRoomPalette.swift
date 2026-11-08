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

    // City map at night.
    static let mapNight = Color(red: 0.043, green: 0.059, blue: 0.078)

    // Candle.
    static let candleRoom = Color(red: 0.031, green: 0.024, blue: 0.020)
    static let wax = Color(red: 0.969, green: 0.941, blue: 0.882)
    static let flame = Color(red: 1.0, green: 0.78, blue: 0.396)
    static let flameEdge = Color(red: 1.0, green: 0.604, blue: 0.227)
    static let candleText = Color(red: 0.957, green: 0.933, blue: 0.890)
    static let candleGold = Color(red: 0.851, green: 0.698, blue: 0.478)

    // Memory book: cloth cover, gold foil, paper and ink.
    static let bookRoom = Color(red: 0.027, green: 0.027, blue: 0.035)
    static let bookCloth = Color(red: 0.114, green: 0.106, blue: 0.125)
    static let bookClothDeep = Color(red: 0.051, green: 0.047, blue: 0.063)
    static let foilDark = Color(red: 0.620, green: 0.486, blue: 0.263)
    static let foil = Color(red: 0.851, green: 0.737, blue: 0.518)
    static let foilLight = Color(red: 1.0, green: 0.945, blue: 0.812)
    static let paper = Color(red: 0.945, green: 0.918, blue: 0.859)
    static let paperEdge = Color(red: 0.847, green: 0.812, blue: 0.737)
    static let photoPaper = Color(red: 0.984, green: 0.969, blue: 0.933)
    static let ink = Color(red: 0.106, green: 0.102, blue: 0.090)
    static let inkSoft = Color(red: 0.290, green: 0.275, blue: 0.243)
    static let inkMuted = Color(red: 0.420, green: 0.396, blue: 0.353)
    static let inkFaint = Color(red: 0.541, green: 0.510, blue: 0.451)
    static let stampGold = Color(red: 0.659, green: 0.510, blue: 0.247)
    static let chapterPaper = Color(red: 0.047, green: 0.043, blue: 0.055)
    static let chapterInk = Color(red: 0.961, green: 0.937, blue: 0.886)
    static let chapterDot = Color(red: 0.910, green: 0.780, blue: 0.557)

    // Setlist: a sheet of paper taped to the floor.
    static let setlistFloor = Color(red: 0.043, green: 0.043, blue: 0.047)
    static let setlistPaper = Color(red: 0.949, green: 0.937, blue: 0.902)
    static let setlistInk = Color(red: 0.094, green: 0.094, blue: 0.102)
    static let tape = Color(red: 0.588, green: 0.588, blue: 0.612)
    static let highlighter = Color(red: 0.910, green: 0.780, blue: 0.557)
    // Companions: fabric wristbands with a metal clasp.
    static let wristbands: [Color] = [
        Color(red: 0.784, green: 0.208, blue: 0.169),
        Color(red: 0.184, green: 0.365, blue: 0.620),
        Color(red: 0.851, green: 0.643, blue: 0.255),
        Color(red: 0.243, green: 0.490, blue: 0.353),
        Color(red: 0.420, green: 0.310, blue: 0.592)
    ]
    static let wristbandText = Color(red: 0.969, green: 0.957, blue: 0.925)
    static let clasp = Color(red: 0.902, green: 0.902, blue: 0.918)
    static let claspShade = Color(red: 0.549, green: 0.549, blue: 0.573)
    // Merch: a lit wooden display case.
    static let cabinetRoom = Color(red: 0.043, green: 0.039, blue: 0.035)
    static let cabinetTop = Color(red: 0.106, green: 0.090, blue: 0.078)
    static let cabinetBottom = Color(red: 0.071, green: 0.059, blue: 0.051)
    static let cabinetFrame = Color(red: 0.165, green: 0.137, blue: 0.114)
    static let cabinetLight = Color(red: 1.0, green: 0.910, blue: 0.745)
    static let glassShelf = Color(red: 0.863, green: 0.922, blue: 0.941)
    // Ledger: thermal receipt paper.
    static let receiptPaper = Color(red: 0.957, green: 0.949, blue: 0.925)
    static let receiptInk = Color(red: 0.102, green: 0.102, blue: 0.110)
    static let printerSlot = Color(red: 0.133, green: 0.133, blue: 0.149)
    // Badges: enamel pins in three metals.
    static let badgeMetals: [Color] = [
        Color(red: 0.722, green: 0.478, blue: 0.318),
        Color(red: 0.784, green: 0.800, blue: 0.831),
        Color(red: 0.941, green: 0.863, blue: 0.714)
    ]
    static let badgeEnamel = Color(red: 0.086, green: 0.082, blue: 0.094)
    static let badgeLocked = Color(red: 0.180, green: 0.176, blue: 0.192)
}
