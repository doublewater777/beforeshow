#!/usr/bin/env node
/**
 * 生产环境：静态站点 + /api/leads 飞书写入
 *
 * 用法（在 apps/fake-door 目录）：
 *   npm run build && npm run start
 *
 * 环境变量见 .env.example
 */

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { submitLead } from "./feishu-lead-handler.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const DIST = path.join(ROOT, "dist");
const ENV_FILE = path.join(ROOT, ".env");
const PORT = Number(process.env.PORT || 3000);
const HOST = process.env.HOST || "0.0.0.0";

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".webp": "image/webp",
  ".json": "application/json; charset=utf-8",
  ".woff2": "font/woff2",
};

function loadEnvFile(filePath) {
  const env = { ...process.env };
  if (!fs.existsSync(filePath)) return env;
  for (const line of fs.readFileSync(filePath, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const idx = trimmed.indexOf("=");
    if (idx === -1) continue;
    const key = trimmed.slice(0, idx).trim();
    const val = trimmed.slice(idx + 1).trim();
    if (key) env[key] = val;
  }
  return env;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function safePath(urlPath) {
  const decoded = decodeURIComponent(urlPath.split("?")[0]);
  const rel = decoded.replace(/^\/+/, "");
  const target = path.resolve(DIST, rel);
  if (!target.startsWith(DIST)) return null;
  return target;
}

function sendFile(res, filePath) {
  const ext = path.extname(filePath).toLowerCase();
  const type = MIME[ext] || "application/octet-stream";
  res.writeHead(200, { "Content-Type": type, "Cache-Control": ext === ".html" ? "no-cache" : "public, max-age=31536000, immutable" });
  fs.createReadStream(filePath).pipe(res);
}

const env = loadEnvFile(ENV_FILE);

const server = http.createServer(async (req, res) => {
  const url = req.url || "/";

  if (req.method === "OPTIONS" && url.startsWith("/api/leads")) {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    });
    res.end();
    return;
  }

  if (req.method === "POST" && url === "/api/leads") {
    try {
      const raw = await readBody(req);
      const body = raw ? JSON.parse(raw) : {};
      const result = await submitLead(env, body);
      res.writeHead(result.ok ? 200 : (result.status || 502), {
        "Content-Type": "application/json; charset=utf-8",
        "Access-Control-Allow-Origin": "*",
      });
      res.end(JSON.stringify(result));
    } catch (err) {
      res.writeHead(500, { "Content-Type": "application/json; charset=utf-8" });
      res.end(JSON.stringify({ ok: false, error: err instanceof Error ? err.message : "服务器错误" }));
    }
    return;
  }

  if (req.method !== "GET" && req.method !== "HEAD") {
    res.writeHead(405);
    res.end();
    return;
  }

  const target = safePath(url === "/" ? "/index.html" : url);
  if (!target) {
    res.writeHead(403);
    res.end();
    return;
  }

  let filePath = target;
  if (fs.existsSync(filePath) && fs.statSync(filePath).isDirectory()) {
    filePath = path.join(filePath, "index.html");
  }

  if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
    if (req.method === "HEAD") {
      res.writeHead(200);
      res.end();
      return;
    }
    sendFile(res, filePath);
    return;
  }

  const fallback = path.join(DIST, "index.html");
  if (fs.existsSync(fallback)) {
    if (req.method === "HEAD") {
      res.writeHead(200);
      res.end();
      return;
    }
    sendFile(res, fallback);
    return;
  }

  res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
  res.end("Not found");
});

if (!fs.existsSync(DIST)) {
  console.error("dist/ 不存在，请先运行 npm run build");
  process.exit(1);
}

server.listen(PORT, HOST, () => {
  const mode = env.FEISHU_LEAD_MODE || (env.FEISHU_WEBHOOK_URL ? "webhook" : "bitable");
  console.log(`BeforeShow fake-door (${mode})`);
  console.log(`  http://${HOST === "0.0.0.0" ? "localhost" : HOST}:${PORT}/`);
});