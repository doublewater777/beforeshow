import { createHash, randomUUID, timingSafeEqual } from "node:crypto";
import { assertAppAuthenticated } from "../../auth/appAuth.js";

const MAX_MESSAGE_LENGTH = 2000;
const MAX_DIAGNOSTIC_LENGTH = 160;
const EXPECTED_APP_SIGNATURE = "beforeshow-app-signature-v1";
const RATE_LIMIT_COLLECTION = "feedbackRateLimits";
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;
const MAX_PER_INSTANCE_PER_WINDOW = 5;
const MAX_GLOBAL_PER_WINDOW = 120;

export async function main(event = {}, context = {}, options = {}) {
  const body = parseRequestBody(event);
  const auth = assertAppAuthenticated(authEvent(event, body), context);

  if (!matchesExpectedSignature(
    body?.appSignature ?? event.appSignature ?? context.appSignature,
    options.expectedAppSignature ?? EXPECTED_APP_SIGNATURE
  )) {
    return errorResponse("APP_AUTH_INVALID", "Invalid app authentication.");
  }

  const rawMessage = typeof body?.message === "string" ? body.message : "";
  const message = rawMessage.trim();

  if (message.length === 0) {
    return errorResponse("MESSAGE_REQUIRED", "Feedback message is required.");
  }

  if (Array.from(rawMessage).length > MAX_MESSAGE_LENGTH) {
    return errorResponse("MESSAGE_TOO_LONG", "Feedback message is too long.");
  }

  const now = options.now?.() ?? new Date();
  const consumeRateLimit = options.consumeRateLimit ?? consumeFeedbackRateLimit;

  let allowed;
  try {
    allowed = await consumeRateLimit({
      appInstanceId: auth.appInstanceId,
      now
    });
  } catch {
    // Fail closed: if the limiter is unavailable, do not expose an unbounded write path.
    return errorResponse("RATE_LIMIT_UNAVAILABLE", "Feedback rate limit is unavailable.");
  }

  if (!allowed) {
    return errorResponse("RATE_LIMITED", "Too many feedback submissions.");
  }

  const feedbackId = (options.randomUUID ?? randomUUID)();
  const record = {
    feedbackId,
    message,
    appVersion: normalizeDiagnostic(body?.appVersion),
    osVersion: normalizeDiagnostic(body?.osVersion),
    submittedAt: now.toISOString()
  };

  try {
    const writeFeedback = options.writeFeedback ?? writeFeedbackToCloudDatabase;
    await writeFeedback(record);

    return {
      ok: true,
      feedbackId
    };
  } catch {
    return errorResponse("STORE_FAILED", "Feedback could not be stored.");
  }
}

function matchesExpectedSignature(received, expected) {
  if (typeof received !== "string" || typeof expected !== "string") {
    return false;
  }

  const receivedBuffer = Buffer.from(received);
  const expectedBuffer = Buffer.from(expected);
  return receivedBuffer.length === expectedBuffer.length &&
    timingSafeEqual(receivedBuffer, expectedBuffer);
}

async function consumeFeedbackRateLimit({ appInstanceId, now }) {
  const { default: cloudbase } = await import("@cloudbase/node-sdk");
  const app = cloudbase.init({});
  const db = app.database();
  await ensureCollection(db, RATE_LIMIT_COLLECTION);

  const windowStart = Math.floor(now.getTime() / RATE_LIMIT_WINDOW_MS) * RATE_LIMIT_WINDOW_MS;
  const expiresAt = new Date(windowStart + (2 * RATE_LIMIT_WINDOW_MS)).toISOString();
  const instanceHash = createHash("sha256")
    .update(`${windowStart}:${String(appInstanceId)}`)
    .digest("hex");
  const globalDocumentId = `global-${windowStart}`;
  const instanceDocumentId = `instance-${windowStart}-${instanceHash}`;

  const result = await db.runTransaction(async transaction => {
    const globalRef = transaction.collection(RATE_LIMIT_COLLECTION).doc(globalDocumentId);
    const instanceRef = transaction.collection(RATE_LIMIT_COLLECTION).doc(instanceDocumentId);

    const globalResult = await globalRef.get();
    const instanceResult = await instanceRef.get();
    const globalCount = documentCount(globalResult);
    const instanceCount = documentCount(instanceResult);

    if (globalCount >= MAX_GLOBAL_PER_WINDOW ||
        instanceCount >= MAX_PER_INSTANCE_PER_WINDOW) {
      return { allowed: false };
    }

    await globalRef.set({
      scope: "global",
      count: globalCount + 1,
      windowStart,
      expiresAt
    });
    await instanceRef.set({
      scope: "instance",
      count: instanceCount + 1,
      windowStart,
      expiresAt
    });

    return { allowed: true };
  });

  return result?.result?.allowed === true;
}

function documentCount(result) {
  const data = result?.data;
  if (Array.isArray(data)) {
    return Number(data[0]?.count ?? 0);
  }
  return Number(data?.count ?? 0);
}

async function writeFeedbackToCloudDatabase(record) {
  const { default: cloudbase } = await import("@cloudbase/node-sdk");
  const app = cloudbase.init({});
  const db = app.database();
  const collectionName = "userFeedback";
  await ensureCollection(db, collectionName);
  await db.collection(collectionName).add(record);
}

async function ensureCollection(db, collectionName) {
  try {
    await db.collection(collectionName).limit(1).get();
  } catch (error) {
    if (error?.code !== "DATABASE_COLLECTION_NOT_EXIST") {
      throw error;
    }

    try {
      await db.createCollection(collectionName);
    } catch (createError) {
      if (createError?.code !== "DATABASE_COLLECTION_ALREADY_EXIST") {
        throw createError;
      }
    }
  }
}

function normalizeDiagnostic(value) {
  if (typeof value !== "string") {
    return "";
  }
  return value.trim().slice(0, MAX_DIAGNOSTIC_LENGTH);
}

function errorResponse(code, message) {
  return {
    ok: false,
    error: {
      code,
      message
    }
  };
}

function parseRequestBody(event) {
  if (typeof event.body === "string") {
    try {
      return JSON.parse(event.body);
    } catch {
      return event.body;
    }
  }

  return event.body ?? event;
}

function authEvent(event, body) {
  if (body !== null && typeof body === "object" && !Array.isArray(body)) {
    return { ...event, ...body };
  }

  return event;
}
