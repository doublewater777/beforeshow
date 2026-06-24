const SENSITIVE_KEYS = new Set([
  "prompt",
  "rawPrompt",
  "rawOutput",
  "output",
  "response",
  "show",
  "showName",
  "venueName",
  "origin",
  "destination",
  "hotel",
  "meetingPoint",
  "items",
  "steps"
]);

const ALLOWED_LOG_KEYS = new Set([
  "event",
  "featureType",
  "provider",
  "success",
  "errorCode",
  "durationMs",
  "usedFallback",
  "requestId",
  "timestamp"
]);

export function createTechnicalLog(fields, now = new Date()) {
  const log = {
    event: fields.event ?? "generation",
    timestamp: now.toISOString()
  };

  for (const [key, value] of Object.entries(fields)) {
    if (ALLOWED_LOG_KEYS.has(key) && !SENSITIVE_KEYS.has(key)) {
      log[key] = value;
    }
  }

  return log;
}

export function containsSensitiveLogField(value) {
  if (Array.isArray(value)) {
    return value.some(containsSensitiveLogField);
  }

  if (value && typeof value === "object") {
    return Object.entries(value).some(([key, child]) => {
      if (SENSITIVE_KEYS.has(key)) {
        return true;
      }

      return containsSensitiveLogField(child);
    });
  }

  return false;
}
