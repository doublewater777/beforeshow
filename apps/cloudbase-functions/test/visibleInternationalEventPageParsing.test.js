import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { parseVisibleEventPage, fetchAndParseTicketPage } from "../src/functions/parseShowLink/ticketPageParser.js";

describe("international visible ticket page fallback", () => {
  it("parses an AXS-style English event date and venue line", () => {
    const html = `<!doctype html>
      <html><head><title>The Fray Tickets - AXS</title></head><body>
        <div>Wed Aug 12, 2026 - 7:00 PM</div>
        <h1>The Fray</h1>
        <div>Summer of Light Tour</div>
        <div>Jacobs Pavilion, Cleveland, OH, United States</div>
        <div>2014 Sycamore Street, Cleveland, OH, 44113</div>
      </body></html>`;

    const draft = parseVisibleEventPage(html, { source: "axs" });
    assert.equal(draft.name, "The Fray");
    assert.equal(draft.date, "2026-08-12");
    assert.equal(draft.startTime, "19:00");
    assert.equal(draft.city, "Cleveland");
    assert.equal(draft.venueName, "Jacobs Pavilion");
    assert.match(draft.venueAddr, /2014 Sycamore Street/);
  });

  it("parses the current AXS expanded month format", () => {
    const html = `<!doctype html>
      <html><head><title>LE SSERAFIM Tickets - AXS</title></head><body>
        <div>Wed (Wednesday) Sep (September) 16, 2026 - 7:30 PM AEG</div>
        <h1>LE SSERAFIM</h1>
        <div>2026 LE SSERAFIM 'PUREFLOW' TOUR IN LOS ANGELES</div>
        <div>Crypto.com Arena, Los Angeles, CA, United States Ages: All Ages</div>
        <div>1111 S. Figueroa, Los Angeles, CA, 90015</div>
      </body></html>`;

    const draft = parseVisibleEventPage(html, { source: "axs" });
    assert.equal(draft.name, "LE SSERAFIM");
    assert.equal(draft.date, "2026-09-16");
    assert.equal(draft.startTime, "19:30");
    assert.equal(draft.city, "Los Angeles");
    assert.equal(draft.venueName, "Crypto.com Arena");
    assert.match(draft.venueAddr, /1111 S\. Figueroa/);
  });

  it("parses a DICE-style day-month line using a full date elsewhere on page", () => {
    const html = `<!doctype html>
      <html><head><title>Greg Mendez Tickets | DICE</title></head><body>
        <h1>Greg Mendez</h1>
        <div>Sid The Cat Auditorium</div>
        <div>Mon 10 Aug, 7:00 pm</div>
        <div>Gigs Pasadena</div>
        <div>8/10/2026 at Sid The Cat Auditorium</div>
        <div>Lineup</div><div>Greg Mendez, Maria BC</div>
        <div>1022 El Centro Street, South Pasadena, California 91030, United States</div>
      </body></html>`;

    const draft = parseVisibleEventPage(html, { source: "dice" });
    assert.equal(draft.name, "Greg Mendez");
    assert.equal(draft.date, "2026-08-10");
    assert.equal(draft.startTime, "19:00");
    assert.equal(draft.venueName, "Sid The Cat Auditorium");
    assert.equal(draft.artist, "Greg Mendez, Maria BC");
  });

  it("parses DICE ordinal dates from the current visible-page pattern", () => {
    const html = `<!doctype html>
      <html><head><title>Pacifica Tickets | DICE</title></head><body>
        <h1>Pacifica</h1>
        <div>Rough Trade Bristol</div>
        <div>Wed 13 May, 7:00 pm</div>
        <div>Gigs Bristol</div>
        <div>About</div>
        <div>DHP Presents</div>
        <div>Pacifica</div>
        <div>With Special Guests</div>
        <div>At Rough Trade Bristol</div>
        <div>13th May 2026</div>
        <div>Lineup</div><div>Pacifica</div>
        <div>Venue</div><div>Rough Trade Bristol</div>
        <div>3 New Bridewell, Nelson Street, Bristol BS1 2QD, United Kingdom</div>
      </body></html>`;

    const draft = parseVisibleEventPage(html, { source: "dice" });
    assert.equal(draft.name, "Pacifica");
    assert.equal(draft.date, "2026-05-13");
    assert.equal(draft.startTime, "19:00");
    assert.equal(draft.venueName, "Rough Trade Bristol");
    assert.match(draft.venueAddr, /New Bridewell/);
    assert.equal(draft.artist, "Pacifica");
  });

  it("supplements a JSON-LD DICE event with city and artist from visible text", async () => {
    const html = `<!doctype html>
      <html><head><title>Solstice Tickets | £23.15 | Aug 23 @ The 1865, Southampton | DICE</title></head><body>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "MusicEvent",
          "name": "Solstice",
          "startDate": "2026-08-23T19:00:00+01:00",
          "location": {
            "@type": "Place",
            "name": "The 1865",
            "address": "Brunswick Square, Southampton SO14 3AR, UK"
          }
        }
        </script>
        <h1>Solstice</h1>
        <div>Sun, Aug 23, 7:00 PM</div>
        <div>Gigs Southampton</div>
        <div>Lineup</div>
        <div>Solstice</div>
      </body></html>`;

    const fetch = async () => ({
      ok: true,
      status: 200,
      url: "https://dice.fm/event/yob8ov-solstice-23rd-aug-the-1865-southampton-tickets",
      text: async () => html
    });

    const draft = await fetchAndParseTicketPage({
      url: "https://dice.fm/event/yob8ov-solstice-23rd-aug-the-1865-southampton-tickets",
      source: "dice",
      fetch
    });

    assert.equal(draft.name, "Solstice");
    assert.equal(draft.date, "2026-08-23");
    assert.equal(draft.startTime, "19:00");
    assert.equal(draft.venueName, "The 1865");
    assert.equal(draft.venueAddr, "Brunswick Square, Southampton SO14 3AR, UK");
    assert.equal(draft.city, "Southampton");
    assert.equal(draft.artist, "Solstice");
  });

  it("skips a numeric lineup count and trims trailing 'and N more'", async () => {
    const html = `<!doctype html>
      <html><head><title>BOUNDARIES Tickets | DICE</title></head><body>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "MusicEvent",
          "name": "BOUNDARIES",
          "startDate": "2025-08-13T18:30:00-07:00",
          "location": {
            "@type": "Place",
            "name": "The Glass House",
            "address": "200 W 2nd St, Pomona, CA 91766, USA"
          }
        }
        </script>
        <h1>BOUNDARIES</h1>
        <div>Wed, 13 Aug 2025, 6:30 pm</div>
        <div>Gigs Los Angeles</div>
        <div>Lineup</div>
        <div>1</div>
        <div>Boundaries, Stick To Your Guns, Gates To Hell and 1 more</div>
      </body></html>`;

    const fetch = async () => ({
      ok: true,
      status: 200,
      url: "https://dice.fm/event/l82ngl-boundaries-13th-aug-the-glass-house-pomona-tickets",
      text: async () => html
    });

    const draft = await fetchAndParseTicketPage({
      url: "https://dice.fm/event/l82ngl-boundaries-13th-aug-the-glass-house-pomona-tickets",
      source: "dice",
      fetch
    });

    assert.equal(draft.city, "Los Angeles");
    assert.equal(draft.artist, "Boundaries, Stick To Your Guns, Gates To Hell");
  });

  it("parses Ticketmaster venue text attached to the date-time line", () => {
    const html = `<!doctype html>
      <html><head><title>KCRW Presents Thievery Corporation: 30th Anniversary Tour | Ticketmaster</title></head><body>
        <h1>KCRW Presents Thievery Corporation: 30th Anniversary Tour</h1>
        <div>Fri • Sep 11, 2026 • 8:00 PMYouTube Theater, Inglewood, CA</div>
      </body></html>`;

    const draft = parseVisibleEventPage(html, { source: "ticketmaster" });
    assert.equal(draft.name, "KCRW Presents Thievery Corporation: 30th Anniversary Tour");
    assert.equal(draft.date, "2026-09-11");
    assert.equal(draft.startTime, "20:00");
    assert.equal(draft.city, "Inglewood");
    assert.equal(draft.venueName, "YouTube Theater");
  });
});
