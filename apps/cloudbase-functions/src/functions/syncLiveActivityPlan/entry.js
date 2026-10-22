import { createHash, timingSafeEqual } from "node:crypto";
import { assertAppAuthenticated } from "../../auth/appAuth.js";

import { deliveredReminderKeys, reminderEvents, reminderAlert } from "../../apns/liveActivityReminder.js";

import { liveActivityDatabase, readPlan, registerPlan } from "../../apns/liveActivityPlanStore.js";

const EXPECTED_APP_SIGNATURE = "beforeshow-app-signature-v1";
const COLLECTION_NAME = "liveActivityPlans";
const EXPIRY_BUFFER_MS = 24 * 60 * 60 * 1000; // 24 hours after show deadline

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
  if (planSecret.length < 16) {
    return errorResponse("PLAN_SECRET_REQUIRED", "planSecret must be at least 16 characters.");
  }

  const plan = body?.plan;
  if (!plan || typeof plan !== "object") {
    return errorResponse("PLAN_REQUIRED", "LiveActivityBoundedTransitionPlan is required.");
  }

  const showID = typeof plan.showID === "string" ? plan.showID.trim() : "";
  const activityPushToken = typeof plan.activityPushToken === "string" ? plan.activityPushToken.trim() : "";
  const version = typeof plan.version === "number" ? plan.version : 0;
  const deadlineRaw = plan.deadline;
  const stepsRaw = Array.isArray(plan.steps) ? plan.steps : [];

  if (!showID || !activityPushToken || version <= 0 || !deadlineRaw) {
    return errorResponse("PLAN_INVALID", "Missing required plan fields (showID, activityPushToken, version, deadline).");
  }

  const deadline = parsePlanDate(deadlineRaw);
  if (isNaN(deadline.getTime())) {
    return errorResponse("PLAN_INVALID", "Invalid plan deadline timestamp.");
  }

  const now = options.now?.() ?? new Date();
  if (deadline < now) {
    return errorResponse("PLAN_EXPIRED", "Show deadline has already passed.");
  }

  const incomingSecretHash = hashSecret(planSecret);
  const docId = `${auth.appInstanceId}:${showID}`;

  const findExisting = options.findExisting ?? (id => options.database ? readPlan(options.database, id) : findExistingPlan(id));
  const existing = await findExisting(docId);

  if (existing) {
    if (existing.planSecretHash && !safeCompareHash(existing.planSecretHash, incomingSecretHash)) {
      return errorResponse("PLAN_AUTH_FORBIDDEN", "Device secret does not match existing plan.");
    }

    if (version < existing.version) {
      return errorResponse("STALE_PLAN_VERSION", "Incoming plan version is older than existing registered plan.");
    }

    if (version === existing.version) {
      return {
        ok: true,
        acceptedVersion: existing.version,
        planID: existing.planID,
        idempotent: true
      };
    }
  }

  const normalizedSteps = stepsRaw.map((step, idx) => {
    const scheduledAt = parsePlanDate(step.scheduledAt);
    const staleAt = step.staleAt != null ? parsePlanDate(step.staleAt) : null;
    const state = step.state ?? {};
    const isReminder = Boolean(state.isReminderActive);
    const alert = isReminder ? reminderAlert(state, reminderEvents(state, step.reminderEvents), plan.language) : null;
    const alertTitle = alert?.title ?? null;
    const alertBody = alert?.body ?? null;

    return {
      stepIndex: idx,
      scheduledAt,
      staleAt,
      state,
      reminderEvents: step.reminderEvents ?? null,
      isReminder,
      alertTitle,
      alertBody,
      isConsumed: false,
      consumedAt: null
    };
  });

  const expireAt = new Date(deadline.getTime() + EXPIRY_BUFFER_MS);
  const record = {
    _id: docId,
    appInstanceId: auth.appInstanceId,
    showID,
    planID: plan.planID ?? docId,
    planSecretHash: incomingSecretHash,
    activityPushToken,
    isProduction: Boolean(plan.isProduction),
    version,
    deadline,
    expireAt,
    status: "active",
    updatedAt: now,
    language: plan.language ?? "zh-Hans",
    deliveredReminderKeys: deliveredReminderKeys(existing),
    steps: normalizedSteps
  };

  let registration;
  try {
    registration = options.database
      ? await registerPlan(options.database, record)
      : options.savePlan ? await options.savePlan(record)
      : await registerPlan(await liveActivityDatabase(), record);
  } catch (err) {
    return errorResponse(err.code || "PLAN_SAVE_FAILED", err.message);
  }

  return {
    ok: true,
    acceptedVersion: registration?.acceptedVersion ?? version,
    planID: registration?.planID ?? record.planID,
    ...(registration?.idempotent ? { idempotent: true } : {}),
    stepsCount: normalizedSteps.length
  };
}

export function hashSecret(secret) {
  return createHash("sha256").update(secret, "utf8").digest("hex");
}

function parsePlanDate(value) {
  // Swift JSONEncoder's default Date format is seconds since 2001-01-01.
  // Content-state dates stay untouched so ActivityKit can decode them.
  return new Date(typeof value === "number" ? (value + 978307200) * 1000 : value);
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
