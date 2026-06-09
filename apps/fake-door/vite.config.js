import { defineConfig, loadEnv } from "vite";
import { submitLead } from "./scripts/feishu-lead-handler.mjs";

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function feishuLeadProxy(env) {
  return {
    name: "feishu-lead-proxy",
    configureServer(server) {
      server.middlewares.use("/api/leads", async (req, res, next) => {
        if (req.method === "OPTIONS") {
          res.statusCode = 204;
          res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
          res.setHeader("Access-Control-Allow-Headers", "Content-Type");
          res.end();
          return;
        }

        if (req.method !== "POST") return next();

        try {
          const raw = await readBody(req);
          const body = raw ? JSON.parse(raw) : {};
          const result = await submitLead(env, body);

          res.statusCode = result.ok ? 200 : (result.status || 502);
          res.setHeader("Content-Type", "application/json; charset=utf-8");
          res.end(JSON.stringify(result));
        } catch (err) {
          res.statusCode = 500;
          res.setHeader("Content-Type", "application/json; charset=utf-8");
          res.end(JSON.stringify({
            ok: false,
            error: err instanceof Error ? err.message : "代理请求失败",
          }));
        }
      });
    },
  };
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  return {
    plugins: [feishuLeadProxy(env)],
    server: {
      port: 5173,
    },
  };
});