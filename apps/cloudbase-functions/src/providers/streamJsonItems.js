/**
 * Progressive extractor for model JSON of the form:
 * { "type":"candidateSongs", "items":[ {...}, {...} ] }
 *
 * Yields complete item objects as soon as each `{...}` in the items array closes.
 */
export function createCandidateSongsItemExtractor() {
  let buffer = "";
  let itemsContentStart = -1;
  let scanIndex = 0;
  let inString = false;
  let escape = false;
  let depth = 0;
  let objectStart = -1;
  const emitted = [];

  function tryStartItems() {
    if (itemsContentStart >= 0) {
      return true;
    }
    const match = /"items"\s*:\s*\[/.exec(buffer);
    if (!match) {
      return false;
    }
    itemsContentStart = match.index + match[0].length;
    scanIndex = itemsContentStart;
    return true;
  }

  function push(chunk) {
    if (typeof chunk !== "string" || chunk.length === 0) {
      return [];
    }
    buffer += chunk;
    if (!tryStartItems()) {
      return [];
    }

    const newlyEmitted = [];
    while (scanIndex < buffer.length) {
      const ch = buffer[scanIndex];

      if (inString) {
        if (escape) {
          escape = false;
        } else if (ch === "\\") {
          escape = true;
        } else if (ch === "\"") {
          inString = false;
        }
        scanIndex += 1;
        continue;
      }

      if (ch === "\"") {
        inString = true;
        scanIndex += 1;
        continue;
      }

      if (ch === "{") {
        if (depth === 0) {
          objectStart = scanIndex;
        }
        depth += 1;
        scanIndex += 1;
        continue;
      }

      if (ch === "}") {
        if (depth > 0) {
          depth -= 1;
          if (depth === 0 && objectStart >= 0) {
            const raw = buffer.slice(objectStart, scanIndex + 1);
            try {
              const item = JSON.parse(raw);
              if (item && typeof item === "object" && !Array.isArray(item)) {
                emitted.push(item);
                newlyEmitted.push(item);
              }
            } catch {
              // Incomplete / invalid object; keep scanning.
            }
            objectStart = -1;
          }
        }
        scanIndex += 1;
        continue;
      }

      scanIndex += 1;
    }

    return newlyEmitted;
  }

  function finalObject() {
    const trimmed = buffer.trim();
    if (!trimmed) {
      return null;
    }
    try {
      return JSON.parse(extractJsonObject(trimmed));
    } catch {
      // A clean EOF is not proof that the model completed its JSON document.
      // Never promote already-extracted items into an authoritative response;
      // callers must fail/fallback unless the complete object parses.
      return null;
    }
  }

  return {
    push,
    finalObject,
    get buffer() {
      return buffer;
    },
    get items() {
      return emitted.slice();
    }
  };
}

export function extractJsonObject(content) {
  const trimmed = content.trim();
  if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
    return trimmed;
  }

  const start = trimmed.indexOf("{");
  const end = trimmed.lastIndexOf("}");
  if (start >= 0 && end > start) {
    return trimmed.slice(start, end + 1);
  }

  throw new Error("Model content did not contain a JSON object.");
}

export function formatSseEvent(event, data) {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
}

/**
 * Parse OpenAI-compatible chat completion SSE payload chunks into content deltas.
 */
export function parseOpenAIStreamChunk(rawLine) {
  const line = rawLine.trim();
  if (!line.startsWith("data:")) {
    return { kind: "ignore" };
  }
  const payload = line.slice(5).trim();
  if (!payload) {
    return { kind: "ignore" };
  }
  if (payload === "[DONE]") {
    return { kind: "done" };
  }
  try {
    const json = JSON.parse(payload);
    const delta = json?.choices?.[0]?.delta?.content;
    if (typeof delta === "string" && delta.length > 0) {
      return { kind: "delta", text: delta };
    }
    const full = json?.choices?.[0]?.message?.content;
    if (typeof full === "string" && full.length > 0) {
      return { kind: "delta", text: full };
    }
    return { kind: "ignore" };
  } catch {
    return { kind: "ignore" };
  }
}
