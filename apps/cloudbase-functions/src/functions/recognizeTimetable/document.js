const SUPPORTED_VERSION = 1;
const MAX_DOCUMENT_CHARS = 200_000;

/** Extract the outermost JSON object from model text (fences / stray prose). */
export function extractObject(text) {
  if (typeof text !== "string") {
    return null;
  }
  const trimmed = text.trim();
  const open = trimmed.indexOf("{");
  const close = trimmed.lastIndexOf("}");
  if (open < 0 || close <= open) {
    return null;
  }
  return trimmed.slice(open, close + 1);
}

/**
 * Parse and lightly normalize a TimetableExchangeDocument.
 * Mirrors TimetableImportParser version/shape gates; normalizes END/TBA ends.
 */
export function parseExchangeDocument(rawText) {
  if (typeof rawText !== "string" || rawText.trim().length === 0) {
    return { ok: false, code: "INVALID_MODEL_OUTPUT", message: "Model returned empty content." };
  }
  if (rawText.length > MAX_DOCUMENT_CHARS) {
    return { ok: false, code: "INVALID_MODEL_OUTPUT", message: "Model output is too large." };
  }

  const jsonText = extractObject(rawText);
  if (!jsonText) {
    return { ok: false, code: "INVALID_MODEL_OUTPUT", message: "Model output is not a JSON object." };
  }

  let parsed;
  try {
    parsed = JSON.parse(jsonText);
  } catch {
    return { ok: false, code: "INVALID_MODEL_OUTPUT", message: "Model output is not valid JSON." };
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return { ok: false, code: "INVALID_MODEL_OUTPUT", message: "Model output must be a JSON object." };
  }

  if (parsed.version !== SUPPORTED_VERSION) {
    return {
      ok: false,
      code: "UNSUPPORTED_VERSION",
      message: `Unsupported timetable document version: ${String(parsed.version)}.`
    };
  }

  if (!Array.isArray(parsed.days)) {
    return { ok: false, code: "INVALID_MODEL_OUTPUT", message: "Document.days must be an array." };
  }

  const document = normalizeDocument(parsed);
  return { ok: true, document };
}

function normalizeDocument(doc) {
  return {
    version: 1,
    timeZone: normalizeNullableString(doc.timeZone),
    days: (doc.days || []).map((day) => ({
      date: normalizeNullableString(day?.date),
      stages: Array.isArray(day?.stages)
        ? day.stages.map((stage) => ({
            name: normalizeNullableString(stage?.name),
            performances: Array.isArray(stage?.performances)
              ? stage.performances.map((performance) => ({
                  artist: normalizeNullableString(performance?.artist),
                  start: normalizeNullableString(performance?.start),
                  end: normalizeEnd(performance?.end)
                }))
              : []
          }))
        : []
    }))
  };
}

function normalizeNullableString(value) {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value !== "string") {
    return String(value);
  }
  const trimmed = value.trim();
  if (!trimmed || trimmed.toLowerCase() === "null") {
    return null;
  }
  return trimmed;
}

function normalizeEnd(value) {
  const normalized = normalizeNullableString(value);
  if (normalized === null) {
    return null;
  }
  const upper = normalized.toUpperCase();
  if (upper === "END" || upper === "TBA") {
    return null;
  }
  return normalized;
}
