import XCTest
@testable import BeforeShow

final class ShowDraftTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testDraftSavesUserEditedValuesAfterConfirmation() throws {
        let date = makeDate(year: 2026, month: 7, day: 3)
        var draft = ShowDraft(
            name: "识别出来的名字",
            date: date,
            startTime: makeDate(year: 2026, month: 7, day: 3, hour: 19, minute: 30),
            venueName: "识别场馆",
            source: .screenshotOCR
        )

        draft.name = "用户改好的现场"
        draft.venueName = "用户确认的场馆"
        draft.artist = "用户确认的艺人"

        let show = try draft.makeShow()

        XCTAssertEqual(show.name, "用户改好的现场")
        XCTAssertEqual(show.venueName, "用户确认的场馆")
        XCTAssertEqual(show.artist, "用户确认的艺人")
    }

    func testDraftPassesEndDateAndEndTimeIntoShow() throws {
        let draft = ShowDraft(
            name: "深夜发光 Livehouse",
            date: makeDate(year: 2026, month: 7, day: 8),
            startTime: makeDate(year: 2026, month: 7, day: 8, hour: 23),
            endDate: makeDate(year: 2026, month: 7, day: 9),
            endTime: makeDate(year: 2026, month: 7, day: 9, hour: 1),
            source: .manual
        )

        let show = try draft.makeShow()

        XCTAssertEqual(show.endDate, makeDate(year: 2026, month: 7, day: 9))
        XCTAssertEqual(show.endTime, makeDate(year: 2026, month: 7, day: 9, hour: 1))
        XCTAssertTrue(draft.hasValidEndTime(calendar: calendar))
    }

    func testDraftKeepsMissingEndTimeNilWhenSaved() throws {
        let date = DateComponents(
            calendar: Calendar.current,
            timeZone: Calendar.current.timeZone,
            year: 2026,
            month: 7,
            day: 8
        ).date!
        let startTime = Calendar.current.date(bySettingHour: 19, minute: 30, second: 0, of: date)!
        let draft = ShowDraft(
            name: "默认结束时间现场",
            date: date,
            startTime: startTime,
            source: .manual
        )

        let show = try draft.makeShow()

        XCTAssertNil(show.endDate)
        XCTAssertNil(show.endTime)
    }

    func testDraftCopiesEndDateAndEndTimeFromEditedShow() throws {
        let show = try Show(
            name: "编辑跨天现场",
            date: makeDate(year: 2026, month: 7, day: 8),
            startTime: makeDate(year: 2026, month: 7, day: 8, hour: 23),
            endDate: makeDate(year: 2026, month: 7, day: 9),
            endTime: makeDate(year: 2026, month: 7, day: 9, hour: 1)
        )

        let draft = ShowDraft(show: show)

        XCTAssertEqual(draft.endDate, show.endDate)
        XCTAssertEqual(draft.endTime, show.endTime)
    }

    func testScreenshotOCRProducesEditableDraftAndIgnoresSensitiveTicketFields() throws {
        let text = """
        山海音乐节
        日期：2026-07-03
        时间：19:30
        城市：上海
        场馆：春浪草地
        阵容：落日飞车 / deca joins
        座位：A区
        订单号：SECRET-12345
        手机号：13800000000
        """

        let draft = try XCTUnwrap(ShowScreenshotRecognitionService(calendar: calendar).draft(fromRecognizedText: text))

        XCTAssertEqual(draft.name, "山海音乐节")
        XCTAssertEqual(draft.date, makeDate(year: 2026, month: 7, day: 3))
        XCTAssertEqual(draft.startTime, makeDate(year: 2026, month: 7, day: 3, hour: 19, minute: 30))
        XCTAssertEqual(draft.city, "上海")
        XCTAssertEqual(draft.venueName, "春浪草地")
        XCTAssertEqual(draft.artist, "落日飞车 / deca joins")
        XCTAssertFalse(draft.name.contains("SECRET"))
    }

    func testScreenshotOCRKeepsUsefulPartialFieldsWhenDateIsMissing() throws {
        let text = """
        演出名称：夏夜 Livehouse
        场馆：MAO Livehouse
        城市：上海
        座位：A区
        """

        let draft = try XCTUnwrap(
            ShowScreenshotRecognitionService(calendar: calendar).draft(fromRecognizedText: text)
        )

        XCTAssertEqual(draft.name, "夏夜 Livehouse")
        XCTAssertEqual(draft.city, "上海")
        XCTAssertEqual(draft.venueName, "MAO Livehouse")
        XCTAssertNil(draft.startTime)
    }

    func testScreenshotRecognitionFailureCanFallBackToManualDraft() {
        let draft = ShowScreenshotRecognitionService(calendar: calendar).draft(fromRecognizedText: "订单号：SECRET")

        XCTAssertNil(draft)
    }

    // MARK: - 字段级 provenance（recognizedFields）

    func testScreenshotOCRRecordsRecognizedFieldsIncludingDate() throws {
        let text = """
        山海音乐节
        日期：2026-07-03
        时间：19:30
        城市：上海
        场馆：春浪草地
        阵容：落日飞车 / deca joins
        """

        let draft = try XCTUnwrap(
            ShowScreenshotRecognitionService(calendar: calendar).draft(fromRecognizedText: text)
        )

        XCTAssertEqual(
            draft.recognizedFields,
            [.name, .date, .startTime, .city, .venueName, .artist]
        )
    }

    func testScreenshotOCRWithoutDateDoesNotMarkDateRecognized() throws {
        let text = """
        演出名称：夏夜 Livehouse
        场馆：MAO Livehouse
        城市：上海
        """

        let draft = try XCTUnwrap(
            ShowScreenshotRecognitionService(calendar: calendar).draft(fromRecognizedText: text)
        )

        // 日期回退为今天不算识别成功
        XCTAssertFalse(draft.recognizedFields.contains(.date))
        XCTAssertFalse(draft.recognizedFields.contains(.startTime))
        XCTAssertTrue(draft.recognizedFields.contains(.name))
        XCTAssertTrue(draft.recognizedFields.contains(.city))
        XCTAssertTrue(draft.recognizedFields.contains(.venueName))
    }

    func testLocalLinkParserMarksDateAndPresentFieldsRecognized() throws {
        let parser = ShowLinkDraftParser(calendar: calendar)

        let draft = try parser.draft(
            from: "https://detail.damai.cn/item.htm?date=2026-07-15&time=20:00&name=测试现场&city=上海&venue=测试场馆&artist=测试艺人"
        )

        XCTAssertEqual(
            draft.recognizedFields,
            [.name, .date, .startTime, .city, .venueName, .artist]
        )
    }

    func testLocalLinkParserRejectsLookalikeHosts() {
        let parser = ShowLinkDraftParser(calendar: calendar)

        // 域名必须严格匹配官方域及其子域名，仿冒 / 包含式匹配都算不支持
        XCTAssertThrowsError(try parser.draft(from: "https://notdamai.example.com/item?date=2026-07-15"))
        XCTAssertThrowsError(try parser.draft(from: "https://damai.cn.evil.example/item?date=2026-07-15"))
        XCTAssertThrowsError(try parser.draft(from: "https://showstart.com.evil.example/item?date=2026-07-15"))
    }

    func testLinkParserNormalizesBareHostWithoutScheme() throws {
        // UI 来源 chip 会补 https://；提交解析必须用同一规范化，否则 chip 成功但解析失败
        XCTAssertEqual(
            ShowLinkDraftParser.normalizedLink("detail.damai.cn/item.htm?date=2026-07-15&name=测试"),
            "https://detail.damai.cn/item.htm?date=2026-07-15&name=测试"
        )

        let parser = ShowLinkDraftParser(calendar: calendar)
        let draft = try parser.draft(
            from: "detail.damai.cn/item.htm?date=2026-07-15&time=20:00&name=测试现场&city=上海&venue=测试场馆"
        )
        XCTAssertEqual(draft.name, "测试现场")
        XCTAssertTrue(draft.recognizedFields.contains(.date))
    }

    func testRemoteShowLinkParsingServiceMarksProvenanceWithoutStartTime() async throws {
        let json = """
        {
            "ok": true,
            "draft": {
                "name": "待确认时间的现场",
                "city": "上海",
                "date": "2026-07-15",
                "startTime": null,
                "endDate": null,
                "endTime": null,
                "venueName": "测试场馆",
                "venueAddr": "测试地址",
                "artist": "测试艺人",
                "coverImageURL": null,
                "artistAvatarURLs": [],
                "priceRange": "",
                "source": "damai"
            }
        }
        """
        let service = RemoteShowLinkParsingService(
            client: BeforeShowCloudClient(
                rootURL: URL(string: "https://example.com")!,
                credentials: BeforeShowAppCredentials(
                    appInstanceId: "test-instance",
                    appSignature: "test-signature"
                ),
                session: MockURLSession(data: json.data(using: .utf8)!, statusCode: 200)
            ),
            calendar: calendar
        )

        let draft = try await service.parse(link: "https://detail.damai.cn/item.htm?id=123")

        XCTAssertTrue(draft.recognizedFields.contains(.date))
        XCTAssertFalse(draft.recognizedFields.contains(.startTime))
        XCTAssertTrue(draft.recognizedFields.contains(.name))
        XCTAssertTrue(draft.recognizedFields.contains(.city))
        XCTAssertTrue(draft.recognizedFields.contains(.venueName))
        XCTAssertTrue(draft.recognizedFields.contains(.artist))
    }

    func testMaoyanPosterOCRExtractsNaturalLayoutShowInfo() throws {
        let text = """
        周震南「LOVE & DESIRE」演唱会
        2026 07-04
        北京、华黑生物•將百酸E0M中心
        2026周震南［LOVE&DESIRE」演唱会
        -北京站
        2026.07.04 19:00 周六
        北京 华熙生物•润百颜ECM中心
        猫眼|丝滑抢票上猫眼
        """

        let draft = try XCTUnwrap(ShowScreenshotRecognitionService(calendar: calendar).draft(fromRecognizedText: text))

        XCTAssertTrue(draft.name.contains("周震南"))
        XCTAssertTrue(draft.name.contains("演唱会"))
        XCTAssertEqual(draft.date, makeDate(year: 2026, month: 7, day: 4))
        XCTAssertEqual(draft.startTime, makeDate(year: 2026, month: 7, day: 4, hour: 19))
        XCTAssertEqual(draft.city, "北京市")
        XCTAssertTrue(draft.venueName.contains("华熙生物") || draft.venueName.contains("华黑生物"))
    }

    func testDamaiPosterOCRExtractsSelectedTourStopInsteadOfOtherDates() throws {
        let text = """
        CRWIY IoLs
        桃引
        演唱会
        美怡良巡回逆明会
        杭州＋金沙湖大剧院
        ）1271930|168O1580 4801380 280 180
        杭州•HI LIVE |2026艾怡良「内心引力」
        巡回演唱会—杭州站
        2026.09.12 周六 19:30
        杭州市• 杭州金沙湖大剧院-歌剧厅
        大麦|买票上大麦
        """

        let draft = try XCTUnwrap(ShowScreenshotRecognitionService(calendar: calendar).draft(fromRecognizedText: text))

        XCTAssertTrue(draft.name.contains("艾怡良"))
        XCTAssertTrue(draft.name.contains("内心引力"))
        XCTAssertEqual(draft.date, makeDate(year: 2026, month: 9, day: 12))
        XCTAssertEqual(draft.startTime, makeDate(year: 2026, month: 9, day: 12, hour: 19, minute: 30))
        XCTAssertEqual(draft.city, "杭州市")
        XCTAssertTrue(draft.venueName.contains("金沙湖大剧院"))
    }

    func testShowstartDetailOCRIgnoresPhoneStatusTimeAndExtractsLivehouseInfo() throws {
        let text = """
        22:56
        「汲夜行舟」另类/国风/独立摇
        滚三乐队联合演出 杭州周二场
        #摇滚，#独立
        早鸟39/单人49/双人89
        ¥39-89
        2026.06.16 本周二20:00
        杭州 酒球会
        杭州市西湖区万塘路262号酒球会（杭州店）
        电子票
        阵容
        极境乐队
        艺人
        山枭乐队
        艺人
        """

        let draft = try XCTUnwrap(ShowScreenshotRecognitionService(calendar: calendar).draft(fromRecognizedText: text))

        XCTAssertTrue(draft.name.contains("联合演出"))
        XCTAssertEqual(draft.date, makeDate(year: 2026, month: 6, day: 16))
        XCTAssertEqual(draft.startTime, makeDate(year: 2026, month: 6, day: 16, hour: 20))
        XCTAssertEqual(draft.city, "杭州市")
        XCTAssertTrue(draft.venueName.contains("酒球会"))
    }

    func testDamaiDetailOCRPrefersCurrentPerformanceDateOverTourDateList() throws {
        let text = """
        22:56
        演唱会
        杭州•HI LIVE |2026艾怡良「内心
        引力」巡回演唱会—杭州站
        热卖
        采圳站
        08.15
        杭州站
        09.12
        缺货
        上海站
        07.05
        2026.09.12周六 19:30
        约90分钟（无中场休息）
        杭州市．杭州金沙湖大剧院-歌剧厅
        浙江省杭州市钱塘区下沙街道金沙湖大剧院
        艾怡良
        """

        let draft = try XCTUnwrap(ShowScreenshotRecognitionService(calendar: calendar).draft(fromRecognizedText: text))

        XCTAssertTrue(draft.name.contains("艾怡良") || draft.name.contains("内心"))
        XCTAssertEqual(draft.date, makeDate(year: 2026, month: 9, day: 12))
        XCTAssertEqual(draft.startTime, makeDate(year: 2026, month: 9, day: 12, hour: 19, minute: 30))
        XCTAssertEqual(draft.city, "杭州市")
        XCTAssertTrue(draft.venueName.contains("金沙湖大剧院"))
    }

    func testMaoyanDetailOCRExtractsBasicInfoFromNoticePage() throws {
        let text = """
        「春日海海」2026鹿先森乐队工人
        体育馆演唱会
        6.19
        ¥280-880
        2026.06.19 19:00 周五
        约120分钟（以现场为准）
        北京工人体育馆
        北京 工人体育场北路与工人体育场西路交叉口西南角
        鹿先森乐队
        2026鹿先森乐队工人体育馆演唱会 票务须知
        一、演出基本信息
        • 演出项目：2026鹿先森乐队工人体育馆演唱会
        •演出时间：2026年6月19日 19:00
        • 演出场馆：北京工人体育馆
        """

        let draft = try XCTUnwrap(ShowScreenshotRecognitionService(calendar: calendar).draft(fromRecognizedText: text))

        XCTAssertTrue(draft.name.contains("鹿先森"))
        XCTAssertEqual(draft.date, makeDate(year: 2026, month: 6, day: 19))
        XCTAssertEqual(draft.startTime, makeDate(year: 2026, month: 6, day: 19, hour: 19))
        XCTAssertEqual(draft.city, "北京市")
        XCTAssertEqual(draft.venueName, "北京工人体育馆")
    }

    func testLinkParserUsesServiceAndReturnsDraft() async throws {
        let expectedDraft = ShowDraft(
            name: "夏夜Livehouse",
            date: makeDate(year: 2026, month: 7, day: 3),
            startTime: makeDate(year: 2026, month: 7, day: 3, hour: 20),
            city: "成都",
            venueName: "小酒馆",
            source: .link
        )
        let parser = ShowLinkDraftParser(service: MockShowLinkParsingService(result: expectedDraft))

        let draft = try await parser.draft(from: "https://detail.damai.cn/item.htm?id=123")

        XCTAssertEqual(draft.source, .link)
        XCTAssertEqual(draft.name, "夏夜Livehouse")
        XCTAssertEqual(draft.date, makeDate(year: 2026, month: 7, day: 3))
        XCTAssertEqual(draft.startTime, makeDate(year: 2026, month: 7, day: 3, hour: 20))
        XCTAssertEqual(draft.city, "成都")
        XCTAssertEqual(draft.venueName, "小酒馆")
    }

    func testLinkParserPropagatesUnsupportedSourceError() async {
        let parser = ShowLinkDraftParser(service: MockShowLinkParsingService(error: ShowLinkParsingError.unsupportedSource))

        do {
            _ = try await parser.draft(from: "https://example.com/show/123")
            XCTFail("Expected unsupported source error")
        } catch {
            XCTAssertEqual(error as? ShowLinkParsingError, .unsupportedSource)
        }
    }

    func testLinkFailurePresentationDistinguishesUnsupportedAndNetworkErrors() {
        let unsupported = AddShowLinkFailurePresentation.resolve(
            ShowLinkParsingError.unsupportedSource
        )
        let network = AddShowLinkFailurePresentation.resolve(
            ShowLinkParsingError.networkFailure
        )

        XCTAssertEqual(unsupported.title, "这个链接暂不支持")
        XCTAssertTrue(unsupported.message.contains("大麦"))
        XCTAssertEqual(network.title, "网络连接失败")
        XCTAssertTrue(network.message.contains("重试"))
        XCTAssertNotEqual(network, unsupported)
    }

    func testShowLinkPlatformCatalogRecognizesSupportedHostsAndRejectsLookalikes() {
        let supported: [(String, String)] = [
            ("m.damai.cn", "大麦"),
            ("wap.showstart.com", "秀动"),
            ("show.maoyan.com", "猫眼"),
            ("m.piaoxingqiu.com", "票星球"),
            ("mobile.livelab.com.cn", "纷玩岛"),
            ("www.ticketmaster.com", "Ticketmaster"),
            ("www.ticketmaster.co.uk", "Ticketmaster"),
            ("dice.fm", "DICE"),
            ("www.axs.com", "AXS"),
            ("www.livenation.cn", "Live Nation"),
            ("www.livenation.co.uk", "Live Nation"),
            ("livenation.app.link", "Live Nation")
        ]

        for (host, expected) in supported {
            XCTAssertEqual(ShowLinkPlatformCatalog.displayName(forHost: host), expected, host)
        }

        let lookalikes = [
            "damai.cn.evil.example",
            "showstart.com.evil.example",
            "maoyan.com.evil.example",
            "piaoxingqiu.com.evil.example",
            "livelab.com.cn.evil.example",
            "ticketmaster.com.evil.example",
            "dice.fm.evil.example",
            "axs.com.evil.example",
            "livenation.com.evil.example"
        ]
        for host in lookalikes {
            XCTAssertNil(ShowLinkPlatformCatalog.displayName(forHost: host), host)
        }
    }

    func testLinkUICopyListsAllSupportedPlatforms() {
        let unsupported = AddShowLinkFailurePresentation.resolve(
            ShowLinkParsingError.unsupportedSource
        )
        let names = ["大麦", "秀动", "猫眼", "票星球", "纷玩岛", "Ticketmaster", "DICE", "AXS", "Live Nation"]

        for name in names {
            XCTAssertTrue(unsupported.message.contains(name), name)
        }
        XCTAssertEqual(
            ShowLinkPlatformCatalog.supportSummary,
            "大麦、秀动、猫眼、票星球、纷玩岛、Ticketmaster、DICE、AXS、Live Nation"
        )
        XCTAssertEqual(AddShowMethodCopy.link.subtitle, "粘贴支持平台的票务链接，需要联网解析。")
    }

    func testLocalLinkParserOnlySupportsDamaiAndShowstart() throws {
        let parser = ShowLinkDraftParser(calendar: calendar)

        XCTAssertNoThrow(try parser.draft(from: "https://detail.damai.cn/item.htm?date=2026-07-15&time=20:00&name=测试现场"))
        XCTAssertNoThrow(try parser.draft(from: "https://wap.showstart.com/activity/123?date=2026-07-15&time=20:00&name=测试现场"))
        XCTAssertThrowsError(try parser.draft(from: "https://m.maoyan.com/asgard/shows/123?date=2026-07-15&time=20:00"))
        XCTAssertThrowsError(try parser.draft(from: "https://www.livenation.cn/show/123?date=2026-07-15&time=20:00"))
    }

    func testShowstartSingleDayFestivalDraftCanSaveWithoutEndTime() throws {
        let draft = ShowDraft(
            name: "第二届速煞朋克音乐节",
            date: makeDate(year: 2026, month: 6, day: 27),
            startTime: makeDate(year: 2026, month: 6, day: 27, hour: 19),
            endDate: makeDate(year: 2026, month: 6, day: 27),
            city: "杭州",
            venueName: "酒球会",
            artist: "硬鸡乐队, 开膛RIPPER",
            coverImageURL: "https://example.com/showstart-cover.jpg",
            source: .link
        )

        let show = try draft.makeShow()
        XCTAssertEqual(show.endDate, makeDate(year: 2026, month: 6, day: 27))
        XCTAssertNil(show.endTime)
    }

    func testRemoteShowLinkParsingServiceMapsBackendResponse() async throws {
        let json = """
        {
            "ok": true,
            "draft": {
                "name": "测试现场",
                "city": "上海",
                "date": "2026-07-15",
                "startTime": "20:00",
                "endDate": "2026-07-16",
                "endTime": "00:30",
                "venueName": "测试场馆",
                "venueAddr": "测试地址",
                "artist": "测试艺人",
                "coverImageURL": "https://example.com/show-cover.jpg",
                "artistAvatarURLs": ["https://example.com/artist-a.jpg", "https://example.com/artist-b.jpg"],
                "priceRange": "200-400",
                "source": "showstart"
            }
        }
        """
        let service = RemoteShowLinkParsingService(
            client: BeforeShowCloudClient(
                rootURL: URL(string: "https://example.com")!,
                credentials: BeforeShowAppCredentials(
                    appInstanceId: "test-instance",
                    appSignature: "test-signature"
                ),
                session: MockURLSession(data: json.data(using: .utf8)!, statusCode: 200)
            ),
            calendar: calendar
        )

        let draft = try await service.parse(link: "https://wap.showstart.com/activity/123")

        XCTAssertEqual(draft.name, "测试现场")
        XCTAssertEqual(draft.city, "上海")
        XCTAssertEqual(draft.date, makeDate(year: 2026, month: 7, day: 15))
        XCTAssertEqual(draft.startTime, makeDate(year: 2026, month: 7, day: 15, hour: 20))
        XCTAssertEqual(draft.endDate, makeDate(year: 2026, month: 7, day: 16))
        XCTAssertEqual(draft.endTime, makeDate(year: 2026, month: 7, day: 16, hour: 0, minute: 30))
        XCTAssertEqual(draft.venueName, "测试场馆")
        XCTAssertEqual(draft.venueAddress, "测试地址")
        XCTAssertEqual(draft.artist, "测试艺人")
        XCTAssertEqual(draft.coverImageURL, "https://example.com/show-cover.jpg")
        XCTAssertEqual(draft.artistAvatarURLs, [
            "https://example.com/artist-a.jpg",
            "https://example.com/artist-b.jpg"
        ])
        XCTAssertEqual(draft.source, .link)
    }

    func testRemoteShowLinkParsingServiceKeepsMissingStartTimeUnconfirmed() async throws {
        let json = """
        {
            "ok": true,
            "draft": {
                "name": "待确认时间的现场",
                "city": "上海",
                "date": "2026-07-15",
                "startTime": null,
                "endDate": null,
                "endTime": null,
                "venueName": "测试场馆",
                "venueAddr": "测试地址",
                "artist": "测试艺人",
                "coverImageURL": null,
                "artistAvatarURLs": [],
                "priceRange": "",
                "source": "damai"
            }
        }
        """
        let service = RemoteShowLinkParsingService(
            client: BeforeShowCloudClient(
                rootURL: URL(string: "https://example.com")!,
                credentials: BeforeShowAppCredentials(
                    appInstanceId: "test-instance",
                    appSignature: "test-signature"
                ),
                session: MockURLSession(data: json.data(using: .utf8)!, statusCode: 200)
            ),
            calendar: calendar
        )

        let draft = try await service.parse(link: "https://detail.damai.cn/item.htm?id=123")

        XCTAssertNil(draft.startTime)
        XCTAssertThrowsError(try draft.makeShow())
    }

    func testDraftWithoutStartTimeCannotCreateShow() {
        let draft = ShowDraft(
            name: "缺少时间的现场",
            date: makeDate(year: 2026, month: 7, day: 15),
            source: .link
        )

        XCTAssertThrowsError(try draft.makeShow())
    }

    func testApplyDraftIsSingleEditSeamMatchingMakeShowNormalization() throws {
        let show = try Show(
            name: "旧名字",
            date: makeDate(year: 2026, month: 7, day: 1),
            startTime: makeDate(year: 2026, month: 7, day: 1, hour: 20)
        )
        show.markPostponed(newDate: nil)

        let draft = ShowDraft(
            name: "  新名字  ",
            date: makeDate(year: 2026, month: 8, day: 2),
            startTime: makeDate(year: 2026, month: 8, day: 2, hour: 19, minute: 30),
            city: "  杭州  ",
            venueName: "   ",
            artist: "艺人",
            coverImageURL: "https://example.com/c.jpg",
            source: .manual
        )

        try show.apply(draft)

        XCTAssertEqual(show.name, "新名字")
        XCTAssertEqual(show.date, makeDate(year: 2026, month: 8, day: 2))
        XCTAssertEqual(show.startTime, makeDate(year: 2026, month: 8, day: 2, hour: 19, minute: 30))
        XCTAssertEqual(show.city, "杭州")
        XCTAssertNil(show.venueName)
        XCTAssertEqual(show.artist, "艺人")
        XCTAssertEqual(show.coverImageURL, "https://example.com/c.jpg")
        // Edit must not clear 现场变更
        XCTAssertEqual(show.changeStatus, .postponed)

        let created = try draft.makeShow()
        XCTAssertEqual(created.name, show.name)
        XCTAssertEqual(created.city, show.city)
        XCTAssertNil(created.venueName)
    }

    func testApplyDraftRejectsEmptyNameAndInvalidEndTime() throws {
        let show = try Show(
            name: "有效",
            date: makeDate(year: 2026, month: 7, day: 1),
            startTime: makeDate(year: 2026, month: 7, day: 1, hour: 20)
        )

        var emptyName = ShowDraft(
            name: "   ",
            date: makeDate(year: 2026, month: 7, day: 1),
            startTime: makeDate(year: 2026, month: 7, day: 1, hour: 20)
        )
        XCTAssertThrowsError(try show.apply(emptyName)) { error in
            XCTAssertEqual(error as? ShowValidationError, .emptyName)
        }

        let invalidEnd = ShowDraft(
            name: "仍有效名",
            date: makeDate(year: 2026, month: 7, day: 2),
            startTime: makeDate(year: 2026, month: 7, day: 2, hour: 20),
            endDate: makeDate(year: 2026, month: 7, day: 1),
            endTime: makeDate(year: 2026, month: 7, day: 1, hour: 22)
        )
        XCTAssertThrowsError(try show.apply(invalidEnd)) { error in
            XCTAssertEqual(error as? ShowValidationError, .invalidEndTime)
        }
        XCTAssertEqual(show.name, "有效")
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date!
    }
}

private struct MockShowLinkParsingService: ShowLinkParsingService {
    var result: ShowDraft?
    var error: Error?

    func parse(link: String) async throws -> ShowDraft {
        if let error {
            throw error
        }
        return try XCTUnwrap(result)
    }
}

private struct MockURLSession: URLSessionProtocol {
    var data: Data
    var statusCode: Int

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
