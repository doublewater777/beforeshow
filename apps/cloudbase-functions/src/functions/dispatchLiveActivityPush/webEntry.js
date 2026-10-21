import http from "node:http";
import { main } from "./entry.js";

const PORT = process.env.PORT || 9000;

const server = http.createServer(async (req, res) => {
  res.setHeader("Content-Type", "application/json");

  try {
    const result = await main({}, {}, {});
    res.statusCode = 200;
    res.end(JSON.stringify(result));
  } catch (error) {
    res.statusCode = 500;
    res.end(JSON.stringify({
      ok: false,
      error: { code: "INTERNAL_ERROR", message: error.message }
    }));
  }
});

server.listen(PORT, () => {
  console.log(`dispatchLiveActivityPush web server listening on port ${PORT}`);
});
