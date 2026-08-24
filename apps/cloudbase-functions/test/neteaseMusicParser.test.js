import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { parseShowLink } from "../src/functions/parseShowLink/index.js";
import {
  fetchNetEaseMusicConcert,
  parseNetEaseMusicConcert
} from "../src/functions/parseShowLink/neteaseMusicParser.js";

const DETAIL = {
  id: 33750652,
  title: "“听见·五月天”MAYDAY金典演奏音乐会·武汉站",
  cover: "https://p1.music.126.net/cover.jpg",
  artistInfoList: [
    { name: "五月天", img: "https://p1.music.126.net/artist.jpg" }
  ],
  minPrice: 78,
  maxPrice: 380,
  startTime: 1789212600000,
  endTime: 1789218000000,
  city: "武汉市",
  venue: "珞珈山剧院",
  address: "武汉市 珞珈山剧院"
};

describe("NetEase Music concert adapter", () => {
  it("posts the concert ID to the public detail endpoint", async () => {
    let request;
    const fetch = async (url, options) => {
      request = { url, options };
      return {
        ok: true,
        status: 200,
        json: async () => ({ code: 200, data: DETAIL })
      };
    };

    const detail = await fetchNetEaseMusicConcert({ concertId: "33750652", fetch });

    assert.equal(detail.id, 33750652);
    assert.equal(request.url, "https://st.music.163.com/api/concert/detail/v3");
    assert.equal(request.options.method, "POST");
    assert.equal(request.options.body, "concertId=33750652");
  });

  it("maps concert details into the BeforeShow draft contract", () => {
    const draft = parseNetEaseMusicConcert(DETAIL);

    assert.equal(draft.name, DETAIL.title);
    assert.equal(draft.city, "武汉");
    assert.equal(draft.date, "2026-09-12");
    assert.equal(draft.startTime, "19:30");
    assert.equal(draft.startDateTime, "2026-09-12T19:30:00+08:00");
    assert.equal(draft.endDateTime, "2026-09-12T21:00:00+08:00");
    assert.equal(draft.timeZoneIdentifier, "Asia/Shanghai");
    assert.equal(draft.venueName, DETAIL.venue);
    assert.equal(draft.venueAddr, DETAIL.address);
    assert.equal(draft.artist, "五月天");
    assert.deepEqual(draft.artistAvatarURLs, ["https://p1.music.126.net/artist.jpg"]);
    assert.equal(draft.coverImageURL, DETAIL.cover);
    assert.equal(draft.priceRange, "78 - 380");
    assert.equal(draft.source, "neteasemusic");
  });

  it("dispatches a shared detail link through the NetEase Music adapter", async () => {
    const fetch = async () => ({
      ok: true,
      status: 200,
      json: async () => ({ code: 200, data: DETAIL })
    });

    const draft = await parseShowLink(
      "https://st.music.163.com/g/show/detail?concertId=33750652",
      { fetch }
    );

    assert.equal(draft.name, DETAIL.title);
    assert.equal(draft.source, "neteasemusic");
  });

  it("does not parse the ticket homepage or non-detail NetEase Music pages", async () => {
    await assert.rejects(
      parseShowLink("https://st.music.163.com/g/show"),
      (error) => error?.code === "UNSUPPORTED_PLATFORM"
    );
    await assert.rejects(
      parseShowLink("https://st.music.163.com/song?concertId=33750652"),
      (error) => error?.code === "UNSUPPORTED_PLATFORM"
    );
  });

  it("rejects a response without concert data", async () => {
    const fetch = async () => ({
      ok: true,
      status: 200,
      json: async () => ({ code: 404, msg: "not found" })
    });

    await assert.rejects(
      fetchNetEaseMusicConcert({ concertId: "33750652", fetch }),
      /NetEase Music API error/
    );
  });
});
