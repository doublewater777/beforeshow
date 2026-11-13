import assert from "node:assert/strict";
import test from "node:test";
import { onRequestGet } from "../functions/s/[token].js";

function tokenFor(overrides = {}) {
  const payload = {
    v: 1,
    n: "草东没有派对",
    d: 1792324800,
    t: 1792324800,
    z: "Asia/Shanghai",
    s: 28800,
    c: "上海",
    l: "MAO Livehouse",
    p: "https://img.example.com/cover.jpg",
    ...overrides,
  };
  return Buffer.from(JSON.stringify(payload)).toString("base64url");
}

function page(token, headers = {}) {
  return onRequestGet({
    request: new Request(`https://beforeshow.doublewaterapps.com/s/${token}`, {
      headers: { "Accept-Language": "zh-CN", ...headers },
    }),
    params: { token },
  });
}

test("the page shows the shared show and a way into the app", async () => {
  const token = tokenFor();
  const response = page(token);
  const html = await response.text();
  assert.equal(response.status, 200);
  assert.match(html, /<meta property="og:title" content="草东没有派对">/);
  assert.match(html, /10月18日/);
  assert.match(html, /20:00/);
  assert.match(html, /MAO Livehouse · 上海/);
  assert.match(html, /src="https:\/\/img.example.com\/cover.jpg"/);
  assert.ok(html.includes(`href="beforeshow://s/${token}"`));
  assert.match(html, /href="https:\/\/apps.apple.com\/app\/id6780078298"/);
  assert.match(html, /开场前/);
});

test("the store name follows the reader's language", async () => {
  assert.match(await page(tokenFor(), { "Accept-Language": "zh-TW" }).text(), /開場前/);
  assert.match(await page(tokenFor(), { "Accept-Language": "en-US" }).text(), /Add to BeforeShow/);
});

test("a festival shows its last day", async () => {
  const html = await page(tokenFor({ e: 1792324800 + 86400 })).text();
  assert.match(html, /10月19日/);
});

test("show text is escaped", async () => {
  const html = await page(tokenFor({ n: '<script>alert("x")</script>', l: '" onmouseover="x' })).text();
  assert.doesNotMatch(html, /<script>alert/);
  assert.match(html, /&lt;script&gt;/);
  assert.doesNotMatch(html, /" onmouseover="x/);
});

test("a cover that is not a web address is left out", async () => {
  const html = await page(tokenFor({ p: "javascript:alert(1)" })).text();
  assert.doesNotMatch(html, /javascript:/);
  assert.doesNotMatch(html, /class="poster"/);
});

test("broken and unknown tokens are refused", () => {
  for (const token of ["", "not*base64", Buffer.from("not json").toString("base64url"), tokenFor({ v: 2 }), tokenFor({ n: " " })]) {
    assert.equal(page(token).status, 404, token);
  }
});

test("inside WeChat the button points to opening in the browser", async () => {
  const html = await page(tokenFor(), { "User-Agent": "Mozilla/5.0 MicroMessenger/8.0" }).text();
  assert.match(html, /id="open" class="btn" href="#wechat-guide"/);
  assert.match(html, /选择在浏览器中打开/);
});
