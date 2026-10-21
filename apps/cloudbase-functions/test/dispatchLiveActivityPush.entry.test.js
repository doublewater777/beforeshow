import test from "node:test";
import assert from "node:assert/strict";
import { main } from "../src/functions/dispatchLiveActivityPush/entry.js";

test("dispatchLiveActivityPush delivers due steps and sends alert within 15m window", async () => {
  const now = new Date("2026-10-21T18:05:00Z");
  const scheduledAt = new Date("2026-10-21T18:00:00Z"); // 5 minutes ago -> within 15m

  let pushedPayload = null;
  let updatedSteps = null;

  const plan = {
    _id: "dev-1:show-1",
    activityPushToken: "token-1",
    isProduction: false,
    status: "active",
    steps: [
      {
        stepIndex: 0,
        scheduledAt,
        state: { showName: "Strawberry Festival" },
        isReminder: true,
        alertTitle: "快开始了",
        alertBody: "椅子乐团 · 18:00 风舞台",
        isConsumed: false
      }
    ]
  };

  const res = await main(
    {},
    {},
    {
      now: () => now,
      findActivePlans: async () => [plan],
      updatePlan: async (docId, updateData) => {
        updatedSteps = updateData.steps;
      },
      transport: async (args) => {
        pushedPayload = args.payload;
        return { ok: true, statusCode: 200 };
      }
    }
  );

  assert.equal(res.ok, true);
  assert.equal(res.dispatchedCount, 1);
  assert.equal(pushedPayload.aps.event, "update");
  assert.deepEqual(pushedPayload.aps.alert, {
    title: "快开始了",
    body: "椅子乐团 · 18:00 风舞台",
    sound: "default"
  });
  assert.equal(updatedSteps[0].isConsumed, true);
});

test("dispatchLiveActivityPush suppresses alert when reminder is more than 15m late", async () => {
  const now = new Date("2026-10-21T18:20:00Z");
  const scheduledAt = new Date("2026-10-21T18:00:00Z"); // 20 minutes ago -> late!

  let pushedPayload = null;

  const plan = {
    _id: "dev-1:show-1",
    activityPushToken: "token-1",
    isProduction: false,
    status: "active",
    steps: [
      {
        stepIndex: 0,
        scheduledAt,
        state: { showName: "Strawberry Festival" },
        isReminder: true,
        alertTitle: "快开始了",
        alertBody: "椅子乐团 · 18:00 风舞台",
        isConsumed: false
      }
    ]
  };

  const res = await main(
    {},
    {},
    {
      now: () => now,
      findActivePlans: async () => [plan],
      updatePlan: async () => {},
      transport: async (args) => {
        pushedPayload = args.payload;
        return { ok: true, statusCode: 200 };
      }
    }
  );

  assert.equal(res.ok, true);
  assert.equal(res.dispatchedCount, 1);
  assert.equal(pushedPayload.aps.event, "update");
  assert.equal(pushedPayload.aps.alert, undefined); // Alert suppressed!
});

test("dispatchLiveActivityPush marks plan as token_expired on 410 Unregistered", async () => {
  const now = new Date("2026-10-21T18:00:00Z");
  let finalStatus = null;

  const plan = {
    _id: "dev-1:show-1",
    activityPushToken: "stale-token",
    isProduction: false,
    status: "active",
    steps: [
      {
        stepIndex: 0,
        scheduledAt: now,
        state: { showName: "Strawberry Festival" },
        isConsumed: false
      }
    ]
  };

  const res = await main(
    {},
    {},
    {
      now: () => now,
      findActivePlans: async () => [plan],
      updatePlan: async (docId, updateData) => {
        finalStatus = updateData.status;
      },
      transport: async () => {
        return { ok: false, statusCode: 410, reason: "Unregistered" };
      }
    }
  );

  assert.equal(res.ok, true);
  assert.equal(res.expiredTokenCount, 1);
  assert.equal(finalStatus, "token_expired");
});

test("dispatchLiveActivityPush marks plan as completed when all steps are consumed or ended", async () => {
  const now = new Date("2026-10-21T23:00:00Z");
  let finalStatus = null;

  const plan = {
    _id: "dev-1:show-end",
    activityPushToken: "token-end",
    isProduction: false,
    status: "active",
    steps: [
      {
        stepIndex: 0,
        scheduledAt: now,
        state: { showName: "Strawberry Festival", isEnded: true },
        isConsumed: false
      }
    ]
  };

  const res = await main(
    {},
    {},
    {
      now: () => now,
      findActivePlans: async () => [plan],
      updatePlan: async (docId, updateData) => {
        finalStatus = updateData.status;
      },
      transport: async () => {
        return { ok: true, statusCode: 200 };
      }
    }
  );

  assert.equal(res.ok, true);
  assert.equal(res.dispatchedCount, 1);
  assert.equal(finalStatus, "completed");
});

test("dispatchLiveActivityPush gracefully skips when APNs credentials are missing and no transport", async () => {
  const res = await main({}, {}, {});
  assert.equal(res.ok, true);
  assert.equal(res.skippedDueToConfig, true);
  assert.equal(res.dispatchedCount, 0);
});
