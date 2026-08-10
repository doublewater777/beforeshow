import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { detectPlatform } from "../src/functions/parseShowLink/platformDetector.js";

const OFFICIAL_TICKETMASTER_DOMAINS = [
  "ticketmaster.com",
  "ticketmaster.ca",
  "ticketmaster.co.uk",
  "ticketmaster.ie",
  "ticketmaster.com.au",
  "ticketmaster.co.nz",
  "ticketmaster.com.mx",
  "ticketmaster.at",
  "ticketmaster.be",
  "ticketmaster.com.br",
  "ticketmaster.ch",
  "ticketmaster.cl",
  "ticketmaster.co",
  "ticketmaster.cy",
  "ticketmaster.cz",
  "ticketmaster.de",
  "ticketmaster.dk",
  "ticketmaster.es",
  "ticketmaster.fi",
  "ticketmaster.fr",
  "ticketmaster.gr",
  "ticketmaster.it",
  "ticketmaster.nl",
  "ticketmaster.no",
  "ticketmaster.pe",
  "ticketmaster.ph",
  "ticketmaster.pl",
  "ticketmaster.se",
  "ticketmaster.sg",
  "ticketmaster.co.za",
  "ticketmaster.ae"
];

describe("Ticketmaster regional domains", () => {
  for (const domain of OFFICIAL_TICKETMASTER_DOMAINS) {
    it(`recognizes ${domain}`, () => {
      assert.equal(
        detectPlatform(`https://www.${domain}/example/event/ABC123`),
        "ticketmaster"
      );
    });
  }
});
