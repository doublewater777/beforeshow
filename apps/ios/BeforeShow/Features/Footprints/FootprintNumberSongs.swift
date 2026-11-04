import Foundation

/// A song tied to a show count, played on the record for that number.
struct FootprintNumberSong: Equatable, Sendable {
    let number: Int
    let title: String
    /// Empty when the title alone finds it.
    let artist: String
}

struct FootprintRecordShelf: Equatable {
    let unlocked: [FootprintNumberSong]
    let next: FootprintNumberSong?
    /// Shows still to go before `next` plays.
    let remaining: Int
    let total: Int
}

/// One record per show count, 1 to 50: the 36th show unlocks the 36th record.
enum FootprintNumberSongs {
    private static let catalog: [Int: (title: String, artist: String)] = [
        1: ("第一天", "孙燕姿"),
        2: ("Two of Us", "The Beatles"),
        3: ("三人游", "方大同"),
        4: ("Four Out of Five", "Arctic Monkeys"),
        5: ("Five Hundred Miles", ""),
        6: ("杀死那个石家庄人", "万能青年旅店"),
        7: ("七里香", "周杰伦"),
        8: ("八", "草东没有派对"),
        9: ("九份的咖啡店", "陈绮贞"),
        10: ("十万嬉皮", "万能青年旅店"),
        11: ("November Rain", "Guns N' Roses"),
        12: ("12:51", "The Strokes"),
        13: ("13", "LANY"),
        14: ("14 Years", "Guns N' Roses"),
        15: ("好不容易", "方大同"),
        16: ("Sixteen Saltines", "Jack White"),
        17: ("Seventeen Going Under", "Sam Fender"),
        18: ("Eighteen", "Pale Waves"),
        19: ("19-2000", "Gorillaz"),
        20: ("Twenties", "Bren Joy"),
        21: ("21 Guns", "Green Day"),
        22: ("二十二", "陶喆"),
        23: ("才二十三", "方大同"),
        24: ("24K Magic", "Bruno Mars"),
        25: ("25", "鸟撞"),
        26: ("SS26", "Charli xcx"),
        27: ("Smells Like Teen Spirit", "Nirvana"),
        28: ("28", "Zach Bryan"),
        29: ("29", "许钧"),
        30: ("三十岁的女人", "赵雷"),
        31: ("31", "(Car, the garden)"),
        32: ("32nd Floor", "Nija"),
        33: ("Episode 33", "She Her Her Hers"),
        34: ("34+35", "Ariana Grande"),
        35: ("35℃", "五條真由美"),
        36: ("36 Degrees", "Placebo"),
        37: ("37", "harper"),
        38: ("38 Years Old", "The Tragically Hip"),
        39: ("39", "Marble Sounds"),
        40: ("40 Days", "Raina Sokolov-Gonzalez"),
        41: ("DISCO 41", "ONEsONE"),
        42: ("Viva La Vida", "Coldplay"),
        43: ("43", "Florist"),
        44: ("44 Seconds Road Movie", "SoulFa"),
        45: ("45", "Bleachers"),
        46: ("Forty Six & 2", "Tool"),
        47: ("47", "Anders Osborne"),
        48: ("48", "Sunny Day Real Estate"),
        49: ("Funk #49", "James Gang"),
        50: ("50 Ways to Leave Your Lover", "Paul Simon")
    ]

    /// What a collection of `showCount` nights has unlocked, newest first, and the next record still sealed.
    static func shelf(showCount: Int) -> FootprintRecordShelf {
        let songs = catalog.keys.sorted().compactMap(song(for:))
        let next = songs.first { $0.number > showCount }
        return FootprintRecordShelf(
            unlocked: Array(songs.filter { $0.number <= showCount }.reversed()),
            next: next,
            remaining: next.map { $0.number - showCount } ?? 0,
            total: songs.count
        )
    }

    static func song(for number: Int) -> FootprintNumberSong? {
        catalog[number].map { FootprintNumberSong(number: number, title: $0.title, artist: $0.artist) }
    }
}
