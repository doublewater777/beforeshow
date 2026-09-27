import http from "node:http";
import { main } from "./entry.js";

const PORT = process.env.PORT || 9000;

const server = http.createServer(async (req, res) => {
  res.setHeader("Content-Type", "application/json");

  if (req.method !== "GET") {
    res.statusCode = 405;
    res.end(JSON.stringify({
      ok: false,
      error: { code: "METHOD_NOT_ALLOWED", message: "Only GET is supported" }
    }));
    return;
  }

  try {
    const url = new URL(req.url ?? "/", "http://localhost");
    const result = await main({
      headers: req.headers,
      query: Object.fromEntries(url.searchParams.entries())
    }, {});

    res.statusCode = statusCode(result.error?.code);
    res.end(JSON.stringify(result));
  } catch (error) {
    res.statusCode = 500;
    res.end(JSON.stringify({
      ok: false,
      error: { code: "INTERNAL_ERROR", message: error.message }
    }));
  }
});

function statusCode(forErrorCode) {
  switch (forErrorCode) {
  case "ADMIN_UNAUTHORIZED":
    return 401;
  case "ADMIN_NOT_CONFIGURED":
    return 503;
  case "READ_FAILED":
    return 500;
  default:
    return 200;
  }
}

server.listen(PORT, () => {
  console.log(`listFeedback web server listening on port ${PORT}`);
});
