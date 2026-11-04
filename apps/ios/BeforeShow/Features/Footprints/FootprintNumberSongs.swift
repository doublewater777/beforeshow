import Foundation

/// A song tied to a show count, played on the record for that number.
struct FootprintNumberSong: Equatable, Sendable {
    let number: Int
    let title: String
    let artist: String
    let trackID: Int
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
    /// Track ids from the iTunes store, so covers and previews come back in one lookup.
    private static let catalog: [Int: (title: String, artist: String, trackID: Int)] = [
        1: ("第一天", "孙燕姿", 255921455),
        2: ("Two of Us", "The Beatles", 1441164497),
        3: ("三人游", "方大同", 313404860),
        4: ("Four Out of Five", "Arctic Monkeys", 1367926559),
        5: ("Five Hundred Miles", "The Seekers", 695471856),
        6: ("杀死那个石家庄人", "万能青年旅店", 1538548895),
        7: ("七里香", "周杰伦", 536115195),
        8: ("八", "草东没有派对", 1679884076),
        9: ("September", "Earth, Wind & Fire", 1456623340),
        10: ("十万嬉皮", "万能青年旅店", 1538548885),
        11: ("November Rain", "Guns N' Roses", 1440896193),
        12: ("12:51", "The Strokes", 604783731),
        13: ("13", "LANY", 1440894440),
        14: ("14 Years", "Guns N' Roses", 1389971323),
        15: ("好不容易", "方大同", 540055025),
        16: ("Sixteen Saltines", "Jack White", 519241144),
        17: ("Seventeen Going Under", "Sam Fender", 1577930641),
        18: ("Eighteen", "Pale Waves", 1413399634),
        19: ("19-2000", "Gorillaz", 850576709),
        20: ("Twenties", "Bren Joy", 1557468393),
        21: ("21 Guns", "Green Day", 315611467),
        22: ("二十二", "陶喆", 914664943),
        23: ("才二十三", "方大同", 1762980607),
        24: ("24K Magic", "Bruno Mars", 1161504024),
        25: ("25", "鸟撞", 1524595858),
        26: ("SS26", "Charli xcx", 6774745616),
        27: ("Smells Like Teen Spirit", "Nirvana", 1440783625),
        28: ("28", "Zach Bryan", 1819829902),
        29: ("29", "许钧", 1590994109),
        30: ("三十岁的女人", "赵雷", 1722411239),
        31: ("31", "(Car, the garden)", 1643121483),
        32: ("32nd Floor", "Nija", 1799811471),
        33: ("Episode 33", "She Her Her Hers", 1435990102),
        34: ("34+35", "Ariana Grande", 1553953635),
        35: ("35℃", "きのこ帝国", 1440797374),
        36: ("36 Degrees", "Placebo", 961067971),
        37: ("37", "harper", 1745474393),
        38: ("38 Years Old", "The Tragically Hip", 1440843312),
        39: ("39", "Marble Sounds", 1771040938),
        40: ("40 Days", "Raina Sokolov-Gonzalez", 1780023488),
        41: ("DISCO 41", "ONEsONE", 1807248960),
        42: ("Viva La Vida", "Coldplay", 1122773680),
        43: ("43", "Florist", 1614340471),
        44: ("44 Seconds Road Movie", "SoulFa", 1445519919),
        45: ("45", "Bleachers", 1567285168),
        46: ("Forty Six & 2", "Tool", 1474185342),
        47: ("47", "Anders Osborne", 1881056374),
        48: ("48", "Sunny Day Real Estate", 329697275),
        49: ("Funk #49", "James Gang", 1484423660),
        50: ("50 Ways to Leave Your Lover", "Paul Simon", 380625663)
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
        catalog[number].map { FootprintNumberSong(number: number, title: $0.title, artist: $0.artist, trackID: $0.trackID) }
    }
}
