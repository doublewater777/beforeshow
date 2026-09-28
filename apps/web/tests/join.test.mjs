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

test("supports China mainland icloud.com.cn CloudKit destinations", async () => {
  const response = invite({ u: "https://www.icloud.com.cn/share/07eSuMIaRuOnwy6KE2DNkgH_w" });
  assert.equal(response.status, 200);
});

test("wechat user agent receives in-browser guide and target-based overlay", async () => {
  const payload = {
    v: 1,
    u: "https://www.icloud.com/share/abc123",
    n: "草东没有派对",
    t: 1792324800,
    z: "Asia/Shanghai",
    l: "MAO Livehouse · 上海",
    o: "Alex",
  };
  const token = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const response = onRequestGet({
    request: new Request(`https://beforeshow.doublewaterapps.com/join/${token}`, {
      headers: {
        "Accept-Language": "zh-CN",
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/8.0.38(0x1800262c) NetType/WIFI",
      },
    }),
    params: { token },
  });
  const html = await response.text();
  assert.equal(response.status, 200);
  assert.match(html, /<body class="is-wechat">/);
  assert.match(html, /在浏览器中打开/);
  assert.match(html, /href="#wechat-guide"/);
  assert.match(html, /id="wechat-guide"/);
  assert.match(html, /<link rel="apple-touch-icon" href="\/app-icon\.png">/);
});

test("renders remote cover and large card social metadata when present", async () => {
  const coverURL = "https://images.example.com/poster.jpg";
  const response = invite({ c: coverURL });
  const html = await response.text();
  assert.equal(response.status, 200);
  assert.match(html, /<meta property="og:image" content="https:\/\/images\.example\.com\/poster\.jpg">/);
  assert.match(html, /<meta name="twitter:card" content="summary_large_image">/);
  assert.match(html, /<meta name="twitter:image" content="https:\/\/images\.example\.com\/poster\.jpg">/);
  assert.match(html, /class="ticket-cover-wrap"/);
  assert.match(html, /aspect-ratio:\s*3\s*\/\s*4/);
  assert.match(html, /<img class="ticket-cover" src="https:\/\/images\.example\.com\/poster\.jpg"/);
});

test("falls back to Asia/Shanghai time for Chinese locale when timezone is missing", async () => {
  const response = invite({ t: 1790915400, z: undefined, s: undefined });
  const html = await response.text();
  assert.equal(response.status, 200);
  assert.match(html, /10月2日 12:30/);
});

test("falls back cleanly when cover is missing", async () => {
  const response = invite();
  const html = await response.text();
  assert.equal(response.status, 200);
  assert.match(html, /<meta property="og:image" content="https:\/\/beforeshow\.doublewaterapps\.com\/app-icon\.png">/);
  assert.match(html, /<meta name="twitter:card" content="summary">/);
  assert.doesNotMatch(html, /class="ticket-cover-wrap"/);
  assert.doesNotMatch(html, /class="ticket-cover"/);
});

test("rejects invalid cover schemes or malformed cover URLs", () => {
  assert.equal(invite({ c: "javascript:alert(1)" }).status, 404);
  assert.equal(invite({ c: "file:///private/var/mobile/cover.jpg" }).status, 404);
  assert.equal(invite({ c: "not-a-url" }).status, 404);
  assert.equal(invite({ c: "https://" + "a".repeat(1025) }).status, 404);
});
