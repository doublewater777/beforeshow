export const MODEL_PROVIDERS = {
  doubao: {
    name: "doubao",
    label: "Volcengine Doubao",
    apiKeyEnv: "DOUBAO_API_KEY",
    baseUrlEnv: "DOUBAO_BASE_URL",
    modelEnv: "DOUBAO_MODEL",
    defaultBaseUrl: "https://ark.cn-beijing.volces.com/api/v3/chat/completions",
    defaultModel: "doubao-seed-1-6"
  },
  qwen: {
    name: "qwen",
    label: "Alibaba Qwen",
    apiKeyEnv: "QWEN_API_KEY",
    baseUrlEnv: "QWEN_BASE_URL",
    modelEnv: "QWEN_MODEL",
    defaultBaseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
    defaultModel: "qwen-plus"
  }
};

export function loadModelProviderConfig(env = process.env) {
  return {
    primary: providerConfig(MODEL_PROVIDERS.doubao, env),
    fallback: providerConfig(MODEL_PROVIDERS.qwen, env)
  };
}

export function providerSequence(env = process.env) {
  const config = loadModelProviderConfig(env);
  return [config.primary, config.fallback];
}

function providerConfig(provider, env) {
  const config = {
    name: provider.name,
    label: provider.label,
    apiKeyEnv: provider.apiKeyEnv,
    baseUrl: env[provider.baseUrlEnv] || provider.defaultBaseUrl,
    model: env[provider.modelEnv] || provider.defaultModel
  };

  Object.defineProperty(config, "apiKey", {
    value: env[provider.apiKeyEnv],
    enumerable: false
  });

  return config;
}
