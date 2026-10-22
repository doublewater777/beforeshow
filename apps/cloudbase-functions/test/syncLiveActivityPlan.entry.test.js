import test from "node:test";
import assert from "node:assert/strict";
import { main, hashSecret } from "../src/functions/syncLiveActivityPlan/entry.js";

const VALID_APP_SIG = "beforeshow-app-signature-v1";
const VALID_SECRET = "super-secret-random-32char-string";

test("syncLiveActivityPlan accepts Swift JSONEncoder reference-date seconds", async () => {
  const now = new Date("2026-10-21T08:00:00Z");
  let saved;
  const result = await main({
    appInstanceId: "swift-device",
    appSignature: VALID_APP_SIG,
    planSecret: VALID_SECRET,
    plan: {
      showID: "swift-show",
      activityPushToken: "test-token",
      version: 1,
      deadline: 814266000,
      steps: [{
        scheduledAt: 814263300,
        staleAt: 814263600,
        state: { showName: "Test", startDate: 814263300 }
      }]
    }
  }, {}, {
    now: () => now,
    findExisting: async () => null,
    savePlan: async record => { saved = record; }
  });
  assert.equal(result.ok, true);
  assert.equal(saved.deadline.toISOString(), "2026-10-21T09:00:00.000Z");
  assert.equal(saved.steps[0].scheduledAt.toISOString(), "2026-10-21T08:15:00.000Z");
  assert.equal(saved.steps[0].staleAt.toISOString(), "2026-10-21T08:20:00.000Z");
  assert.equal(saved.steps[0].state.startDate, 814263300);
});

test("syncLiveActivityPlan rejects unauthenticated requests", async () => {
  const res = await main({ appInstanceId: "", appSignature: "" });
  assert.equal(res.ok, false);
});

test("syncLiveActivityPlan rejects missing or short planSecret", async () => {
  const res = await main({
    appInstanceId: "dev-1",
    appSignature: VALID_APP_SIG,
    planSecret: "short"
  });
  assert.equal(res.ok, false);
  assert.equal(res.error.code, "PLAN_SECRET_REQUIRED");
});

test("syncLiveActivityPlan saves new plan and marks steps", async () => {
  let savedRecord = null;
  const futureDeadline = new Date(Date.now() + 5 * 3600 * 1000);
  const stepDate = new Date(Date.now() + 1800 * 1000);

  const plan = {
    planID: "plan-123",
    showID: "show-456",
    appInstanceID: "dev-1",
    activityPushToken: "token-hex-abc",
    isProduction: false,
    version: 1,
    deadline: futureDeadline.toISOString(),
    steps: [
      {
        scheduledAt: stepDate.toISOString(),
        state: {
          showName: "Midi Festival",
          isReminderActive: true,
          reminderArtistName: "Wasted Laika",
          reminderStageName: "Tang Stage"
        }
      }
    ]
  };

  const res = await main(
    {
      appInstanceId: "dev-1",
      appSignature: VALID_APP_SIG,
      planSecret: VALID_SECRET,
      plan
    },
    {},
    {
      savePlan: async (record) => {
        savedRecord = record;
      }
    }
  );

  assert.equal(res.ok, true);
  assert.equal(res.acceptedVersion, 1);
  assert.equal(res.stepsCount, 1);
  assert.equal(savedRecord.showID, "show-456");
  assert.equal(savedRecord.planSecretHash, hashSecret(VALID_SECRET));
  assert.equal(savedRecord.steps[0].isReminder, true);
  assert.equal(savedRecord.steps[0].alertTitle, "Wasted Laika快开始了");
  assert.equal(savedRecord.steps[0].alertBody, "Tang Stage");
});

test("syncLiveActivityPlan rejects lower version and accepts idempotent equal version", async () => {
  const existing = {
    _id: "dev-1:show-456",
    version: 3,
    planID: "plan-v3",
    planSecretHash: hashSecret(VALID_SECRET)
  };

  // 1. Equal version -> idempotent
  const resEqual = await main(
    {
      appInstanceId: "dev-1",
      appSignature: VALID_APP_SIG,
      planSecret: VALID_SECRET,
      plan: {
        showID: "show-456",
        activityPushToken: "token",
        version: 3,
        deadline: new Date(Date.now() + 10000).toISOString(),
        steps: []
      }
    },
    {},
    {
      findExisting: async () => existing
    }
  );
  assert.equal(resEqual.ok, true);
  assert.equal(resEqual.idempotent, true);

  // 2. Lower version -> stale rejected
  const resLower = await main(
    {
      appInstanceId: "dev-1",
      appSignature: VALID_APP_SIG,
      planSecret: VALID_SECRET,
      plan: {
        showID: "show-456",
        activityPushToken: "token",
        version: 2,
        deadline: new Date(Date.now() + 10000).toISOString(),
        steps: []
      }
    },
    {},
    {
      findExisting: async () => existing
    }
  );
  assert.equal(resLower.ok, false);
  assert.equal(resLower.error.code, "STALE_PLAN_VERSION");
});

test("syncLiveActivityPlan rejects unauthorized secret tampering", async () => {
  const existing = {
    _id: "dev-1:show-456",
    version: 1,
    planSecretHash: hashSecret(VALID_SECRET)
  };

  const res = await main(
    {
      appInstanceId: "dev-1",
      appSignature: VALID_APP_SIG,
      planSecret: "wrong-secret-1234567890",
      plan: {
        showID: "show-456",
        activityPushToken: "token",
        version: 2,
        deadline: new Date(Date.now() + 10000).toISOString(),
        steps: []
      }
    },
    {},
    {
      findExisting: async () => existing
    }
  );
  assert.equal(res.ok, false);
  assert.equal(res.error.code, "PLAN_AUTH_FORBIDDEN");
});
