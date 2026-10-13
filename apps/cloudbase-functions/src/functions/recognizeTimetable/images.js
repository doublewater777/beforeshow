const ALLOWED_MIME = new Set(["image/jpeg", "image/jpg", "image/png", "image/webp"]);
const MAX_IMAGES = 3;
/** Decoded bytes per image. CloudBase HTTP bodies are also capped; keep under ~4MB. */
const MAX_BYTES_PER_IMAGE = 4 * 1024 * 1024;
const MAX_TOTAL_BYTES = 5 * 1024 * 1024;

/**
 * Normalize request images from either:
 * - images: [{ mimeType, base64 }]
 * - imageBase64 + optional mimeType (single)
 */
export function parseImages(body = {}) {
  let raw = [];

  if (Array.isArray(body.images)) {
    raw = body.images;
  } else if (typeof body.imageBase64 === "string") {
    raw = [{
      mimeType: body.mimeType || "image/jpeg",
      base64: body.imageBase64
    }];
  }

  if (raw.length === 0) {
    return { ok: false, code: "IMAGE_REQUIRED", message: "At least one timetable image is required." };
  }

  if (raw.length > MAX_IMAGES) {
    return {
      ok: false,
      code: "TOO_MANY_IMAGES",
      message: `At most ${MAX_IMAGES} images are accepted per request.`
    };
  }

  const images = [];
  let totalBytes = 0;

  for (const item of raw) {
    if (!item || typeof item.base64 !== "string") {
      return { ok: false, code: "IMAGE_REQUIRED", message: "Each image needs a base64 payload." };
    }

    let mimeType = typeof item.mimeType === "string" ? item.mimeType.trim().toLowerCase() : "image/jpeg";
    if (mimeType === "image/jpg") {
      mimeType = "image/jpeg";
    }
    if (!ALLOWED_MIME.has(mimeType)) {
      return {
        ok: false,
        code: "IMAGE_UNSUPPORTED",
        message: "Only JPEG, PNG, and WebP images are supported."
      };
    }

    const base64 = stripDataUrl(item.base64.trim());
    if (!base64 || !/^[A-Za-z0-9+/=\s]+$/.test(base64)) {
      return { ok: false, code: "IMAGE_INVALID", message: "Image base64 is invalid." };
    }

    const compact = base64.replace(/\s+/g, "");
    const byteLength = Math.floor((compact.length * 3) / 4) -
      (compact.endsWith("==") ? 2 : compact.endsWith("=") ? 1 : 0);

    if (byteLength <= 0) {
      return { ok: false, code: "IMAGE_REQUIRED", message: "Image payload is empty." };
    }
    if (byteLength > MAX_BYTES_PER_IMAGE) {
      return {
        ok: false,
        code: "IMAGE_TOO_LARGE",
        message: `Each image must be at most ${MAX_BYTES_PER_IMAGE} bytes.`
      };
    }

    totalBytes += byteLength;
    if (totalBytes > MAX_TOTAL_BYTES) {
      return {
        ok: false,
        code: "IMAGE_TOO_LARGE",
        message: `Combined images must be at most ${MAX_TOTAL_BYTES} bytes.`
      };
    }

    images.push({ mimeType, base64: compact, byteLength });
  }

  return { ok: true, images };
}

function stripDataUrl(value) {
  const match = /^data:[^;]+;base64,(.+)$/s.exec(value);
  return match ? match[1] : value;
}
