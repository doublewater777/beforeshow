import http from "node:http";
import { assertAppAuthenticated } from "../../auth/appAuth.js";
import { providerSequence } from "../../config/modelProviders.js";
import { validateGenerationRequest } from "../../contracts/generationContracts.js";
import { generateSseFrames } from "./generateStream.js";
import { main } from "./index.js";

const PORT = process.env.PORT || 9000;

const server = http.createServer(async (req, res) => {
  if (req.method !== "POST") {
    res.statusCode = 405;
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({
      ok: false,
      error: {
        code: "METHOD_NOT_ALLOWED",
        message: "Only POST is supported"
      }
    }));
    return;
  }

  let body = "";
  req.on("data", (chunk) => {
    body += chunk;
  });

  req.on("end", async () => {
    let event = {};
    try {
      event = body.length > 0 ? JSON.parse(body) : {};
    } catch {
      res.statusCode = 400;
      res.setHeader("Content-Type", "application/json");
      res.end(JSON.stringify({
        ok: false,
        error: {
          code: "INVALID_JSON",
          message: "Request body must be JSON."
        }
      }));
      return;
    }

    const wantsStream = event.stream === true;

    if (!wantsStream) {
      res.setHeader("Content-Type", "application/json");
      try {
        const result = await main(event, {}, {});
        res.statusCode = 200;
        res.end(JSON.stringify(result));
      } catch (error) {
        res.statusCode = 500;
        res.end(JSON.stringify({
          ok: false,
          error: {
            code: error.code ?? "INTERNAL_ERROR",
            message: error.message
          }
        }));
      }
      return;
    }

    // SSE stream protocol for progressive setlist items.
    res.writeHead(200, {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no"
    });

    try {
      const auth = assertAppAuthenticated(event, {});
      const request = validateGenerationRequest(stripAppAuth(event));
      const providers = providerSequence(process.env);

      // Auth is accountless; include a quiet meta note without secrets.
      res.write(`event: meta\ndata: ${JSON.stringify({
        accountless: auth.accountless === true,
        type: request.type,
        stream: true
      })}\n\n`);

      for await (const frame of generateSseFrames(request, { providers, env: process.env })) {
        res.write(frame);
      }
      res.end();
    } catch (error) {
      res.write(`event: error\ndata: ${JSON.stringify({
        code: error.code ?? "INTERNAL_ERROR",
        message: error.message ?? "Stream failed."
      })}\n\n`);
      res.end();
    }
  });
});

function stripAppAuth(input) {
  if (input === null || typeof input !== "object" || Array.isArray(input)) {
    return input;
  }
  const { appInstanceId, appSignature, ...businessInput } = input;
  return businessInput;
}

server.listen(PORT, () => {
  console.log(`generate web server listening on port ${PORT}`);
});
