import XCTest
@testable import BeforeShow

final class ShowLinkPlatformCatalogTests: XCTestCase {
    func testRecognizesSupportedOfficialHosts() {
        let cases: [(String, String)] = [
            ("m.damai.cn", "大麦"),
            ("wap.showstart.com", "秀动"),
            ("show.maoyan.com", "猫眼"),
            ("m.piaoxingqiu.com", "票星球"),
            ("mobile.livelab.com.cn", "纷玩岛"),
            ("www.ticketmaster.com", "Ticketmaster"),
            ("www.ticketmaster.co.uk", "Ticketmaster"),
            ("www.ticketmaster.com.au", "Ticketmaster"),
            ("dice.fm", "DICE"),
            ("www.axs.com", "AXS")
        ]

        for (host, expectedName) in cases {
            XCTAssertEqual(
                ShowLinkPlatformCatalog.displayName(forHost: host),
                expectedName,
                "host: \(host)"
            )
        }
    }

    func testRejectsLookalikeHosts() {
        let spoofedHosts = [
            "damai.cn.evil.example",
            "showstart.com.evil.example",
            "maoyan.com.evil.example",
            "piaoxingqiu.com.evil.example",
            "livelab.com.cn.evil.example",
            "ticketmaster.com.evil.example",
            "dice.fm.evil.example",
            "axs.com.evil.example"
        ]

        for host in spoofedHosts {
            XCTAssertNil(ShowLinkPlatformCatalog.displayName(forHost: host), "host: \(host)")
        }
    }

    func testSupportSummaryListsAllEightPlatforms() {
        XCTAssertEqual(
            ShowLinkPlatformCatalog.supportSummary,
            "大麦、秀动、猫眼、票星球、纷玩岛、Ticketmaster、DICE、AXS"
        )
    }
}
