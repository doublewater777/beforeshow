#!/usr/bin/env node
/**
 * 生产/预览用最小代理：/api/leads → 飞书多维表格
 *
 * 模式 1（推荐，lark-cli 全自动）：
 *   FEISHU_LEAD_MODE=bitable
 *   FEISHU_BASE_TOKEN=appxxx
 *   FEISHU_TABLE_ID=tblxxx
 *
 * 模式 2（手动 UI 配置的 webhook）：
 *   FEISHU_WEBHOOK_URL=https://www.feishu.cn/flow/api/trigger-webhook/xxx
 */

import http from "node:http";
import { submitLead } from "./feishu-lead-handler.mjs";

const PORT = Number(process.env.PORT || 8787);
const env = process.env;

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

const server = http.createServer(async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  if (req.method !== "POST" || req.url !== "/api/leads") {
    res.writeHead(404, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "Not found" }));
    return;
  }

  try {
    const raw = await readBody(req);
    const body = raw ? JSON.parse(raw) : {};
    const result = await submitLead(env, body);

    res.writeHead(result.ok ? 200 : (result.status || 502), {
      "Content-Type": "application/json; charset=utf-8",
    });
    res.end(JSON.stringify(result));
  } catch (err) {
    res.writeHead(500, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: err instanceof Error ? err.message : "代理失败" }));
  }
});

server.listen(PORT, () => {
  const mode = env.FEISHU_LEAD_MODE || (env.FEISHU_WEBHOOK_URL ? "webhook" : "bitable");
  console.log(`Feishu lead proxy (${mode}) → http://localhost:${PORT}/api/leads`);
});