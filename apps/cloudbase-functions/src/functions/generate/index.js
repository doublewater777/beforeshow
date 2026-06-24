import { assertAppAuthenticated } from "../../auth/appAuth.js";
import { providerSequence } from "../../config/modelProviders.js";
import {
  selectValidProviderResponse,
  validateGenerationRequest
} from "../../contracts/generationContracts.js";
import { createTechnicalLog } from "../../logging/technicalLog.js";
import { callOpenAICompatibleProvider } from "../../providers/openAICompatibleClient.js";

export async function main(event = {}, context = {}, options = {}) {
  const body = parseRequestBody(event);
  const auth = assertAppAuthenticated(authEvent(event, body), context);
  const request = validateGenerationRequest(stripAppAuth(body));
  const providers = providerSequence(options.env).map((provider) => ({
    name: provider.name,
    model: provider.model,
    apiKeyEnv: provider.apiKeyEnv,
    baseUrl: provider.baseUrl
  }));
  const providerResults = [];
  const providerErrors = [];

  for (const provider of providerSequence(options.env)) {
    const startedAt = Date.now();
    try {
      providerResults.push(await callOpenAICompatibleProvider(provider, request, options));
    } catch (error) {
      providerErrors.push({
        provider: provider.name,
        code: error.code ?? "PROVIDER_FAILED",
        durationMs: Date.now() - startedAt
      });
      providerResults.push({
        provider: provider.name,
        error: error.code ?? "PROVIDER_FAILED"
      });
    }
  }

  const selected = selectValidProviderResponse(request.type, providerResults);
  const selectedDuration = providerResults.find(
    (result) => result.provider === selected.provider
  )?.durationMs;

  return {
    ok: true,
    request: {
      requestId: request.requestId,
      type: request.type
    },
    auth: {
      accountless: auth.accountless
    },
    provider: {
      name: selected.provider,
      usedFallback: selected.usedFallback
    },
    providers,
    response: selected.response,
    log: createTechnicalLog({
      event: "generation.request.completed",
      requestId: request.requestId,
      featureType: request.type,
      provider: selected.provider,
      success: true,
      usedFallback: selected.usedFallback,
      durationMs: selectedDuration
    }),
    providerErrors
  };
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
  if (isPlainObject(body)) {
    return { ...event, ...body };
  }

  return event;
}

function stripAppAuth(input) {
  if (!isPlainObject(input)) {
    return input;
  }

  const { appInstanceId, appSignature, ...businessInput } = input;
  return businessInput;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
