import crypto from "node:crypto";

let cachedApiSession = null;

const SHOWSTART_H5_URL = "https://wap.showstart.com";
const SHOWSTART_API_URL = `${SHOWSTART_H5_URL}/v3`;
const SHOWSTART_VERSION = "997";
const SHOWSTART_USER_AGENT = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

export async function fetchShowStartDetail({ activityId, fetch: fetchImpl = globalThis.fetch }) {
  if (!fetchImpl) {
    throw new Error("Fetch API is not available");
  }

  const session = await getOrCreateApiSession(fetchImpl);
  const data = {
    activityId,
    coupon: "",
    shareId: "",
    previewPwd: ""
  };
  const json = await postShowStartApi({
    path: "/wap/activity/details",
    data,
    activityId,
    session,
    fetch: fetchImpl
  });

  if (json.state !== "1" || !json.result) {
    if (json.state === "token-clean-at") {
      cachedApiSession = null;
    }
    throw new Error(`ShowStart API error: ${json.msg ?? "unknown"}`);
  }

  return json.result;
}

async function getOrCreateApiSession(fetchImpl) {
  if (cachedApiSession && cachedApiSession.expiresAt > Date.now() + 60_000) {
    return cachedApiSession;
  }

  const session = createShowStartApiSession();
  const json = await postShowStartApi({
    path: "/waf/gettoken",
    data: {},
    session,
    fetch: fetchImpl
  });

  const accessToken = json.result?.accessToken;
  if (json.state !== "1" || !accessToken?.access_token) {
    throw new Error(`ShowStart token error: ${json.msg ?? "unknown"}`);
  }

  session.accessToken = accessToken.access_token;
  session.idToken = json.result?.idToken?.id_token ?? "";
  session.expiresAt = Number(accessToken.expire ?? 0) * 1000;
  cachedApiSession = session;
  return session;
}

async function postShowStartApi({ path, data, activityId = "", session, fetch: fetchImpl }) {
  const request = buildShowStartApiRequest({ path, data, activityId, session });
  const response = await fetchImpl(request.url, {
    method: "POST",
    headers: request.headers,
    body: request.body
  });
  const text = await response.text();

  try {
    return JSON.parse(text);
  } catch {
    throw new Error("ShowStart API returned invalid JSON");
  }
}

function buildShowStartApiRequest({ path, data, activityId, session }) {
  const traceId = `${randomString(32)}${Date.now()}`;
  const requestData = {
    ...data,
    st_flpv: data.st_flpv ?? session.stFlpv,
    sign: data.sign ?? "",
    trackPath: data.trackPath ?? ""
  };
  const body = JSON.stringify(requestData);
  const signPayload = [
    session.accessToken,
    "",
    session.idToken,
    "",
    "wap",
    session.deviceNo,
    body,
    path,
    SHOWSTART_VERSION,
    "wap",
    traceId
  ].join("");

  return {
    url: `${SHOWSTART_API_URL}${path}`,
    body,
    headers: {
      "content-type": "application/json",
      "user-agent": SHOWSTART_USER_AGENT,
      referer: `${SHOWSTART_H5_URL}/pages/activity/detail/detail?activityId=${activityId}`,
      cterminal: "wap",
      csappid: "wap",
      cusat: session.accessToken || "nil",
      cusut: "nil",
      cusit: session.idToken || "nil",
      cusid: "nil",
      cusname: "nil",
      cdeviceno: session.deviceNo,
      cuuserref: session.deviceNo,
      cversion: SHOWSTART_VERSION,
      ctrackpath: requestData.trackPath,
      csourcepath: "",
      st_flpv: requestData.st_flpv,
      crtraceid: traceId,
      crpsign: md5(signPayload),
      cdeviceinfo: encodeURI(JSON.stringify({
        vendorName: "",
        deviceMode: "iPhone",
        deviceName: "",
        systemName: "ios",
        systemVersion: "17.0",
        cpuMode: " ",
        cpuCores: "",
        cpuArch: "",
        memerySize: "",
        diskSize: "",
        network: "4G",
        resolution: "390*844",
        pixelResolution: ""
      }))
    }
  };
}

function createShowStartApiSession() {
  return {
    deviceNo: randomString(32).toLowerCase(),
    stFlpv: randomString(20),
    accessToken: "",
    idToken: "",
    expiresAt: 0
  };
}

function randomString(length) {
  const chars = `0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz${Date.now()}`;
  let result = "";
  for (let index = 0; index < length; index += 1) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

function md5(value) {
  return crypto.createHash("md5").update(value, "utf8").digest("hex");
}

export function parseShowStartDetail(result) {
  const site = result.site ?? {};
  const sessionUserInfos = result.sessionUserInfos ?? [];

  const activityName = result.activityName ?? "";
  const city = (site.cityName ?? "").replace(/市$/, "");
  const venueName = site.name ?? "";
  const venueAddr = site.address ?? "";

  const { date, startTime } = parseShowTime(result.showTime ?? "");
  const artist = extractArtists(sessionUserInfos);
  const artistAvatarURLs = extractArtistAvatarURLs(sessionUserInfos);

  const price = (result.price ?? "").replace(/^¥\s*/, "").trim();

  return {
    name: activityName,
    city,
    date,
    startTime,
    venueName,
    venueAddr,
    artist,
    coverImageURL: result.avatar ?? result.album?.[0] ?? "",
    artistAvatarURLs,
    priceRange: price,
    source: "showstart"
  };
}

function parseShowTime(showTime) {
  if (!showTime) {
    return { date: "", startTime: "" };
  }

  const match = showTime.match(/(\d{4})\.(\d{1,2})\.(\d{1,2})(?:[^\d]*)(\d{1,2}):(\d{2})?/);
  if (match) {
    const [, year, month, day, hour, minute] = match;
    return {
      date: `${year}-${month.padStart(2, "0")}-${day.padStart(2, "0")}`,
      startTime: hour && minute ? `${hour.padStart(2, "0")}:${minute}` : ""
    };
  }

  const dateOnlyMatch = showTime.match(/(\d{4})\.(\d{1,2})\.(\d{1,2})/);
  if (dateOnlyMatch) {
    const [, year, month, day] = dateOnlyMatch;
    return {
      date: `${year}-${month.padStart(2, "0")}-${day.padStart(2, "0")}`,
      startTime: ""
    };
  }

  return { date: "", startTime: "" };
}

function extractArtists(sessionUserInfos) {
  if (!Array.isArray(sessionUserInfos) || sessionUserInfos.length === 0) {
    return "";
  }

  const firstSession = sessionUserInfos[0];
  const userInfos = firstSession.userInfos ?? [];
  const names = userInfos
    .map((u) => u.name)
    .filter((name) => typeof name === "string" && name.trim().length > 0);

  return names.join(", ");
}

function extractArtistAvatarURLs(sessionUserInfos) {
  if (!Array.isArray(sessionUserInfos) || sessionUserInfos.length === 0) {
    return [];
  }

  const firstSession = sessionUserInfos[0];
  const userInfos = firstSession.userInfos ?? [];
  return userInfos
    .map((u) => u.avatar)
    .filter((url) => typeof url === "string" && url.trim().length > 0);
}
