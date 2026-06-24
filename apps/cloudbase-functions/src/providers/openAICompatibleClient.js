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
          content: systemPromptFor(request.type)
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

function systemPromptFor(type) {
  const common = [
    "You are the BeforeShow backend generation service.",
    "Return only one JSON object. Do not return markdown, prose, comments, or code fences.",
    "Do not include lyrics, recommendation reasons, confidence scores, cover URLs, audio URLs, video URLs, comments, danmaku, page contents, or platform IDs.",
    "Use concise Simplified Chinese where natural."
  ].join("\n");

  if (type === "candidateSongs") {
    return `${common}\nReturn exactly: {"type":"candidateSongs","items":[{"songName":"...","artist":"..."}]}. Order items as a guessed live-show order.`;
  }

  if (type === "roundTripDraft") {
    return `${common}\nReturn exactly: {"type":"roundTripDraft","direction":"outbound|return","summary":"...","steps":[{"title":"...","detail":"..."}],"evidence":[{"title":"...","url":"..."}]}. Include evidence only when it is reliable; never invent specific traffic facts.`;
  }

  if (type === "showRecap") {
    return `${common}\nReturn exactly: {"type":"showRecap","items":[{"title":"...","source":"bilibili","bvid":"...","originalUrl":"https://www.bilibili.com/video/..."}]}. Store metadata only.`;
  }

  return common;
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
