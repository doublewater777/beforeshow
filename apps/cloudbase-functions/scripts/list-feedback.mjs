const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 100;

const url = process.env.FEEDBACK_ADMIN_URL;
const token = process.env.FEEDBACK_ADMIN_TOKEN;
const limit = parseLimit(process.argv.slice(2));
const asJSON = process.argv.includes("--json");

if (!url || !token) {
  console.error("Set FEEDBACK_ADMIN_URL and FEEDBACK_ADMIN_TOKEN before listing feedback.");
  process.exit(2);
}

const endpoint = new URL(url);
endpoint.searchParams.set("limit", String(limit));

const response = await fetch(endpoint, {
  headers: {
    Authorization: `Bearer ${token}`
  }
});

const payload = await response.json().catch(() => null);
if (!response.ok || !payload?.ok) {
  console.error(
    payload?.error?.code
      ? `Feedback lookup failed: ${payload.error.code}`
      : `Feedback lookup failed: HTTP ${response.status}`
  );
  process.exit(1);
}

const feedback = Array.isArray(payload.feedback) ? payload.feedback : [];

if (asJSON) {
  console.log(JSON.stringify(feedback, null, 2));
  process.exit(0);
}

if (feedback.length === 0) {
  console.log("No feedback yet.");
  process.exit(0);
}

for (const item of feedback) {
  const timestamp = item.submittedAt || "unknown time";
  const version = [item.appVersion, item.osVersion].filter(Boolean).join(" · ");
  console.log(`[${timestamp}] ${version}`);
  console.log(item.message || "");
  console.log(`id: ${item.feedbackId || "-"}`);
  console.log("");
}

function parseLimit(args) {
  const raw = args.find(arg => arg.startsWith("--limit="))?.split("=")[1];
  const parsed = Number.parseInt(raw ?? "", 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return DEFAULT_LIMIT;
  }
  return Math.min(parsed, MAX_LIMIT);
}
