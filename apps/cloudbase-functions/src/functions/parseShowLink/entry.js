import { assertAppAuthenticated } from "../../auth/appAuth.js";
import { createTechnicalLog } from "../../logging/technicalLog.js";
import { parseShowLink, UnsupportedPlatformError } from "./index.js";

export async function main(event = {}, context = {}, options = {}) {
  const body = parseRequestBody(event);
  const auth = assertAppAuthenticated(authEvent(event, body), context);
  const url = body?.url ?? event.url;

  if (typeof url !== "string" || url.trim().length === 0) {
    return {
      ok: false,
      error: {
        code: "URL_REQUIRED",
        message: "A show link URL is required."
      }
    };
  }

  const startedAt = Date.now();

  try {
    const draft = await parseShowLink(url, options);

    return {
      ok: true,
      auth: {
        accountless: auth.accountless
      },
      draft,
      log: createTechnicalLog({
        event: "parseShowLink.request.completed",
        source: draft.source,
        url: url.slice(0, 200),
        success: true,
        durationMs: Date.now() - startedAt
      })
    };
  } catch (error) {
    const isUnsupported = error instanceof UnsupportedPlatformError;

    return {
      ok: false,
      auth: {
        accountless: auth.accountless
      },
      error: {
        code: isUnsupported ? "UNSUPPORTED_PLATFORM" : "PARSE_FAILED",
        message: error.message
      },
      log: createTechnicalLog({
        event: "parseShowLink.request.failed",
        url: url.slice(0, 200),
        success: false,
        errorCode: isUnsupported ? "UNSUPPORTED_PLATFORM" : "PARSE_FAILED",
        errorMessage: error.message,
        durationMs: Date.now() - startedAt
      })
    };
  }
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
