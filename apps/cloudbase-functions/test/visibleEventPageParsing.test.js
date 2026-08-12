import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { parseVisibleEventPage } from "../src/functions/parseShowLink/ticketPageParser.js";

describe("visible ticket page fallback", () => {
  it("parses a Maoyan-style server-rendered detail page", () => {
    const html = `<!doctype html>
      <html><head><title>时代少年团「叁重楼」演唱会—「楼间楼」重庆站 - 猫眼</title></head>
      <body>
        <h1>时代少年团「叁重楼」演唱会—「楼间楼」重庆站</h1>
        <div>重庆龙兴足球场(怡园路与两江大道交叉口西南角)</div>
        <div>2026.5.3 19:00 周日</div>
      </body></html>`;

    const draft = parseVisibleEventPage(html, { source: "maoyan" });
    assert.equal(draft.name, "时代少年团「叁重楼」演唱会—「楼间楼」重庆站");
    assert.equal(draft.city, "重庆");
    assert.equal(draft.date, "2026-05-03");
    assert.equal(draft.startTime, "19:00");
    assert.equal(draft.venueName, "重庆龙兴足球场");
    assert.match(draft.venueAddr, /怡园路/);
    assert.equal(draft.source, "maoyan");
  });

  it("parses a Fenwandao-style mobile ticket page", () => {
    const html = `<!doctype html>
      <html><head><title>【深圳】告五人第一次新世界巡回演唱会【宇宙的有趣 AROUND THE NEW WORLD】深圳站</title></head>
      <body>
        <h1>【深圳】告五人第一次新世界巡回演唱会【宇宙的有趣 AROUND THE NEW WORLD】深圳站</h1>
        <div>¥380.00 - 980.00</div>
        <div>2023.08.19-2023.08.20</div>
        <div>深圳 | 华润深圳湾体育中心“春茧”体育馆</div>
        <div>深圳市·深圳湾体育中心-体育馆</div>
        <div>主要演员</div><div>告五人</div>
      </body></html>`;

    const draft = parseVisibleEventPage(html, { source: "fenwandao" });
    assert.equal(draft.name, "【深圳】告五人第一次新世界巡回演唱会【宇宙的有趣 AROUND THE NEW WORLD】深圳站");
    assert.equal(draft.city, "深圳");
    assert.equal(draft.date, "2023-08-19");
    assert.equal(draft.endDate, "2023-08-20");
    assert.equal(draft.venueName, "华润深圳湾体育中心“春茧”体育馆");
    assert.equal(draft.artist, "告五人");
    assert.equal(draft.priceRange, "380.00 - 980.00");
    assert.equal(draft.source, "fenwandao");
  });
});
