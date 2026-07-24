import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { parseShowLink } from "../src/functions/parseShowLink/index.js";

describe("parseShowLink integration", () => {
  it("parses Damai livehouse mobile link", { timeout: 20000 }, async () => {
    const draft = await parseShowLink("https://m.damai.cn/shows/item.html?itemId=1054603723374");

    assert.equal(draft.source, "damai");
    assert.equal(draft.city, "杭州");
    assert.ok(draft.name.includes("Chris James"));
    assert.ok(draft.venueName.length > 0);
    assert.ok(draft.date.length > 0);
  });

  it("parses Damai music festival mobile link", { timeout: 20000 }, async () => {
    const draft = await parseShowLink("https://m.damai.cn/shows/item.html?itemId=1051998434427");

    assert.equal(draft.source, "damai");
    assert.equal(draft.city, "湖州");
    assert.ok(draft.name.includes("绿洲音乐节"));
    assert.ok(draft.artist.length > 0);
  });

  it("parses Damai concert PC link", { timeout: 20000 }, async () => {
    const draft = await parseShowLink("https://detail.damai.cn/item.htm?id=1055935539093");

    assert.equal(draft.source, "damai");
    assert.equal(draft.city, "北京");
    assert.ok(draft.name.includes("洛天依"));
    assert.ok(draft.startTime.length > 0);
  });

  it("parses ShowStart livehouse link", { timeout: 60000 }, async () => {
    const draft = await parseShowLink("https://wap.showstart.com/pages/activity/detail/detail?activityId=298012");

    assert.equal(draft.source, "showstart");
    assert.equal(draft.city, "杭州");
    assert.ok(draft.name.includes("康士坦的变化球"));
    assert.ok(draft.venueName.length > 0);
  });

  it("parses ShowStart music festival link", { timeout: 60000 }, async () => {
    const draft = await parseShowLink("https://wap.showstart.com/pages/activity/detail/detail?activityId=295771");

    assert.equal(draft.source, "showstart");
    assert.equal(draft.city, "杭州");
    assert.ok(draft.name.includes("速煞朋克音乐节"));
    assert.ok(draft.artist.length > 0);
  });
});
