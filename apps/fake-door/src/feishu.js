/**
 * Submit waitlist leads to Feishu Bitable via automation webhook.
 *
 * Browser → POST /api/leads (same origin)
 * Dev: Vite middleware forwards to FEISHU_WEBHOOK_URL
 * Prod: run scripts/feishu-lead-proxy.mjs or deploy to 云函数
 */

const LEAD_API = import.meta.env.VITE_LEAD_API_URL || "/api/leads";

export async function submitLeadToFeishu(lead) {
  const payload = {
    email: lead.email,
    show: lead.show,
    session: lead.session || "",
    submitted_at: lead.submitted_at || new Date().toISOString(),
    source: lead.source || "fake-door",
  };

  const res = await fetch(LEAD_API, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });

  const data = await res.json().catch(() => ({}));

  if (!res.ok || data.ok === false) {
    throw new Error(data.error || `提交失败（${res.status}）`);
  }

  return data;
}