import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { parseShowLink } from "../src/functions/parseShowLink/index.js";
import {
  fetchFenwandaoProjectInfo,
  parseFenwandaoProject
} from "../src/functions/parseShowLink/fenwandaoParser.js";

const PROJECT_ID = "271";
const SHARE_URL =
  "https://mobile.livelab.com.cn/hppreview/pages/buyTickets/step1?channel=weibo&id=271&type=1";

const PROJECT_RESPONSE = {
  code: 10000,
  msg: "操作成功",
  data: {
    projectId: 271,
    projectName: "【深圳】告五人第一次新世界巡回演唱会 【宇宙的有趣 AROUND THE NEW WORLD】深圳站",
    nameDisplay: "【深圳】告五人第一次新世界巡回演唱会 【宇宙的有趣 AROUND THE NEW WORLD】深圳站",
    poster: "https://livelabassets.livelab.com.cn/images/ad/1689577296835.2002.jpg",
    lowPrice: 380,
    highPrice: 980,
    projectStartDate: "2023/08/19",
    projectEndDate: "2023/08/20",
    timeDisplay: "2023.08.19-2023.08.20",
    projectCity: "深圳",
    venueInfo: {
      name: "华润深圳湾体育中心“春茧”体育馆",
      city: "深圳",
      address: "深圳市·深圳湾体育中心-体育馆"
    },
    watchNotices: [
      { name: "主要演员", tag: "artists", content: "告五人" }
    ]
  }
};

describe("fenwandao project-info API parser", () => {
  it("maps the project response to the BeforeShow draft contract", () => {
    const draft = parseFenwandaoProject(PROJECT_RESPONSE.data);

    assert.deepEqual(draft, {
      name: "【深圳】告五人第一次新世界巡回演唱会 【宇宙的有趣 AROUND THE NEW WORLD】深圳站",
      city: "深圳",
      date: "2023-08-19",
      startTime: "",
      endDate: "2023-08-20",
      venueName: "华润深圳湾体育中心“春茧”体育馆",
      venueAddr: "深圳市·深圳湾体育中心-体育馆",
      artist: "告五人",
      coverImageURL: "https://livelabassets.livelab.com.cn/images/ad/1689577296835.2002.jpg",
      artistAvatarURLs: [],
      priceRange: "380 - 980",
      source: "fenwandao"
    });
  });

  it("extracts start/end time from timeDisplay when a clock is present", () => {
    const payload = structuredClone(PROJECT_RESPONSE);
    payload.data.timeDisplay = "2023.08.19 19:30-2023.08.20 21:00";

    const draft = parseFenwandaoProject(payload.data);
    assert.equal(draft.startTime, "19:30");
    assert.equal(draft.endTime, "21:00");
  });

  it("keeps a single price when low and high are equal", () => {
    const payload = structuredClone(PROJECT_RESPONSE);
    payload.data.highPrice = 380;

    assert.equal(parseFenwandaoProject(payload.data).priceRange, "380");
  });

  it("drops malformed dates and clocks instead of normalizing them", () => {
    const payload = structuredClone(PROJECT_RESPONSE);
    payload.data.projectStartDate = "2026-02-31";
    payload.data.timeDisplay = "24:60";

    const draft = parseFenwandaoProject(payload.data);
    assert.equal(draft.date, "");
    assert.equal(draft.startTime, "");
  });

  it("uses nameDisplay when projectName is missing", () => {
    const payload = structuredClone(PROJECT_RESPONSE);
    delete payload.data.projectName;

    assert.equal(
      parseFenwandaoProject(payload.data).name,
      payload.data.nameDisplay
    );
  });

  it("uses the injected fetch and sends the project-info request", async () => {
    let requestedUrl;
    let requestedOptions;
    const fetch = async (url, options) => {
      requestedUrl = url;
      requestedOptions = options;
      return { ok: true, status: 200, json: async () => PROJECT_RESPONSE };
    };

    const draft = await fetchFenwandaoProjectInfo({ projectId: PROJECT_ID, fetch });

    assert.equal(draft.projectName, PROJECT_RESPONSE.data.projectName);
    assert.match(requestedUrl, /get_project_info\?project_id=271$/);
    assert.equal(requestedOptions.headers.Accept, "application/json, text/plain, */*");
  });

  it("rejects a non-success envelope and missing data", async () => {
    await assert.rejects(
      () => fetchFenwandaoProjectInfo({
        projectId: PROJECT_ID,
        fetch: async () => ({
          ok: true,
          status: 200,
          json: async () => ({ code: 500, msg: "失败" })
        })
      }),
      /Fenwandao API error/
    );

    const draft = parseFenwandaoProject(undefined);
    assert.equal(draft.name, "");
    assert.equal(draft.date, "");
    assert.equal(draft.venueName, "");
  });

  it("routes a project-bearing share URL to the API adapter", async () => {
    let requestedUrl;
    const fetch = async (url) => {
      requestedUrl = url;
      return { ok: true, status: 200, json: async () => PROJECT_RESPONSE };
    };

    const draft = await parseShowLink(SHARE_URL, { fetch });

    assert.equal(draft.source, "fenwandao");
    assert.equal(draft.date, "2023-08-19");
    assert.equal(draft.city, "深圳");
    assert.match(requestedUrl, /get_project_info\?project_id=271$/);
  });

  it("falls back to the canonical page when project info is unavailable", async () => {
    let requests = 0;
    const html = `<script type="application/ld+json">${JSON.stringify({
      "@type": "MusicEvent",
      name: "纷玩岛页面回退",
      startDate: "2026-09-16T19:00:00+08:00",
      location: { "@type": "Place", name: "Fallback Hall" }
    })}</script>`;

    const draft = await parseShowLink(SHARE_URL, {
      fetch: async () => {
        requests += 1;
        if (requests === 1) return { ok: false, status: 503 };
        return { ok: true, status: 200, text: async () => html };
      }
    });

    assert.equal(requests, 2);
    assert.equal(draft.name, "纷玩岛页面回退");
    assert.equal(draft.startDateTime, "2026-09-16T19:00:00+08:00");
  });
});
