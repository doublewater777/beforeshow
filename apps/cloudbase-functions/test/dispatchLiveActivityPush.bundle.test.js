import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

test("dispatcher polls a due final step after the show deadline but before plan expiry", async () => {
  const now = new Date("2026-10-21T18:01:00Z");
  const { outputFiles } = await build({
    entryPoints: [fileURLToPath(new URL("../src/functions/dispatchLiveActivityPush/entry.js", import.meta.url))],
    bundle: true,
    platform: "node",
    format: "esm",
    write: false,
    plugins: [{
      name: "database-fixture",
      setup(builder) {
        builder.onResolve({ filter: /^@cloudbase\/node-sdk$/ }, () => ({ path: "sdk", namespace: "fixture" }));
        builder.onLoad({ filter: /.*/, namespace: "fixture" }, () => ({
          contents: `
            const deadline = new Date("2026-10-21T18:00:00Z");
            const plan = {
              _id: "device:show", status: "active", deadline,
              expireAt: new Date("2026-10-22T18:00:00Z"),
              activityPushToken: "test-token",
              steps: [{ scheduledAt: deadline, state: { isEnded: true }, isConsumed: false }]
            };
            const records = [plan, { ...plan, _id: "expired", expireAt: deadline }];
            const db = {
              command: { gte: value => ({ minimum: value }) },
              collection() { return {
                where(filters) { return {
                  limit() { return {
                    async get() { return { data: records.filter(record =>
                      Object.entries(filters).every(([key, value]) =>
                        value?.minimum ? record[key] >= value.minimum : record[key] === value)
                    ) }; }
                  }; }
                }; }
              }; }
            };
            export default { init: () => ({ database: () => db }) };
          `
        }));
      }
    }]
  });
  const { main } = await import(`data:text/javascript;base64,${Buffer.from(outputFiles[0].text).toString("base64")}`);
  const sent = [];
  const updated = [];
  const result = await main({}, {}, {
    now: () => now,
    transport: async ({ payload }) => {
      sent.push(payload);
      return { ok: true, statusCode: 200 };
    },
    updatePlan: async (id, data) => { updated.push({ id, ...data }); }
  });
  assert.equal(result.dispatchedCount, 1);
  assert.equal(sent[0].aps.event, "end");
  assert.equal(updated[0].id, "device:show");
  assert.equal(updated[0].status, "completed");
});

test("deployed dispatcher exposes a callable CloudBase event handler", () => {
  const cwd = fileURLToPath(new URL("..", import.meta.url));
  execFileSync(process.execPath, ["scripts/prepare-dispatchLiveActivityPush.mjs"], { cwd });
  execFileSync(process.execPath, ["-e", `
    const assert = require("node:assert/strict");
    const deployed = require("./.cloudbase/functions/dispatchLiveActivityPush/index.js");
    assert.equal(typeof deployed.main, "function", "CloudBase index.main handler must exist");
    deployed.main({}, {}).then(result => {
      assert.equal(result.ok, false);
      assert.equal(result.error.code, "CONFIG_MISSING");
      assert.equal(result.skippedDueToConfig, true);
    }).catch(error => { console.error(error); process.exitCode = 1; });
  `], {
    cwd,
    timeout: 15000,
    env: { ...process.env, APNS_KEY_ID: "", APNS_TEAM_ID: "", APNS_PRIVATE_KEY: "" }
  });
});
