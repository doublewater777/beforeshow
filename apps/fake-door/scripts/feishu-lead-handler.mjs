import { spawn } from "node:child_process";

function toFeishuFields(body) {
  return {
    邮箱: body.email ?? "",
    演出: body.show ?? "",
    会话ID: body.session ?? "",
    提交时间: body.submitted_at ?? new Date().toISOString(),
    来源: body.source ?? "fake-door",
  };
}

async function submitViaWebhook(webhookUrl, body) {
  const upstream = await fetch(webhookUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      email: body.email ?? "",
      show: body.show ?? "",
      session: body.session ?? "",
      submitted_at: body.submitted_at ?? new Date().toISOString(),
      source: body.source ?? "fake-door",
    }),
  });

  const text = await upstream.text();
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = { raw: text };
  }

  if (!upstream.ok) {
    return {
      ok: false,
      status: upstream.status,
      error: "飞书 webhook 返回错误",
      detail: parsed,
    };
  }

  return { ok: true, mode: "webhook", feishu: parsed };
}

function runLarkCli(args) {
  return new Promise((resolve, reject) => {
    const child = spawn("lark-cli", args, { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (c) => { stdout += c; });
    child.stderr.on("data", (c) => { stderr += c; });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) {
        reject(new Error(stderr.trim() || stdout.trim() || `lark-cli exit ${code}`));
        return;
      }
      try {
        resolve(stdout ? JSON.parse(stdout) : {});
      } catch {
        resolve({ raw: stdout });
      }
    });
  });
}

async function submitViaBitable({ baseToken, tableId, identity }, body) {
  const fields = toFeishuFields(body);
  const args = [
    "base", "+record-upsert",
    "--base-token", baseToken,
    "--table-id", tableId,
    "--json", JSON.stringify(fields),
    "--format", "json",
  ];
  if (identity) args.splice(2, 0, "--as", identity);
  const result = await runLarkCli(args);

  return { ok: true, mode: "bitable", feishu: result };
}

export async function submitLead(env, body) {
  const mode = env.FEISHU_LEAD_MODE || (env.FEISHU_WEBHOOK_URL ? "webhook" : "");

  if (mode === "bitable" || (env.FEISHU_BASE_TOKEN && env.FEISHU_TABLE_ID)) {
    if (!env.FEISHU_BASE_TOKEN || !env.FEISHU_TABLE_ID) {
      return { ok: false, error: "缺少 FEISHU_BASE_TOKEN 或 FEISHU_TABLE_ID" };
    }
    try {
      return await submitViaBitable(
        {
          baseToken: env.FEISHU_BASE_TOKEN,
          tableId: env.FEISHU_TABLE_ID,
          identity: env.FEISHU_IDENTITY || "user",
        },
        body,
      );
    } catch (err) {
      return {
        ok: false,
        error: err instanceof Error ? err.message : "lark-cli 写入失败",
      };
    }
  }

  if (env.FEISHU_WEBHOOK_URL) {
    return submitViaWebhook(env.FEISHU_WEBHOOK_URL, body);
  }

  return {
    ok: false,
    error: "未配置飞书：运行 bash scripts/setup-feishu-bitable.sh，或设置 FEISHU_WEBHOOK_URL",
  };
}