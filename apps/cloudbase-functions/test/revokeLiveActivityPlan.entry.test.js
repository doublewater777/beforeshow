import test from "node:test";
import assert from "node:assert/strict";
import { main } from "../src/functions/revokeLiveActivityPlan/entry.js";
import { hashSecret } from "../src/functions/syncLiveActivityPlan/entry.js";

const VALID_APP_SIG = "beforeshow-app-signature-v1";
const VALID_SECRET = "super-secret-random-32char-string";

test("revokeLiveActivityPlan marks existing plan revoked", async () => {
  let updatedStatus = null;
  const existing = {
    _id: "dev-1:show-456",
    showID: "show-456",
    planSecretHash: hashSecret(VALID_SECRET),
    status: "active"
  };

  const res = await main(
    {
      appInstanceId: "dev-1",
      appSignature: VALID_APP_SIG,
      showID: "show-456",
      planSecret: VALID_SECRET
    },
    {},
    {
      findExisting: async () => existing,
      updateStatus: async (docId, status) => {
        updatedStatus = status;
      }
    }
  );

  assert.equal(res.ok, true);
  assert.equal(res.revoked, true);
  assert.equal(updatedStatus, "revoked");
});

test("revokeLiveActivityPlan rejects unauthorized secret tampering", async () => {
  const existing = {
    _id: "dev-1:show-456",
    showID: "show-456",
    planSecretHash: hashSecret(VALID_SECRET),
    status: "active"
  };

  const res = await main(
    {
      appInstanceId: "dev-1",
      appSignature: VALID_APP_SIG,
      showID: "show-456",
      planSecret: "tampered-wrong-secret"
    },
    {},
    {
      findExisting: async () => existing
    }
  );

  assert.equal(res.ok, false);
  assert.equal(res.error.code, "PLAN_AUTH_FORBIDDEN");
});

test("revokeLiveActivityPlan succeeds idempotently when plan not found", async () => {
  const res = await main(
    {
      appInstanceId: "dev-1",
      appSignature: VALID_APP_SIG,
      showID: "show-none",
      planSecret: VALID_SECRET
    },
    {},
    {
      findExisting: async () => null
    }
  );

  assert.equal(res.ok, true);
  assert.equal(res.revoked, true);
  assert.equal(res.notFound, true);
});
