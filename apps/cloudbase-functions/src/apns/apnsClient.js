import crypto from "node:crypto";
import http2 from "node:http2";

export const APNS_TOPIC_SUFFIX = ".push-type.liveactivity";
export const DEFAULT_BUNDLE_ID = "com.doublewaterapps.beforeshow";

export function createApnsToken({ keyId, teamId, privateKeyPem, nowSeconds = Math.floor(Date.now() / 1000) }) {
  if (!keyId || !teamId || !privateKeyPem) {
    throw new Error("Missing APNs credentials (keyId, teamId, or privateKeyPem)");
  }

  const pem = normalizePrivateKey(privateKeyPem);
  const header = Buffer.from(JSON.stringify({ alg: "ES256", kid: keyId })).toString("base64url");
  const claims = Buffer.from(JSON.stringify({ iss: teamId, iat: nowSeconds })).toString("base64url");
  const message = `${header}.${claims}`;

  const signature = crypto.sign("sha256", Buffer.from(message), {
    key: pem,
    dsaEncoding: "ieee-p1363"
  }).toString("base64url");

  return `${message}.${signature}`;
}

export function normalizePrivateKey(raw) {
  if (raw.includes("-----BEGIN PRIVATE KEY-----")) {
    return raw.trim();
  }
  // Wrap raw base64 string with PEM header and footer
  const cleaned = raw.replace(/\s+/g, "");
  return `-----BEGIN PRIVATE KEY-----\n${cleaned}\n-----END PRIVATE KEY-----`;
}

export function buildActivityKitPayload({
  contentState,
  scheduledAt,
  staleAt,
  dismissalAt,
  isEnd = false,
  alert = null
}) {
  const timestamp = scheduledAt instanceof Date ? Math.floor(scheduledAt.getTime() / 1000) : (scheduledAt ?? Math.floor(Date.now() / 1000));
  const aps = {
    timestamp,
    event: isEnd ? "end" : "update",
    "content-state": contentState
  };

  if (staleAt) {
    aps["stale-date"] = staleAt instanceof Date ? Math.floor(staleAt.getTime() / 1000) : staleAt;
  }

  if (isEnd && dismissalAt) {
    aps["dismissal-date"] = dismissalAt instanceof Date ? Math.floor(dismissalAt.getTime() / 1000) : dismissalAt;
  }

  if (alert && alert.title && alert.body) {
    aps.alert = {
      title: alert.title,
      body: alert.body,
      sound: alert.sound ?? "default"
    };
  }

  return { aps };
}

export async function sendActivityKitPush({
  pushToken,
  payload,
  isProduction = false,
  bundleId = DEFAULT_BUNDLE_ID,
  keyId,
  teamId,
  privateKeyPem,
  transport = null
}) {
  if (!pushToken) {
    throw new Error("pushToken is required");
  }

  if (transport) {
    return transport({ pushToken, payload, isProduction, bundleId });
  }

  const token = createApnsToken({ keyId, teamId, privateKeyPem });
  const host = isProduction
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
  const topic = `${bundleId}${APNS_TOPIC_SUFFIX}`;
  const hasAlert = Boolean(payload?.aps?.alert);
  const bodyString = JSON.stringify(payload);

  return new Promise((resolve, reject) => {
    const client = http2.connect(host);

    client.on("error", (err) => {
      client.close();
      reject(err);
    });

    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${pushToken}`,
      authorization: `bearer ${token}`,
      "apns-push-type": "liveactivity",
      "apns-topic": topic,
      "apns-priority": hasAlert ? "10" : "5",
      "content-type": "application/json"
    });

    req.setEncoding("utf8");
    let responseData = "";
    let statusCode = 200;

    req.on("response", (headers) => {
      statusCode = Number(headers[":status"]);
    });

    req.on("data", (chunk) => {
      responseData += chunk;
    });

    req.on("end", () => {
      client.close();
      if (statusCode >= 200 && statusCode < 300) {
        resolve({ ok: true, statusCode });
      } else {
        let reason = responseData;
        try {
          const parsed = JSON.parse(responseData);
          reason = parsed.reason || responseData;
        } catch {}
        resolve({ ok: false, statusCode, reason });
      }
    });

    req.on("error", (err) => {
      client.close();
      reject(err);
    });

    req.write(bodyString);
    req.end();
  });
}
