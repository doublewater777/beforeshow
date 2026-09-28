import assert from "node:assert/strict";
import test from "node:test";
import { onRequestGet } from "../functions/join/[token].js";

function invite(overrides = {}) {
  const payload = {
    v: 1,
    u: "https://www.icloud.com/share/abc123",
    n: "草东没有派对",
    t: 1792324800,
    z: "Asia/Shanghai",
    l: "MAO Livehouse · 上海",
    o: "Alex",
    ...overrides,
  };
  const token = Buffer.from(JSON.stringify(payload)).toString("base64url");
  return onRequestGet({
    request: new Request(`https://beforeshow.doublewaterapps.com/join/${token}`, {
      headers: { "Accept-Language": "zh-CN" },
    }),
    params: { token },
  });
}

test("invitation preview contains the show and an explicit route back to the app", async () => {
  const response = invite();
  const html = await response.text();
  assert.equal(response.status, 200);
  assert.match(html, /<meta property="og:title" content="一起去 草东没有派对">/);
  assert.match(html, /10月18日 20:00/);
  assert.match(html, /MAO Livehouse · 上海/);
  assert.match(html, /Alex 邀请你一起去/);
  assert.match(html, /href="beforeshow:\/\/join\/[A-Za-z0-9_-]+"/);
  assert.match(html, /href="https:\/\/apps.apple.com\/app\/id6780078298"/);
  assert.doesNotMatch(html, /icloud\.com\/share/);
});

test("invitation text is escaped in social metadata and the page", async () => {
  const response = invite({ n: '<script>alert("x")</script>', o: 'Alex" <img src=x>' });
  const html = await response.text();
  assert.equal(response.status, 200);
  assert.doesNotMatch(html, /<script>/);
  assert.doesNotMatch(html, /<img src=x>/);
  assert.match(html, /&lt;script&gt;/);
  assert.match(html, /Alex&quot; &lt;img src=x&gt;/);
});

test("invalid CloudKit destinations are refused", () => {
  assert.equal(invite({ u: "https://example.com/share/abc123" }).status, 404);
});
