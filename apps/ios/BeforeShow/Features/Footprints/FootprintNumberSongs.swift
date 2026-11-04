import Foundation

/// A song whose title carries a show count, played on the record for that number.
struct FootprintNumberSong: Equatable, Sendable {
    let number: Int
    let title: String
    let artist: String
}

/// Hand-picked: only numbers with a song that fits a night out. No song is better than a forced one.
enum FootprintNumberSongs {
    private static let catalog: [Int: (title: String, artist: String)] = [
        1: ("第一天", "孙燕姿"),
        2: ("Two of Us", "The Beatles"),
        3: ("三人游", "方大同"),
        4: ("4 Minutes", "Madonna"),
        5: ("Five Years", "David Bowie"),
        7: ("Seven Nation Army", "The White Stripes"),
        8: ("Eight Days a Week", "The Beatles"),
        9: ("9 to 5", "Dolly Parton"),
        10: ("十年", "陈奕迅"),
        17: ("十七岁", "刘德华"),
        21: ("21 Guns", "Green Day"),
        22: ("22", "Taylor Swift"),
        25: ("25 or 6 to 4", "Chicago"),
        30: ("三十岁的女人", "赵雷"),
        50: ("50 Ways to Leave Your Lover", "Paul Simon"),
        99: ("99 Luftballons", "Nena"),
        100: ("100种生活", "卢广仲")
    ]

    static func song(for number: Int) -> FootprintNumberSong? {
        catalog[number].map { FootprintNumberSong(number: number, title: $0.title, artist: $0.artist) }
    }
}
