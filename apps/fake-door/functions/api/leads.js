function json(body, init = {}) {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
      ...(init.headers || {}),
    },
  });
}

function normalizeLead(body) {
  const submittedAt = body.submitted_at ?? new Date().toISOString();

  return {
    email: String(body.email ?? "").trim(),
    show: String(body.show ?? "").trim(),
    session: body.session ?? "",
    submitted_at: submittedAt,
    source: body.source ?? "fake-door",
  };
}

function validateLead(lead) {
  if (!lead.email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(lead.email)) {
    return "请填写有效邮箱";
  }
  if (!lead.show) {
    return "请填写演出名称";
  }
  return "";
}

async function mirrorToFeishu(webhookUrl, lead) {
  if (!webhookUrl) return null;

  const upstream = await fetch(webhookUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(lead),
  });

  const text = await upstream.text();
  let body;
  try {
    body = text ? JSON.parse(text) : {};
  } catch {
    body = { raw: text };
  }

  return {
    ok: upstream.ok,
    status: upstream.status,
    body,
  };
}

export async function onRequestOptions() {
  return json({}, { status: 204 });
}

export async function onRequestPost(context) {
  try {
    const body = await context.request.json();
    const lead = normalizeLead(body);
    const validationError = validateLead(lead);

    if (validationError) {
      return json({ ok: false, error: validationError }, { status: 400 });
    }

    if (!context.env.BEFORESHOW_LEADS) {
      return json({ ok: false, error: "未配置 BEFORESHOW_LEADS KV" }, { status: 502 });
    }

    const id = `${Date.now()}-${crypto.randomUUID()}`;
    const key = `lead:${lead.submitted_at}:${id}`;
    await context.env.BEFORESHOW_LEADS.put(key, JSON.stringify({
      id,
      ...lead,
      user_agent: context.request.headers.get("user-agent") ?? "",
      ip_country: context.request.cf?.country ?? "",
    }));

    let feishu = null;
    let feishuError = null;
    try {
      feishu = await mirrorToFeishu(context.env.FEISHU_WEBHOOK_URL, lead);
    } catch (err) {
      feishuError = err instanceof Error ? err.message : "飞书镜像失败";
    }

    return json({
      ok: true,
      mode: "kv",
      id,
      mirrored: feishu?.ok === true,
      mirror_error: feishu?.ok === false ? "飞书 webhook 返回错误" : feishuError,
    });
  } catch (err) {
    return json({
      ok: false,
      error: err instanceof Error ? err.message : "代理失败",
    }, { status: 500 });
  }
}

export async function onRequest() {
  return json({ ok: false, error: "Not found" }, { status: 404 });
}
