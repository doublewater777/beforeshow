import { ContractError } from "../contracts/generationContracts.js";
import {
  createCandidateSongsItemExtractor,
  extractJsonObject as extractJsonObjectShared,
  parseOpenAIStreamChunk
} from "./streamJsonItems.js";

export class ProviderCallError extends Error {
  constructor(code, message, provider, cause) {
    super(message);
    this.name = "ProviderCallError";
    this.code = code;
    this.provider = provider;
    this.cause = cause;
  }
}

function assertProviderReady(provider, fetchImpl) {
  if (typeof fetchImpl !== "function") {
    throw new ProviderCallError(
      "FETCH_UNAVAILABLE",
      "Fetch is unavailable in this runtime.",
      provider.name
    );
  }

  if (!provider.apiKey) {
    throw new ProviderCallError(
      "PROVIDER_API_KEY_MISSING",
      `${provider.apiKeyEnv} is required.`,
      provider.name
    );
  }
}

function chatCompletionBody(provider, request, { stream }) {
  return {
    model: provider.model,
    temperature: 0.2,
    stream: stream === true,
    response_format: { type: "json_object" },
    messages: [
      {
        role: "system",
        content: systemPromptFor(request)
      },
      {
        role: "user",
        content: JSON.stringify(safePromptPayload(request))
      }
    ]
  };
}

export async function callOpenAICompatibleProvider(provider, request, options = {}) {
  const fetchImpl = options.fetch ?? globalThis.fetch;
  assertProviderReady(provider, fetchImpl);

  const startedAt = Date.now();
  const response = await fetchImpl(provider.baseUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${provider.apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(chatCompletionBody(provider, request, { stream: false }))
  });

  const durationMs = Date.now() - startedAt;
  const rawText = await response.text();

  if (!response.ok) {
    throw new ProviderCallError(
      "PROVIDER_HTTP_ERROR",
      `${provider.name} returned HTTP ${response.status}.`,
      provider.name
    );
  }

  try {
    const providerEnvelope = JSON.parse(rawText);
    const content = providerEnvelope?.choices?.[0]?.message?.content;
    if (typeof content !== "string" || content.trim().length === 0) {
      throw new ContractError("EMPTY_MODEL_CONTENT", "Model returned empty content.");
    }

    return {
      provider: provider.name,
      durationMs,
      response: JSON.parse(extractJsonObject(content))
    };
  } catch (error) {
    if (error instanceof ProviderCallError) {
      throw error;
    }

    throw new ProviderCallError(
      "PROVIDER_RESPONSE_PARSE_ERROR",
      `${provider.name} returned an invalid JSON response.`,
      provider.name,
      error
    );
  }
}

/**
 * Stream OpenAI-compatible chat completions.
 * Yields:
 *   { kind: "item", item }
 *   { kind: "done", response, durationMs }
 */
export async function* streamOpenAICompatibleProvider(provider, request, options = {}) {
  const fetchImpl = options.fetch ?? globalThis.fetch;
  assertProviderReady(provider, fetchImpl);

  const startedAt = Date.now();
  const response = await fetchImpl(provider.baseUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${provider.apiKey}`,
      "Content-Type": "application/json",
      Accept: "text/event-stream"
    },
    body: JSON.stringify(chatCompletionBody(provider, request, { stream: true }))
  });

  if (!response.ok) {
    throw new ProviderCallError(
      "PROVIDER_HTTP_ERROR",
      `${provider.name} returned HTTP ${response.status}.`,
      provider.name
    );
  }

  if (!response.body || typeof response.body.getReader !== "function") {
    // Some test/mock environments only return text(); fall back to non-stream parse.
    const rawText = await response.text();
    const providerEnvelope = JSON.parse(rawText);
    const content = providerEnvelope?.choices?.[0]?.message?.content;
    if (typeof content !== "string" || content.trim().length === 0) {
      throw new ContractError("EMPTY_MODEL_CONTENT", "Model returned empty content.");
    }
    const parsed = JSON.parse(extractJsonObject(content));
    if (Array.isArray(parsed.items)) {
      for (const item of parsed.items) {
        yield { kind: "item", item };
      }
    }
    yield {
      kind: "done",
      response: parsed,
      durationMs: Date.now() - startedAt
    };
    return;
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let lineBuffer = "";
  const extractor = createCandidateSongsItemExtractor();
  let fullContent = "";

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }
      lineBuffer += decoder.decode(value, { stream: true });
      const lines = lineBuffer.split(/\r?\n/);
      lineBuffer = lines.pop() ?? "";

      for (const line of lines) {
        const parsed = parseOpenAIStreamChunk(line);
        if (parsed.kind === "done") {
          continue;
        }
        if (parsed.kind !== "delta") {
          continue;
        }
        fullContent += parsed.text;
        if (request.type === "candidateSongs") {
          const items = extractor.push(parsed.text);
          for (const item of items) {
            yield { kind: "item", item };
          }
        }
      }
    }

    if (lineBuffer.trim()) {
      const parsed = parseOpenAIStreamChunk(lineBuffer);
      if (parsed.kind === "delta") {
        fullContent += parsed.text;
        if (request.type === "candidateSongs") {
          const items = extractor.push(parsed.text);
          for (const item of items) {
            yield { kind: "item", item };
          }
        }
      }
    }
  } finally {
    try {
      reader.releaseLock();
    } catch {
      // ignore
    }
  }

  let finalResponse = extractor.finalObject();
  if (!finalResponse) {
    if (!fullContent.trim()) {
      throw new ContractError("EMPTY_MODEL_CONTENT", "Model returned empty content.");
    }
    try {
      finalResponse = JSON.parse(extractJsonObject(fullContent));
    } catch (error) {
      throw new ProviderCallError(
        "PROVIDER_RESPONSE_PARSE_ERROR",
        `${provider.name} returned an invalid JSON response.`,
        provider.name,
        error
      );
    }
  }

  // If progressive extraction missed items, emit remaining from final parse once.
  if (
    request.type === "candidateSongs" &&
    Array.isArray(finalResponse.items) &&
    extractor.items.length < finalResponse.items.length
  ) {
    const already = new Set(
      extractor.items.map((item) => `${item.songName}\0${item.artist}`)
    );
    for (const item of finalResponse.items) {
      const key = `${item.songName}\0${item.artist}`;
      if (!already.has(key)) {
        yield { kind: "item", item };
      }
    }
  }

  yield {
    kind: "done",
    response: finalResponse,
    durationMs: Date.now() - startedAt
  };
}

function systemPromptFor(request) {
  const { type } = request;
  const common = [
    "You are the BeforeShow backend generation service.",
    "Return only one JSON object. Do not return markdown, prose, comments, or code fences.",
    "Use concise Simplified Chinese where natural."
  ].join("\n");

  const noMediaOrIds =
    "Do not include lyrics, numeric confidence scores, cover URLs, audio URLs, video URLs, comments, danmaku, page contents, or platform IDs.";

  if (type === "candidateSongs") {
    const isFestival = request.show?.type === "musicFestival";
    const maxSongs = request.limits?.maxSongs;
    const targetSongs = isFestival
      ? Math.max(10, request.limits?.targetSongs ?? maxSongs ?? 10)
      : (request.limits?.targetSongs ?? maxSongs);
    const quantityRequirement = targetSongs === undefined
      ? "Return a useful setlist-sized list of songs."
      : `Aim for about ${targetSongs} songs${maxSongs ? ` (never more than ${maxSongs})` : ""}. If selected artists genuinely have fewer plausible songs, return all credible songs rather than inventing filler.`;
    const artistCoverage = isFestival
      ? "Include songs across the full provided artist list when possible; do not collapse to only one or two acts."
      : "Prefer the show headliner; include guest acts only when listed.";

    // Short `hint` is intentional product copy (曲目短因), not long recommendation prose.
    return [
      common,
      noMediaOrIds,
      'Return exactly: {"type":"candidateSongs","items":[{"songName":"...","artist":"...","tier":"high|mid|guest|encore","hint":"..."}]}.',
      quantityRequirement,
      artistCoverage,
      'tier is required and must be one of "high", "mid", "guest", or "encore".',
      "Use a realistic live-set mix: about 2–4 high near the front, mostly mid in the middle, 0–1 guest when a collab/guest is plausible, and 1–2 encore near the end. Do not mark every song mid.",
      "hint is required: a short Chinese reason (about 6–12 characters) for why this song might appear, e.g. 这轮巡演主题曲 / 近巡必唱 / 嘉宾合作曲 / 安可位常客. Not a long review or free-form recommendation essay.",
      "Order items as a guessed live-show setlist order."
    ].join("\n");
  }

  if (type === "roundTripDraft") {
    return [
      common,
      noMediaOrIds,
      "Do not invent long recommendation narratives.",
      'Return exactly: {"type":"roundTripDraft","direction":"outbound|return","summary":"...","steps":[{"title":"...","detail":"..."}],"evidence":[{"title":"...","url":"..."}]}. Include evidence only when it is reliable; never invent specific traffic facts.'
    ].join("\n");
  }

  return `${common}\n${noMediaOrIds}\nDo not invent long recommendation narratives.`;
}

function safePromptPayload(request) {
  return {
    type: request.type,
    locale: request.locale ?? "zh-CN",
    show: request.show,
    ...(request.limits === undefined ? {} : { limits: request.limits }),
    ...(request.direction === undefined ? {} : { direction: request.direction }),
    ...(request.userPlaces === undefined ? {} : { userPlaces: request.userPlaces }),
    ...(request.constraints === undefined ? {} : { constraints: request.constraints })
  };
}

function extractJsonObject(content) {
  try {
    return extractJsonObjectShared(content);
  } catch {
    throw new ContractError("JSON_OBJECT_NOT_FOUND", "Model content did not contain a JSON object.");
  }
}
