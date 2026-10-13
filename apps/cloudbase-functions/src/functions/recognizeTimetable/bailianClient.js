const DEFAULT_BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1";
const DEFAULT_MODEL = "qwen3.7-flash";

/**
 * Call DashScope / MaaS OpenAI-compatible chat completions with vision.
 * Inject via options.callModel in tests.
 */
export async function callBailianVision({
  images,
  promptContent,
  apiKey = process.env.DASHSCOPE_API_KEY,
  baseUrl = process.env.DASHSCOPE_BASE_URL || DEFAULT_BASE_URL,
  model = process.env.TIMETABLE_MODEL || DEFAULT_MODEL,
  fetchImpl = globalThis.fetch,
  timeoutMs = 90_000
} = {}) {
  if (!apiKey || typeof apiKey !== "string" || apiKey.trim().length === 0) {
    const error = new Error("DASHSCOPE_API_KEY is not configured.");
    error.code = "MODEL_UNAVAILABLE";
    throw error;
  }

  const root = String(baseUrl).replace(/\/$/, "");
  const url = `${root}/chat/completions`;
  const body = {
    model,
    temperature: 0.1,
    max_tokens: 4096,
    enable_thinking: false,
    messages: [
      {
        role: "user",
        content: promptContent
      }
    ]
  };

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  let response;
  try {
    response = await fetchImpl(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey.trim()}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(body),
      signal: controller.signal
    });
  } catch (err) {
    const error = new Error(
      err?.name === "AbortError" ? "Model request timed out." : `Model request failed: ${err.message}`
    );
    error.code = "MODEL_FAILED";
    throw error;
  } finally {
    clearTimeout(timer);
  }

  const raw = await response.text();
  let payload;
  try {
    payload = raw ? JSON.parse(raw) : {};
  } catch {
    const error = new Error(`Model returned non-JSON HTTP ${response.status}.`);
    error.code = "MODEL_FAILED";
    throw error;
  }

  if (!response.ok) {
    const message = payload?.error?.message || payload?.message || `HTTP ${response.status}`;
    const error = new Error(message);
    error.code = "MODEL_FAILED";
    error.status = response.status;
    throw error;
  }

  const choice = payload?.choices?.[0];
  let content = choice?.message?.content ?? "";
  if (Array.isArray(content)) {
    content = content
      .map((part) => (typeof part === "string" ? part : part?.text ?? ""))
      .join("");
  }

  return {
    content: typeof content === "string" ? content : String(content ?? ""),
    usage: payload?.usage ?? null,
    model: payload?.model ?? model,
    finishReason: choice?.finish_reason ?? null
  };
}
