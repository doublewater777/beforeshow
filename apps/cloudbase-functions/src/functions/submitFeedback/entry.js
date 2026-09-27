import { randomUUID } from "node:crypto";
import { assertAppAuthenticated } from "../../auth/appAuth.js";

const MAX_MESSAGE_LENGTH = 2000;
const MAX_DIAGNOSTIC_LENGTH = 160;

export async function main(event = {}, context = {}, options = {}) {
  const body = parseRequestBody(event);
  assertAppAuthenticated(authEvent(event, body), context);

  const message = typeof body?.message === "string" ? body.message.trim() : "";
  if (message.length === 0) {
    return {
      ok: false,
      error: {
        code: "MESSAGE_REQUIRED",
        message: "Feedback message is required."
      }
    };
  }

  if (message.length > MAX_MESSAGE_LENGTH) {
    return {
      ok: false,
      error: {
        code: "MESSAGE_TOO_LONG",
        message: "Feedback message is too long."
      }
    };
  }

  const feedbackId = (options.randomUUID ?? randomUUID)();
  const now = options.now?.() ?? new Date();
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
    return {
      ok: false,
      error: {
        code: "STORE_FAILED",
        message: "Feedback could not be stored."
      }
    };
  }
}

async function writeFeedbackToCloudDatabase(record) {
  // The deployment bundle installs the server SDK and keeps this dependency
  // external to esbuild so local unit tests can inject writeFeedback without it.
  const { default: cloudbase } = await import("@cloudbase/node-sdk");
  const app = cloudbase.init({});
  const db = app.database();
  const collectionName = "userFeedback";

  try {
    await db.collection(collectionName).add(record);
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

    await db.collection(collectionName).add(record);
  }
}

function normalizeDiagnostic(value) {
  if (typeof value !== "string") {
    return "";
  }
  return value.trim().slice(0, MAX_DIAGNOSTIC_LENGTH);
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
