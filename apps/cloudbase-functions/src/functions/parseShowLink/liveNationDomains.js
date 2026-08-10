export const LIVE_NATION_DOMAINS = [
  "livenation.com",
  "livenation.asia",
  "livenation.com.au",
  "livenation.be",
  "livenation.ca",
  "livenation.cn",
  "livenation.cz",
  "livenation.dk",
  "livenation.ee",
  "livenation.fi",
  "livenation.fr",
  "livenation.de",
  "livenation.hk",
  "livenation.hu",
  "livenation.co.il",
  "livenation.it",
  "livenation.co.jp",
  "livenation.lt",
  "livenation.nl",
  "livenation.co.nz",
  "livenation.no",
  "livenation.pl",
  "livenation.qa",
  "livenation.sg",
  "livenation.co.za",
  "livenation.kr",
  "livenation.es",
  "livenation.se",
  "livenation.com.tw",
  "livenation.co.th",
  "livenation.ae",
  "livenation.co.uk",
  "livenation.app.link"
];

export function isLiveNationHost(host) {
  return LIVE_NATION_DOMAINS.some(
    (domain) => host === domain || host.endsWith(`.${domain}`)
  );
}

export function liveNationEventId(pathname) {
  return pathname.match(/-tickets-edp(\d+)\/?$/i)?.[1]
    ?? pathname.match(/\/event\/([^/?#]+)/i)?.[1]
    ?? null;
}
