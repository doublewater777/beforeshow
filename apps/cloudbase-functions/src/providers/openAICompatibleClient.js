import { ContractError } from "../contracts/generationContracts.js";

export class ProviderCallError extends Error {
  constructor(code, message, provider, cause) {
    super(message);
    this.name = "ProviderCallError";
    this.code = code;
    this.provider = provider;
    this.cause = cause;
  }
}

export async function callOpenAICompatibleProvider(provider, request, options = {}) {
  const fetchImpl = options.fetch ?? globalThis.fetch;

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

  const startedAt = Date.now();
  const response = await fetchImpl(provider.baseUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${provider.apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: provider.model,
      temperature: 0.2,
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
    })
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
    const targetSongs = request.show?.type === "musicFestival"
      ? Math.max(10, request.limits?.targetSongs ?? 10)
      : request.limits?.targetSongs;
    const quantityRequirement = targetSongs === undefined
      ? "Return a useful setlist-sized list of songs."
      : `Aim for ${targetSongs}–${request.limits?.maxSongs ?? targetSongs} songs. If the selected artist genuinely has fewer plausible songs, return all credible songs you can identify rather than inventing songs to reach the target.`;

    // Short `hint` is intentional product copy (曲目短因), not long recommendation prose.
    return [
      common,
      noMediaOrIds,
      'Return exactly: {"type":"candidateSongs","items":[{"songName":"...","artist":"...","tier":"high|mid|guest|encore","hint":"..."}]}.',
      quantityRequirement,
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
  const trimmed = content.trim();
  if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
    return trimmed;
  }

  const start = trimmed.indexOf("{");
  const end = trimmed.lastIndexOf("}");
  if (start >= 0 && end > start) {
    return trimmed.slice(start, end + 1);
  }

  throw new ContractError("JSON_OBJECT_NOT_FOUND", "Model content did not contain a JSON object.");
}
