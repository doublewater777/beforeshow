import {
  selectValidProviderResponse,
  validateGenerationResponse
} from "../../contracts/generationContracts.js";
import { callOpenAICompatibleProvider } from "../../providers/openAICompatibleClient.js";

/**
 * Doubao primary, Qwen only as fallback (ADR-0008).
 * Tries providers in order; stops as soon as one returns a contract-valid response.
 * Deletion test: without this, generate main re-implements always-call-both and drifts from ADR-0008.
 */
export async function generateWithFallback(request, options = {}) {
  const providers = options.providers;
  if (!Array.isArray(providers) || providers.length === 0) {
    throw new Error("generateWithFallback requires at least one provider.");
  }

  const callProvider = options.callProvider ?? callOpenAICompatibleProvider;
  const providerResults = [];
  const providerErrors = [];

  for (const provider of providers) {
    const startedAt = Date.now();
    try {
      const result = await callProvider(provider, request, options);
      providerResults.push(result);

      if (result.response === undefined) {
        providerErrors.push({
          provider: provider.name,
          code: "MISSING_RESPONSE",
          durationMs: Date.now() - startedAt
        });
        continue;
      }

      try {
        const response = validateGenerationResponse(request.type, result.response);
        return {
          selected: {
            provider: result.provider,
            response,
            usedFallback: providerResults.length > 1
          },
          providerResults,
          providerErrors,
          durationMs: result.durationMs ?? Date.now() - startedAt
        };
      } catch (error) {
        // Code only — avoid echoing forbidden field names (e.g. lyrics) into the API result.
        providerErrors.push({
          provider: provider.name,
          code: error.code ?? "INVALID_PROVIDER_RESPONSE",
          durationMs: Date.now() - startedAt
        });
      }
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

  // Preserve contract error shape when nothing valid remained.
  return {
    selected: selectValidProviderResponse(request.type, providerResults),
    providerResults,
    providerErrors,
    durationMs: undefined
  };
}
