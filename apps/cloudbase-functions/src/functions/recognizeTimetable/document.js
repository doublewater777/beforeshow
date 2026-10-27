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

/** Attempt to repair common JSON malformations like trailing commas or unclosed brackets. */
export function repairJson(str) {
  if (typeof str !== "string") {
    return null;
  }
  try {
    return JSON.parse(str);
  } catch {}

  const cleaned = str.replace(/,\s*([}\]])/g, "$1");
  try {
    return JSON.parse(cleaned);
  } catch {}

  let inString = false;
  let escape = false;
  const stack = [];
  for (let i = 0; i < cleaned.length; i++) {
    const c = cleaned[i];
    if (escape) {
      escape = false;
      continue;
    }
    if (c === "\\") {
      escape = true;
      continue;
    }
    if (c === '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (c === "{" || c === "[") {
      stack.push(c);
    } else if (c === "}" || c === "]") {
      stack.pop();
    }
  }

  let suffix = "";
  while (stack.length > 0) {
    const top = stack.pop();
    suffix += top === "{" ? "}" : "]";
  }

  try {
    return JSON.parse(cleaned + suffix);
  } catch {}

  return null;
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

  const parsed = repairJson(jsonText);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return { ok: false, code: "INVALID_MODEL_OUTPUT", message: "Model output is not valid JSON." };
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

function unnestDays(rawDays) {
  if (!Array.isArray(rawDays)) return [];
  const days = [];
  for (const day of rawDays) {
    if (!day || typeof day !== "object") continue;
    const directStages = [];
    const nestedDays = [];
    for (const stage of (day.stages || [])) {
      if (stage && typeof stage === "object" && stage.date && Array.isArray(stage.stages)) {
        nestedDays.push(stage);
      } else {
        directStages.push(stage);
      }
    }
    days.push({ ...day, stages: directStages });
    for (const nested of nestedDays) {
      days.push(...unnestDays([nested]));
    }
  }
  return days;
}

function normalizeDocument(doc) {
  const flattenedDays = unnestDays(doc.days);
  return {
    version: 1,
    timeZone: normalizeNullableString(doc.timeZone),
    days: flattenedDays.map((day) => ({
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
