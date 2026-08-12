import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  detectPlatform,
  extractShowUrl,
  normalizeUrl,
  UnsupportedPlatformError
} from "../src/functions/parseShowLink/platformDetector.js";
import {
  computeMtopSign,
  fetchMtopToken,
  fetchDamaiDetail,
  parseDamaiDetail
} from "../src/functions/parseShowLink/damaiParser.js";
import {
  fetchShowStartDetail,
  parseShowStartDetail
} from "../src/functions/parseShowLink/showstartParser.js";

describe("parseShowLink platform detection", () => {
  it("detects Damai mobile URLs", () => {
    assert.equal(
      detectPlatform("https://m.damai.cn/shows/item.html?itemId=1054603723374"),
      "damai"
    );
  });

  it("detects Damai PC URLs", () => {
    assert.equal(
      detectPlatform("https://detail.damai.cn/item.htm?id=1055935539093"),
      "damai"
    );
  });

  it("detects ShowStart mobile URLs", () => {
    assert.equal(
      detectPlatform("https://wap.showstart.com/pages/activity/detail/detail?activityId=298012"),
      "showstart"
    );
  });

  it("rejects unsupported platforms", () => {
    assert.throws(
      () => detectPlatform("https://example.com/show/123"),
      (error) => error instanceof UnsupportedPlatformError
    );
  });

  it("rejects spoofed Damai host that only contains damai.cn as suffix label", () => {
    assert.throws(
      () => detectPlatform("https://damai.cn.evil.example/?id=1054603723374"),
      (error) => error instanceof UnsupportedPlatformError
    );
  });

  it("rejects host that only looks like Damai (notdamai.cn)", () => {
    assert.throws(
      () => detectPlatform("https://notdamai.cn/item.htm?id=1054603723374"),
      (error) => error instanceof UnsupportedPlatformError
    );
  });

  it("rejects non-ticket host that only mentions damai.cn in query", () => {
    assert.throws(
      () => detectPlatform("https://evil.example/?redirect=damai.cn&id=1054603723374"),
      (error) => error instanceof UnsupportedPlatformError
    );
  });

  it("rejects spoofed ShowStart host", () => {
    assert.throws(
      () => detectPlatform("https://showstart.com.evil.example/?activityId=298012"),
      (error) => error instanceof UnsupportedPlatformError
    );
  });

  it("accepts bare Damai host without scheme (matches client chip)", () => {
    assert.equal(
      detectPlatform("m.damai.cn/shows/item.html?itemId=1054603723374"),
      "damai"
    );
    const normalized = normalizeUrl("m.damai.cn/shows/item.html?itemId=1054603723374");
    assert.equal(normalized.platform, "damai");
    assert.equal(normalized.itemId, "1054603723374");
  });

  it("normalizes Damai mobile URL to canonical PC item ID", () => {
    const normalized = normalizeUrl("https://m.damai.cn/shows/item.html?itemId=1054603723374");
    assert.equal(normalized.platform, "damai");
    assert.equal(normalized.itemId, "1054603723374");
  });

  it("extracts ShowStart activity ID from mobile URL", () => {
    const normalized = normalizeUrl("https://wap.showstart.com/pages/activity/detail/detail?activityId=295771");
    assert.equal(normalized.platform, "showstart");
    assert.equal(normalized.activityId, "295771");
  });

  it("extracts ShowStart URL from shared app text", () => {
    const sharedText = "秀动：&&`buhwhux,389103-5576444&&【秀动】https://wap.showstart.com/pages/activity/detail/detail?activityId=298012【康士坦的变化球「犬的视线」 2026巡演 杭州站】点击链接可直接查看";

    assert.equal(
      extractShowUrl(sharedText),
      "https://wap.showstart.com/pages/activity/detail/detail?activityId=298012"
    );

    const normalized = normalizeUrl(sharedText);
    assert.equal(normalized.platform, "showstart");
    assert.equal(normalized.activityId, "298012");
  });

  it("normalizes full-width pasted URLs before platform detection", () => {
    const normalized = normalizeUrl("ｈｔｔｐｓ：／／ｍ．ｄａｍａｉ．ｃｎ／ｓｈｏｗｓ／ｉｔｅｍ．ｈｔｍｌ？ｉｔｅｍＩｄ＝１０５４６０３７２３３７４");

    assert.equal(normalized.platform, "damai");
    assert.equal(normalized.itemId, "1054603723374");
  });

  it("stops extracted URLs at sentence punctuation and following Chinese text", () => {
    assert.equal(
      extractShowUrl("https://dice.fm/event/foo。回到开场前"),
      "https://dice.fm/event/foo"
    );
    assert.equal(
      extractShowUrl("https://dice.fm/event/foo, please open it"),
      "https://dice.fm/event/foo"
    );
  });
});

describe("Damai mtop parser", () => {
  it("computes mtop sign with MD5(token&t&appKey&data)", () => {
    const sign = computeMtopSign({
      token: "abc123",
      t: "1234567890",
      appKey: "12574478",
      data: "{\"itemId\":\"1\"}"
    });
    assert.equal(sign, "fd3d4f01ba0dab2d7f4d0464a46a25c9");
  });

  it("fetches mtop token from Set-Cookie header", async () => {
    const fetch = async () => ({
      headers: {
        get(name) {
          if (name === "set-cookie") {
            return "_m_h5_tk=a37209c5dd1be02a8c03242901e2d0c9_1781542491814; path=/; domain=.damai.cn";
          }
          return null;
        }
      },
      text: async () => '{"ret":["FAIL_SYS_TOKEN_EMPTY"]}'
    });

    const { token, cookies } = await fetchMtopToken({ fetch });
    assert.equal(token, "a37209c5dd1be02a8c03242901e2d0c9");
    assert.ok(cookies.includes("_m_h5_tk"));
  });

  it("fetches Damai detail using computed sign and token", async () => {
    let requestedUrl;
    const fetch = async (url) => {
      requestedUrl = url;
      if (url.includes("sign=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")) {
        return {
          headers: {
            get: (name) => name === "set-cookie"
              ? "_m_h5_tk=a37209c5dd1be02a8c03242901e2d0c9_9999999999999; path=/; domain=.damai.cn"
              : null
          },
          text: async () => "{}"
        };
      }

      return {
        ok: true,
        status: 200,
        text: async () => JSON.stringify({
          api: "mtop.damai.item.detail.getdetail",
          data: {
            item: {
              itemName: "【杭州】测试现场",
              cityName: "杭州市",
              showTime: "2026.08.22 周六 19:00",
              showDuration: "约90分钟",
              itemPics: { itemPicList: [{ picUrl: "https://example.com/damai-cover.jpg" }] }
            },
            venue: {
              venueName: "测试场馆",
              venueAddr: "测试地址"
            },
            price: { range: "380-1580" },
            guide: {
              guideCat: "演唱会",
              artists: [{ name: "测试艺人", picUrl: "https://example.com/artist-avatar.jpg" }]
            }
          }
        })
      };
    };

    const detail = await fetchDamaiDetail({ itemId: "1057554781223", fetch });
    assert.equal(detail.item.itemName, "【杭州】测试现场");
    assert.ok(requestedUrl.includes("sign="));
  });

  it("parses Damai detail into show draft fields", () => {
    const draft = parseDamaiDetail({
      item: {
        itemName: "【杭州】2026喻言「榆野岛」巡回演唱会收官场-杭州站",
        cityName: "杭州市",
        showTime: "2026.08.22 周六 19:00",
        itemPics: { itemPicList: [{ picUrl: "https://example.com/damai-cover.jpg" }] }
      },
      venue: {
        venueName: "杭州奥体中心网球中心",
        venueAddr: "杭州市"
      },
      price: { range: "380-1580" },
      guide: {
        guideCat: "演唱会",
        artists: [{ name: "喻言", picUrl: "https://example.com/artist-avatar.jpg" }]
      }
    });

    assert.equal(draft.name, "2026喻言「榆野岛」巡回演唱会收官场-杭州站");
    assert.equal(draft.city, "杭州");
    assert.equal(draft.venueName, "杭州奥体中心网球中心");
    assert.equal(draft.artist, "喻言");
    assert.equal(draft.date, "2026-08-22");
    assert.equal(draft.startTime, "19:00");
    assert.equal(draft.priceRange, "380-1580");
    assert.equal(draft.coverImageURL, "https://example.com/damai-cover.jpg");
    assert.deepEqual(draft.artistAvatarURLs, ["https://example.com/artist-avatar.jpg"]);
  });
});

describe("ShowStart parser", () => {
  it("fetches ShowStart detail through the signed API path", async () => {
    const requested = [];
    const fetch = async (url, options) => {
      requested.push({ url, options });

      if (url.endsWith("/v3/waf/gettoken")) {
        return {
          text: async () => JSON.stringify({
            state: "1",
            result: {
              accessToken: {
                access_token: "access-token",
                expire: Math.floor(Date.now() / 1000) + 300
              },
              idToken: { id_token: "" }
            }
          })
        };
      }

      return {
        text: async () => JSON.stringify({
          state: "1",
          result: {
            activityName: "测试秀动现场",
            avatar: "https://example.com/showstart-cover.jpg",
            showTime: "2026.07.11 周六 20:00",
            site: { cityName: "杭州", name: "MAO Livehouse杭州" },
            sessionUserInfos: [{ userInfos: [{ name: "测试艺人", avatar: "https://example.com/artist-avatar.jpg" }] }]
          }
        })
      };
    };

    const detail = await fetchShowStartDetail({
      activityId: "298012",
      fetch
    });

    assert.equal(detail.activityName, "测试秀动现场");
    assert.equal(requested.length, 2);
    assert.ok(requested[0].url.endsWith("/v3/waf/gettoken"));
    assert.ok(requested[1].url.endsWith("/v3/wap/activity/details"));
    assert.equal(requested[1].options.headers.cusat, "access-token");
    assert.equal(
      requested[1].options.headers.cdeviceno,
      requested[0].options.headers.cdeviceno
    );
    assert.match(requested[1].options.headers.crpsign, /^[a-f0-9]{32}$/);
  });

  it("throws the signed API error directly", async () => {
    const fetch = async () => ({
      text: async () => JSON.stringify({
        state: "sys002",
        msg: "参数校验失败"
      })
    });

    await assert.rejects(
      fetchShowStartDetail({
        activityId: "298012",
        fetch
      }),
      /ShowStart API error: 参数校验失败/
    );
  });

  it("parses ShowStart festival detail into show draft fields", () => {
    const draft = parseShowStartDetail({
      activityId: 295771,
      activityName: "第二届速煞朋克音乐节",
      avatar: "https://example.com/showstart-cover.jpg",
      price: "¥99 - 888",
      showTime: "2026.06.27 周六 19:00",
      site: {
        name: "酒球会",
        address: "杭州市西湖区万塘路262号酒球会(杭州店)",
        cityName: "杭州"
      },
      activityTag: "朋克摇滚,硬核朋克,斯卡朋克",
      sessionUserInfos: [
        {
          title: "06月27日",
          userInfos: [
            { name: "硬鸡乐队", avatar: "https://example.com/yingji.jpg" },
            { name: "开膛RIPPER", avatar: "https://example.com/ripper.jpg" }
          ]
        }
      ]
    });

    assert.equal(draft.name, "第二届速煞朋克音乐节");
    assert.equal(draft.city, "杭州");
    assert.equal(draft.venueName, "酒球会");
    assert.equal(draft.artist, "硬鸡乐队, 开膛RIPPER");
    assert.equal(draft.date, "2026-06-27");
    assert.equal(draft.startTime, "19:00");
    assert.equal(draft.priceRange, "99 - 888");
    assert.equal(draft.coverImageURL, "https://example.com/showstart-cover.jpg");
    assert.deepEqual(draft.artistAvatarURLs, [
      "https://example.com/yingji.jpg",
      "https://example.com/ripper.jpg"
    ]);
  });

  it("parses ShowStart livehouse detail into show draft fields", () => {
    const draft = parseShowStartDetail({
      activityId: 298012,
      activityName: "康士坦的变化球「犬的视线」 2026巡演 杭州站",
      price: "¥220",
      showTime: "2026.07.12 周六 20:00",
      site: {
        name: "MAO Livehouse杭州",
        address: "杭州市上城区中山南路77号尚城1157·利星三楼",
        cityName: "杭州"
      },
      activityTag: "摇滚",
      sessionUserInfos: [
        {
          title: "07月12日",
          userInfos: [
            { name: "康士坦的变化球", avatar: "https://example.com/kst.jpg" }
          ]
        }
      ]
    });

    assert.equal(draft.name, "康士坦的变化球「犬的视线」 2026巡演 杭州站");
    assert.equal(draft.artist, "康士坦的变化球");
    assert.deepEqual(draft.artistAvatarURLs, ["https://example.com/kst.jpg"]);
  });
});
