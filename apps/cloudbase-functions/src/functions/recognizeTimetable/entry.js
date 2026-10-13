import { createHash, timingSafeEqual } from "node:crypto";
import { assertAppAuthenticated } from "../../auth/appAuth.js";
import { callBailianVision } from "./bailianClient.js";
import { parseExchangeDocument } from "./document.js";
import { parseImages } from "./images.js";
import { buildUserContent, RECOGNITION_PROMPT_ZH_HANS } from "./prompt.js";

const EXPECTED_APP_SIGNATURE = "beforeshow-app-signature-v1";
const RATE_LIMIT_COLLECTION = "timetableRecognitionRateLimits";
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;
const MAX_PER_INSTANCE_PER_WINDOW = 10;
const MAX_GLOBAL_PER_WINDOW = 200;

export async function main(event = {}, context = {}, options = {}) {
  const body = parseRequestBody(event);

  let auth;
  try {
    auth = assertAppAuthenticated(authEvent(event, body), context);
  } catch (err) {
    return errorResponse(
      err?.code || "APP_AUTH_REQUIRED",
      err?.message || "Generation calls require app-level authentication."
    );
  }

  if (!matchesExpectedSignature(
    body?.appSignature ?? event.appSignature ?? context.appSignature,
    options.expectedAppSignature ?? EXPECTED_APP_SIGNATURE
  )) {
    return errorResponse("APP_AUTH_INVALID", "Invalid app authentication.");
  }

  const imagesResult = parseImages(body);
  if (!imagesResult.ok) {
    return errorResponse(imagesResult.code, imagesResult.message);
  }

  const now = options.now?.() ?? new Date();
  const consumeRateLimit = options.consumeRateLimit ?? consumeRecognitionRateLimit;

  let allowed;
  try {
    allowed = await consumeRateLimit({
      appInstanceId: auth.appInstanceId,
      now
    });
  } catch {
    return errorResponse("RATE_LIMIT_UNAVAILABLE", "Recognition rate limit is unavailable.");
  }

  if (!allowed) {
    return errorResponse("RATE_LIMITED", "Too many timetable recognition requests.");
  }

  const prompt = options.prompt ?? RECOGNITION_PROMPT_ZH_HANS;
  const promptContent = buildUserContent(imagesResult.images, prompt);
  const callModel = options.callModel ?? callBailianVision;

  let modelResult;
  try {
    modelResult = await callModel({
      images: imagesResult.images,
      promptContent
    });
  } catch (err) {
    const code = err?.code === "MODEL_UNAVAILABLE" ? "MODEL_UNAVAILABLE" : "MODEL_FAILED";
    return errorResponse(code, err?.message || "Model request failed.");
  }

  const parsed = parseExchangeDocument(modelResult.content);
  if (!parsed.ok) {
    return errorResponse(parsed.code, parsed.message);
  }

  return {
    ok: true,
    document: parsed.document,
    model: modelResult.model ?? null,
    usage: summarizeUsage(modelResult.usage)
  };
}

function summarizeUsage(usage) {
  if (!usage || typeof usage !== "object") {
    return null;
  }
  return {
    promptTokens: usage.prompt_tokens ?? null,
    completionTokens: usage.completion_tokens ?? null,
    totalTokens: usage.total_tokens ?? null
  };
}

function parseRequestBody(event) {
  if (event && typeof event === "object" && event.body !== undefined) {
    if (typeof event.body === "string") {
      try {
        return JSON.parse(event.body || "{}");
      } catch {
        return {};
      }
    }
    if (event.body && typeof event.body === "object") {
      return event.body;
    }
  }
  return event && typeof event === "object" ? event : {};
}

function authEvent(event, body) {
  return {
    appInstanceId: body?.appInstanceId ?? event?.appInstanceId,
    appSignature: body?.appSignature ?? event?.appSignature
  };
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

function errorResponse(code, message) {
  return {
    ok: false,
    error: { code, message }
  };
}

async function consumeRecognitionRateLimit({ appInstanceId, now }) {
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

  let allowed = false;
  await db.runTransaction(async (transaction) => {
    const globalRef = transaction.collection(RATE_LIMIT_COLLECTION).doc(globalDocumentId);
    const instanceRef = transaction.collection(RATE_LIMIT_COLLECTION).doc(instanceDocumentId);

    const globalResult = await safeGetDoc(globalRef);
    const instanceResult = await safeGetDoc(instanceRef);
    const globalCount = documentCount(globalResult);
    const instanceCount = documentCount(instanceResult);

    if (globalCount >= MAX_GLOBAL_PER_WINDOW ||
        instanceCount >= MAX_PER_INSTANCE_PER_WINDOW) {
      allowed = false;
      return { allowed: false };
    }

    await globalRef.set({
      kind: "global",
      windowStart,
      count: globalCount + 1,
      expiresAt
    });
    await instanceRef.set({
      kind: "instance",
      windowStart,
      count: instanceCount + 1,
      expiresAt
    });
    allowed = true;
    return { allowed: true };
  });

  return allowed;
}

async function ensureCollection(db, name) {
  try {
    await db.createCollection(name);
  } catch {
    // Collection may already exist.
  }
}

async function safeGetDoc(ref) {
  try {
    return await ref.get();
  } catch {
    return { data: [] };
  }
}

function documentCount(result) {
  const data = result?.data;
  if (Array.isArray(data) && data.length > 0) {
    return Number(data[0].count) || 0;
  }
  if (data && typeof data === "object" && !Array.isArray(data)) {
    return Number(data.count) || 0;
  }
  return 0;
}
