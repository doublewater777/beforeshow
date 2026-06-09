import { execFileSync } from "node:child_process";

const namespaceId = "7ddf3a8d10dc490fb596d6b10f8123cd";

function wrangler(args) {
  return execFileSync("npx", ["wrangler", ...args], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"],
  });
}

const rawKeys = wrangler([
  "kv", "key", "list",
  "--remote",
  "--namespace-id", namespaceId,
  "--prefix", "lead:",
]);

const keys = JSON.parse(rawKeys);
const leads = keys.map(({ name }) => {
  const raw = wrangler([
    "kv", "key", "get",
    "--remote",
    name,
    "--namespace-id", namespaceId,
  ]);
  return JSON.parse(raw);
});

leads.sort((a, b) => String(a.submitted_at).localeCompare(String(b.submitted_at)));
console.log(JSON.stringify(leads, null, 2));
