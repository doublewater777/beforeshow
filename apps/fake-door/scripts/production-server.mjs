#!/usr/bin/env node

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DIST = path.resolve(__dirname, "..", "dist");
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

const server = http.createServer((req, res) => {
  const url = req.url || "/";

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
  console.log(`BeforeShow fake-door static server`);
  console.log(`  http://${HOST === "0.0.0.0" ? "localhost" : HOST}:${PORT}/`);
});