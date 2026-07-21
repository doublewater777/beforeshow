import {
  validateGenerationResponse
} from "../../contracts/generationContracts.js";
import { callOpenAICompatibleProvider, streamOpenAICompatibleProvider } from "../../providers/openAICompatibleClient.js";
import { formatSseEvent } from "../../providers/streamJsonItems.js";

/**
 * Async generator of SSE wire frames for streaming generate.
 * Frames are already formatted `event: ...\ndata: ...\n\n` strings.
 *
 * Provider isolation: each provider keeps progressive items private until its
 * final response passes `validateGenerationResponse`. Only then are items + done sent.
 * A failed provider never leaks items into the client stream (no A/B mix).
 */
export async function* generateSseFrames(request, options = {}) {
  const providers = options.providers;
  if (!Array.isArray(providers) || providers.length === 0) {
    yield formatSseEvent("error", {
      code: "NO_PROVIDERS",
      message: "No model providers configured."
    });
    return;
  }

  const streamProvider = options.streamProvider ?? streamOpenAICompatibleProvider;
  const callProvider = options.callProvider ?? callOpenAICompatibleProvider;
  const providerErrors = [];

  for (let index = 0; index < providers.length; index += 1) {
    const provider = providers[index];
    const usedFallback = index > 0;
    try {
      let finalResponse = null;
      let durationMs = undefined;

      // Meta is informational only; no item is emitted until this provider validates.
      yield formatSseEvent("meta", {
        provider: provider.name,
        usedFallback,
        type: request.type
      });

      for await (const message of streamProvider(provider, request, options)) {
        if (message.kind === "item" && request.type === "candidateSongs") {
          // Progress remains provider-local until the final JSON validates.
          continue;
        }

        if (message.kind === "done") {
          finalResponse = message.response;
          durationMs = message.durationMs;
        }
      }

      if (!finalResponse) {
        throw new Error("Stream ended without a final response.");
      }

      const validated = validateGenerationResponse(request.type, finalResponse, request.limits);

      // Emit the authoritative validated items, then done. Provider-local progress
      // may differ from the model's final corrected JSON and is deliberately not forwarded.
      if (request.type === "candidateSongs" && Array.isArray(validated.items)) {
        for (const item of validated.items) {
          yield formatSseEvent("item", { item });
        }
      }

      yield formatSseEvent("done", {
        ok: true,
        request: {
          requestId: request.requestId,
          type: request.type
        },
        provider: {
          name: provider.name,
          usedFallback
        },
        response: validated,
        durationMs,
        providerErrors
      });
      return;
    } catch (error) {
      providerErrors.push({
        provider: provider.name,
        code: error.code ?? "PROVIDER_FAILED"
      });
      // Discard this provider attempt; try next.
    }
  }

  // Last resort: non-stream single-shot on first provider that works.
  for (let index = 0; index < providers.length; index += 1) {
    const provider = providers[index];
    try {
      const result = await callProvider(provider, request, options);
      const validated = validateGenerationResponse(request.type, result.response, request.limits);
      if (request.type === "candidateSongs" && Array.isArray(validated.items)) {
        for (const item of validated.items) {
          yield formatSseEvent("item", { item });
        }
      }
      yield formatSseEvent("done", {
        ok: true,
        request: {
          requestId: request.requestId,
          type: request.type
        },
        provider: {
          name: provider.name,
          usedFallback: index > 0 || providerErrors.length > 0
        },
        response: validated,
        durationMs: result.durationMs,
        providerErrors
      });
      return;
    } catch (error) {
      providerErrors.push({
        provider: provider.name,
        code: error.code ?? "PROVIDER_FAILED"
      });
    }
  }

  yield formatSseEvent("error", {
    code: "NO_VALID_PROVIDER_RESPONSE",
    message: "No provider returned a valid streamed response.",
    providerErrors
  });
}
