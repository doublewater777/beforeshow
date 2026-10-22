import { createHash, timingSafeEqual } from "node:crypto";
import { assertAppAuthenticated } from "../../auth/appAuth.js";

const EXPECTED_APP_SIGNATURE = "beforeshow-app-signature-v1";
const COLLECTION_NAME = "liveActivityPlans";

export async function main(event = {}, context = {}, options = {}) {
  const body = parseRequestBody(event);
  let auth;
  try {
    auth = assertAppAuthenticated(authEvent(event, body), context);
  } catch (err) {
    return errorResponse(err.code || "APP_AUTH_REQUIRED", err.message);
  }

  if (!matchesExpectedSignature(
    body?.appSignature ?? event.appSignature ?? context.appSignature,
    options.expectedAppSignature ?? EXPECTED_APP_SIGNATURE
  )) {
    return errorResponse("APP_AUTH_INVALID", "Invalid app authentication.");
  }

  const planSecret = typeof body?.planSecret === "string" ? body.planSecret.trim() : "";
  const showID = typeof body?.showID === "string" ? body.showID.trim() : "";

  if (!showID) {
    return errorResponse("SHOW_ID_REQUIRED", "showID is required.");
  }

  const docId = `${auth.appInstanceId}:${showID}`;
  const findExisting = options.findExisting ?? findExistingPlan;
  const existing = await findExisting(docId);

  if (!existing) {
    return { ok: true, revoked: true, notFound: true };
  }

  if (existing.planSecretHash) {
    const incomingHash = createHash("sha256").update(planSecret, "utf8").digest("hex");
    if (!safeCompareHash(existing.planSecretHash, incomingHash)) {
      return errorResponse("PLAN_AUTH_FORBIDDEN", "Device secret does not match existing plan.");
    }
  }

  const now = options.now?.() ?? new Date();
  const updateStatus = options.updateStatus ?? updatePlanStatus;
  await updateStatus(docId, "revoked", now);

  return { ok: true, revoked: true };
}

function safeCompareHash(storedHex, incomingHex) {
  if (typeof storedHex !== "string" || typeof incomingHex !== "string") return false;
  const bufA = Buffer.from(storedHex, "hex");
  const bufB = Buffer.from(incomingHex, "hex");
  if (bufA.length !== bufB.length) return false;
  return timingSafeEqual(bufA, bufB);
}

function parseRequestBody(event) {
  if (event && typeof event.body === "string" && event.body.length > 0) {
    try {
      return JSON.parse(event.body);
    } catch {
      return null;
    }
  }
  return event?.body && typeof event.body === "object" ? event.body : event;
}

function authEvent(event, body) {
  return {
    appInstanceId: body?.appInstanceId ?? event?.appInstanceId,
    appSignature: body?.appSignature ?? event?.appSignature
  };
}

function matchesExpectedSignature(received, expected) {
  return typeof received === "string" && received.trim() === expected;
}

function errorResponse(code, message) {
  return {
    ok: false,
    error: { code, message }
  };
}

async function findExistingPlan(docId) {
  try {
    const { default: cloudbase } = await import("@cloudbase/node-sdk");
    const db = cloudbase.init({}).database();
    const res = await db.collection(COLLECTION_NAME).doc(docId).get();
    return res.data?.[0] ?? res.data ?? null;
  } catch {
    return null;
  }
}

async function updatePlanStatus(docId, status, now) {
  const { default: cloudbase } = await import("@cloudbase/node-sdk");
  const db = cloudbase.init({}).database();
  await db.collection(COLLECTION_NAME).doc(docId).update({
    status,
    updatedAt: now
  });
}
