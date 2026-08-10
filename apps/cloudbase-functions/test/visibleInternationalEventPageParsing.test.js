import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { parseVisibleEventPage } from "../src/functions/parseShowLink/ticketPageParser.js";

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
});
