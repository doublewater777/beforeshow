import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import http2 from "node:http2";
import { once } from "node:events";
import {
  createApnsToken,
  buildActivityKitPayload,
  sendActivityKitPush,
  normalizePrivateKey
} from "../src/apns/apnsClient.js";

test("createApnsToken produces valid ES256 JWT structure", () => {
  const { privateKey } = crypto.generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const pem = privateKey.export({ type: "pkcs8", format: "pem" });

  const token = createApnsToken({
    keyId: "KEY123",
    teamId: "TEAM456",
    privateKeyPem: pem,
    nowSeconds: 1700000000
  });

  const parts = token.split(".");
  assert.equal(parts.length, 3);

  const header = JSON.parse(Buffer.from(parts[0], "base64url").toString());
  assert.deepEqual(header, { alg: "ES256", kid: "KEY123" });

  const claims = JSON.parse(Buffer.from(parts[1], "base64url").toString());
  assert.deepEqual(claims, { iss: "TEAM456", iat: 1700000000 });
});

test("buildActivityKitPayload formats update, alert, and end events properly", () => {
  const state = { showName: "Strawberry Music Festival" };
  const scheduledDate = new Date("2026-10-21T18:00:00Z");
  const staleDate = new Date("2026-10-21T18:30:00Z");

  // 1. Silent update
  const silent = buildActivityKitPayload({
    contentState: state,
    scheduledAt: scheduledDate,
    staleAt: staleDate
  });
  assert.equal(silent.aps.event, "update");
  assert.equal(silent.aps.timestamp, Math.floor(scheduledDate.getTime() / 1000));
  assert.equal(silent.aps["stale-date"], Math.floor(staleDate.getTime() / 1000));
  assert.equal(silent.aps.alert, undefined);

  // 2. Alert update
  const alertPayload = buildActivityKitPayload({
    contentState: state,
    scheduledAt: scheduledDate,
    alert: { title: "快开始了", body: "椅子乐团 · 18:00 风舞台" }
  });
  assert.deepEqual(alertPayload.aps.alert, {
    title: "快开始了",
    body: "椅子乐团 · 18:00 风舞台",
    sound: "default"
  });

  // 3. End event
  const dismissalDate = new Date("2026-10-21T23:45:00Z");
  const endPayload = buildActivityKitPayload({
    contentState: state,
    scheduledAt: scheduledDate,
    isEnd: true,
    dismissalAt: dismissalDate
  });
  assert.equal(endPayload.aps.event, "end");
  assert.equal(endPayload.aps["dismissal-date"], Math.floor(dismissalDate.getTime() / 1000));
});

test("sendActivityKitPush routes correctly through injected transport", async () => {
  let captured = null;
  const transport = async (args) => {
    captured = args;
    return { ok: true, statusCode: 200 };
  };

  const payload = { aps: { event: "update" } };
  const result = await sendActivityKitPush({
    pushToken: "fake-token-hex",
    payload,
    isProduction: true,
    bundleId: "com.doublewaterapps.beforeshow",
    transport
  });

  assert.equal(result.ok, true);
  assert.equal(captured.pushToken, "fake-token-hex");
  assert.equal(captured.isProduction, true);
  assert.equal(captured.bundleId, "com.doublewaterapps.beforeshow");
});

test("APNs requests deliver silent endings and reminders at high priority, ordinary updates at low priority", async (t) => {
  const requests = [];
  const server = http2.createServer();
  server.on("stream", (stream, headers) => {
    let body = "";
    stream.setEncoding("utf8");
    stream.on("data", chunk => { body += chunk; });
    stream.on("end", () => {
      requests.push({ headers, payload: JSON.parse(body) });
      stream.respond({ ":status": 200 });
      stream.end();
    });
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(() => server.close());

  const connect = http2.connect.bind(http2);
  t.mock.method(http2, "connect", () => connect(`http://127.0.0.1:${server.address().port}`));
  const { privateKey } = crypto.generateKeyPairSync("ec", { namedCurve: "prime256v1" });

  for (const { event, alert, priority } of [
    { event: "update", priority: "5" },
    { event: "update", alert: { title: "Reminder", body: "Next performance" }, priority: "10" },
    { event: "end", priority: "10" }
  ]) {
    await t.test(`${event} ${alert ? "with alert" : "silently"} uses priority ${priority}`, async () => {
      const payload = { aps: { event, "content-state": { isEnded: event === "end" } } };
      if (alert) payload.aps.alert = alert;
      const result = await sendActivityKitPush({
        pushToken: "test-activity-token",
        payload,
        bundleId: "com.example.liveactivity",
        keyId: "TESTKEY",
        teamId: "TESTTEAM",
        privateKeyPem: privateKey.export({ type: "pkcs8", format: "pem" })
      });

      assert.equal(result.ok, true);
      const request = requests.at(-1);
      assert.equal(request.headers["apns-priority"], priority);
      assert.equal(request.headers["apns-push-type"], "liveactivity");
      assert.equal(request.headers["apns-topic"], "com.example.liveactivity.push-type.liveactivity");
      assert.deepEqual(request.payload, payload);
    });
  }
});
