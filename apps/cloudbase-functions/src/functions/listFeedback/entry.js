import { timingSafeEqual } from "node:crypto";

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 100;

export async function main(event = {}, context = {}, options = {}) {
  const expectedToken = options.adminToken ?? process.env.FEEDBACK_ADMIN_TOKEN;
  if (!isNonEmptyString(expectedToken)) {
    return errorResponse("ADMIN_NOT_CONFIGURED", "Feedback admin access is not configured.");
  }

  const receivedToken = bearerToken(event.headers?.authorization ?? event.headers?.Authorization);
  if (!matchesSecret(receivedToken, expectedToken)) {
    return errorResponse("ADMIN_UNAUTHORIZED", "Unauthorized.");
  }

  const limit = parseLimit(event.query?.limit ?? event.limit);
  const readFeedback = options.readFeedback ?? readFeedbackFromCloudDatabase;

  try {
    const records = await readFeedback({ limit });
    return {
      ok: true,
      feedback: records.map(sanitizeFeedbackRecord)
    };
  } catch {
    return errorResponse("READ_FAILED", "Feedback could not be loaded.");
  }
}

async function readFeedbackFromCloudDatabase({ limit }) {
  const { default: cloudbase } = await import("@cloudbase/node-sdk");
  const app = cloudbase.init({});
  const db = app.database();

  try {
    const result = await db
      .collection("userFeedback")
      .orderBy("submittedAt", "desc")
      .limit(limit)
      .get();

    return Array.isArray(result?.data) ? result.data : [];
  } catch (error) {
    if (error?.code === "DATABASE_COLLECTION_NOT_EXIST") {
      return [];
    }
    throw error;
  }
}

function sanitizeFeedbackRecord(record = {}) {
  return {
    feedbackId: stringValue(record.feedbackId),
    message: stringValue(record.message),
    appVersion: stringValue(record.appVersion),
    osVersion: stringValue(record.osVersion),
    submittedAt: stringValue(record.submittedAt)
  };
}

function parseLimit(raw) {
  const parsed = Number.parseInt(String(raw ?? ""), 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return DEFAULT_LIMIT;
  }
  return Math.min(parsed, MAX_LIMIT);
}

function bearerToken(authorization) {
  if (typeof authorization !== "string") {
    return "";
  }

  const match = authorization.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim() ?? "";
}

function matchesSecret(received, expected) {
  if (!isNonEmptyString(received) || !isNonEmptyString(expected)) {
    return false;
  }

  const receivedBuffer = Buffer.from(received);
  const expectedBuffer = Buffer.from(expected);
  return receivedBuffer.length === expectedBuffer.length &&
    timingSafeEqual(receivedBuffer, expectedBuffer);
}

function stringValue(value) {
  return typeof value === "string" ? value : "";
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
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
