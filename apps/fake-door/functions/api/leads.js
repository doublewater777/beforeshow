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
  return {
    email: body.email ?? "",
    show: body.show ?? "",
    session: body.session ?? "",
    submitted_at: body.submitted_at ?? new Date().toISOString(),
    source: body.source ?? "fake-door",
  };
}

export async function onRequestOptions() {
  return json({}, { status: 204 });
}

export async function onRequestPost(context) {
  const webhookUrl = context.env.FEISHU_WEBHOOK_URL;
  if (!webhookUrl) {
    return json({ ok: false, error: "未配置 FEISHU_WEBHOOK_URL" }, { status: 502 });
  }

  try {
    const body = await context.request.json();
    const upstream = await fetch(webhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(normalizeLead(body)),
    });

    const text = await upstream.text();
    let feishu;
    try {
      feishu = text ? JSON.parse(text) : {};
    } catch {
      feishu = { raw: text };
    }

    if (!upstream.ok) {
      return json({
        ok: false,
        status: upstream.status,
        error: "飞书 webhook 返回错误",
        detail: feishu,
      }, { status: upstream.status });
    }

    return json({ ok: true, mode: "webhook", feishu });
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
